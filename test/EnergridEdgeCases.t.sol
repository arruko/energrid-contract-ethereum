// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Energrid.sol";

contract EnergridEdgeCasesTest is Test {
    kWhToken public token;
    CELToken public celToken;
    Energy1155 public energy1155;
    
    address public admin = address(this);
    address public user = address(0x1);
    address public buyer = address(0x2);
    address public unauthorized = address(0x3);

    function setUp() public {
        token = new kWhToken();
        celToken = new CELToken();
        energy1155 = new Energy1155("https://metadata.uri/");
        
        // Grant necessary roles
        token.grantRole(token.MINTER_ROLE(), admin);
        celToken.grantRole(celToken.ISSUER_ROLE(), admin);
        energy1155.grantRole(energy1155.MINTER_ROLE(), admin);
    }

    // === Interface Compliance Tests ===
    
    function testInterfaceSupport() public view {
        // Token inherits from AccessControl
        assertTrue(token.supportsInterface(type(IAccessControl).interfaceId));
        
        // CELToken inherits from ERC721 and AccessControl
        assertTrue(celToken.supportsInterface(type(IERC721).interfaceId));
        assertTrue(celToken.supportsInterface(type(IAccessControl).interfaceId));
        
        // Energy1155 inherits from ERC1155 and AccessControl
        assertTrue(energy1155.supportsInterface(type(IERC1155).interfaceId));
        assertTrue(energy1155.supportsInterface(type(IAccessControl).interfaceId));
    }

    // === Batch Operation Tests ===

    function testBatchMintingEdgeCases() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = user;
        recipients[1] = buyer;
        amounts[0] = 50 * 10**18;
        amounts[1] = 50 * 10**18;
        
        // Test successful batch mint
        token.mintBatch(recipients, amounts);
        assertEq(token.balanceOf(user), amounts[0]);
        assertEq(token.balanceOf(buyer), amounts[1]);
        
        // Test array length mismatch
        uint256[] memory wrongAmounts = new uint256[](1);
        wrongAmounts[0] = 100 * 10**18;
        vm.expectRevert(ArrayLengthMismatch.selector);
        token.mintBatch(recipients, wrongAmounts);
        
        // Test batch size limit
        address[] memory tooManyRecipients = new address[](51);
        uint256[] memory tooManyAmounts = new uint256[](51);
        for(uint i = 0; i < 51; i++) {
            tooManyRecipients[i] = address(uint160(i + 1));
            tooManyAmounts[i] = 1 * 10**18;
        }
        vm.expectRevert(BatchSizeLimit.selector);
        token.mintBatch(tooManyRecipients, tooManyAmounts);
    }

    function testBatchCELMinting() public {
        address[] memory recipients = new address[](2);
        string[] memory metadataCIDs = new string[](2);
        recipients[0] = user;
        recipients[1] = buyer;
        metadataCIDs[0] = "QmTest1";
        metadataCIDs[1] = "QmTest2";

        uint256[] memory tokenIds = celToken.mintBatchCertificates(recipients, metadataCIDs);
        assertEq(tokenIds.length, 2);
        assertEq(celToken.ownerOf(tokenIds[0]), user);
        assertEq(celToken.ownerOf(tokenIds[1]), buyer);
        
        // Test empty metadata
        metadataCIDs[0] = "";
        vm.expectRevert(EmptyMetadata.selector);
        celToken.mintBatchCertificates(recipients, metadataCIDs);
    }

    // === Supply Limit Tests ===

    function testSupplyLimitBoundaries() public {
        uint256 maxSupply = token.MAX_SUPPLY();
        
        // Test exact max supply
        token.mint(user, maxSupply);
        assertEq(token.totalMinted(), maxSupply);
        
        // Test exceeding max supply by 1
        vm.expectRevert(ExceedsMaxSupply.selector);
        token.mint(user, 1);
        
        // Test overflow scenarios
        token = new kWhToken();
        token.grantRole(token.MINTER_ROLE(), admin);
        uint256 nearMaxSupply = maxSupply - 1;
        token.mint(user, nearMaxSupply);
        vm.expectRevert(ExceedsMaxSupply.selector);
        token.mint(user, 2);
    }

    function testEnergy1155SupplyBoundaries() public {
        uint256 kwhMaxSupply = energy1155.maxSupply(energy1155.KWH_ID());
        uint256 celMaxSupply = energy1155.maxSupply(energy1155.CEL_ID());

        // Test kWh supply limits
        energy1155.mintKWh(user, kwhMaxSupply);
        vm.expectRevert(ExceedsMaxSupply.selector);
        energy1155.mintKWh(user, 1);

        // Test CEL supply limits
        energy1155.mintCEL(buyer, celMaxSupply);
        vm.expectRevert(ExceedsMaxSupply.selector);
        energy1155.mintCEL(buyer, 1);
    }

    // === State Transition Tests ===

    function testPausingStateTransitions() public {
        // Test pausing transitions
        token.pause();
        assertTrue(token.paused());
        
        vm.expectRevert(ContractPaused.selector);
        token.pause();
        
        // Test unpausing transitions
        token.unpause();
        assertFalse(token.paused());
        
        vm.expectRevert(ContractNotPaused.selector);
        token.unpause();
        
        // Test transfers while paused
        token.mint(user, 100);
        token.pause();
        
        vm.startPrank(user);
        vm.expectRevert(ContractPaused.selector);
        token.transfer(buyer, 50);
        vm.stopPrank();
    }

    function testCELRevocationStates() public {
        // Test certificate lifecycle
        uint256 tokenId = celToken.mintCertificate(user, "QmTest");
        
        // Test double revocation
        celToken.revokeCertificate(tokenId);
        vm.expectRevert(CertificateAlreadyRevoked.selector);
        celToken.revokeCertificate(tokenId);
        
        // Test transfer of revoked certificate
        vm.startPrank(user);
        vm.expectRevert(CertificateIsRevoked.selector);
        celToken.transferFrom(user, buyer, tokenId);
        vm.stopPrank();
        
        // Test URI access of revoked certificate
        vm.expectRevert(CertificateIsRevoked.selector);
        celToken.tokenURI(tokenId);
    }

    // === Access Control Tests ===

    function testRoleManagement() public {
        bytes32 minterRole = token.MINTER_ROLE();
        bytes32 pauserRole = token.PAUSER_ROLE();
        assertTrue(token.hasRole(pauserRole, admin));
        
        // Test role assignment
        token.grantRole(minterRole, user);
        assertTrue(token.hasRole(minterRole, user));
        
        // Test role revocation
        token.revokeRole(minterRole, user);
        assertFalse(token.hasRole(minterRole, user));
        
        // Test unauthorized role management
        vm.startPrank(unauthorized);
        vm.expectRevert();
        token.grantRole(minterRole, unauthorized);
        vm.stopPrank();
    }

    function testUnauthorizedOperations() public {
        vm.startPrank(unauthorized);
        
        // Test unauthorized minting
        vm.expectRevert();
        token.mint(unauthorized, 100);
        
        // Test unauthorized pausing
        vm.expectRevert();
        token.pause();
        
        // Test unauthorized certificate operations
        vm.expectRevert();
        celToken.mintCertificate(unauthorized, "QmTest");
        
        vm.stopPrank();
    }

    // === Error Condition Tests ===

    function testInvalidInputs() public {
        // Test zero address
        vm.expectRevert(InvalidAddress.selector);
        token.mint(address(0), 100);
        
        // Test empty metadata
        vm.expectRevert(EmptyMetadata.selector);
        celToken.mintCertificate(user, "");
        
        // Test invalid token ID
        vm.expectRevert(TokenDoesNotExist.selector);
        celToken.revokeCertificate(999);
    }

    // === Event Emission Tests ===

    function testEventEmissions() public {
        // Test TokensMinted event
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(user, 100);
        token.mint(user, 100);
        
        // Test CertificateIssued event
        vm.expectEmit(true, true, false, true);
        emit CertificateIssued(buyer, 1, "QmTest");
        celToken.mintCertificate(buyer, "QmTest");
        
        // Test Paused/Unpaused events
        vm.expectEmit(true, false, false, false);
        emit Paused(address(this));
        token.pause();
        
        vm.expectEmit(true, false, false, false);
        emit Unpaused(address(this));
        token.unpause();
    }

    // === Events ===
    event TokensMinted(address indexed to, uint256 amount);
    event CertificateIssued(address indexed to, uint256 indexed tokenId, string metadataCID);
    event Paused(address account);
    event Unpaused(address account);
}
