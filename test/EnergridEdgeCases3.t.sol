// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Energrid.sol";

contract EnergridEdgeCases3Test is Test {
    kWhToken kwhToken;
    CELToken celToken;
    Energy1155 energy1155;
    ContractFactory factory;
    
    address admin;
    address user1;
    address user2;

    function setUp() public {
        admin = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy contracts
        kwhToken = new kWhToken();
        celToken = new CELToken();
        energy1155 = new Energy1155("https://api.example.com/token/{id}");
        
        // Setup roles
        kwhToken.grantRole(kwhToken.MINTER_ROLE(), admin);
        celToken.grantRole(celToken.ISSUER_ROLE(), admin);
        energy1155.grantRole(energy1155.MINTER_ROLE(), admin);
    }

    function testSupplyLimitOverflow() public {
        // Test overflow in kWhToken
        uint256 maxAmount = kwhToken.MAX_SUPPLY();
        
        vm.expectRevert(ExceedsMaxSupply.selector);
        kwhToken.mint(user1, maxAmount + 1);

        // Test overflow in Energy1155
        uint256 kwhMaxSupply = energy1155.maxSupply(energy1155.KWH_ID());
        
        vm.expectRevert(ExceedsMaxSupply.selector);
        energy1155.mintKWh(user1, kwhMaxSupply + 1);
    }

    function testBatchMintingLimits() public {
        // Test batch size limit in kWhToken
        address[] memory recipients = new address[](51);
        uint256[] memory amounts = new uint256[](51);
        
        for(uint i = 0; i < 51; i++) {
            recipients[i] = address(uint160(i + 1));
            amounts[i] = 1 ether;
        }
        
        vm.expectRevert(BatchSizeLimit.selector);
        kwhToken.mintBatch(recipients, amounts);

        // Test array length mismatch
        recipients = new address[](2);
        amounts = new uint256[](3);
        
        vm.expectRevert(ArrayLengthMismatch.selector);
        kwhToken.mintBatch(recipients, amounts);
    }

    function testPauseStateTransitions() public {
        // Test pausing logic in all contracts
        kwhToken.pause();
        celToken.pause();
        energy1155.pause();
        
        assertTrue(kwhToken.paused());
        assertTrue(celToken.paused());
        assertTrue(energy1155.paused());

        // Test operations while paused
        vm.expectRevert(ContractPaused.selector);
        kwhToken.mint(user1, 1 ether);

        vm.expectRevert(ContractPaused.selector);
        celToken.mintCertificate(user1, "test");

        vm.expectRevert(ContractPaused.selector);
        energy1155.mintKWh(user1, 1 ether);

        // Test unpausing
        kwhToken.unpause();
        celToken.unpause();
        energy1155.unpause();
        
        assertFalse(kwhToken.paused());
        assertFalse(celToken.paused());
        assertFalse(energy1155.paused());
    }

    function testCertificateRevocationStates() public {
        // Mint certificate
        uint256 tokenId = celToken.mintCertificate(user1, "test");
        
        // Test revocation
        celToken.revokeCertificate(tokenId);
        assertTrue(celToken.isRevoked(tokenId));
        
        // Test operations on revoked certificate
        vm.expectRevert(CertificateIsRevoked.selector);
        celToken.tokenURI(tokenId);

        vm.prank(user1);
        vm.expectRevert(CertificateIsRevoked.selector);
        celToken.transferFrom(user1, user2, tokenId);

        // Test revoking already revoked certificate
        vm.expectRevert(CertificateAlreadyRevoked.selector);
        celToken.revokeCertificate(tokenId);
    }

    function testFactoryDeploymentValidation() public {
        factory = new ContractFactory(
            address(kwhToken),
            address(celToken),
            address(kwhToken)
        );
        
        // Grant required roles to the factory
        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), admin);
        factory.grantRole(factory.DEPLOYER_ROLE(), admin);

        // Test invalid address inputs
        vm.expectRevert();
        factory.deployTradeContract(
            address(0),  // invalid seller
            user2,
            1 ether,
            100 ether,
            block.timestamp + 1 days,
            bytes32(0)
        );

        // Test same address for buyer and seller
        vm.expectRevert();
        factory.deployTradeContract(
            user1,
            user1,  // same as seller
            1 ether,
            100 ether,
            block.timestamp + 1 days,
            bytes32(0)
        );

        // Test invalid deadline
        vm.expectRevert();
        factory.deployTradeContract(
            user1,
            user2,
            1 ether,
            100 ether,
            block.timestamp,  // deadline must be in future
            bytes32(0)
        );
    }

    function testNumericOverflowCases() public {
        // Test overflow in price calculation
        factory = new ContractFactory(
            address(kwhToken),
            address(celToken),
            address(kwhToken)
        );

        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), admin);
        factory.grantRole(factory.DEPLOYER_ROLE(), admin);

        // Try to create trade with values that would cause overflow
        uint256 maxPrice = type(uint256).max / 2;
        uint256 amount = 3;

        // Use generic vm.expectRevert() since the specific error might vary
        vm.expectRevert();
        factory.deployTradeContract(
            user1,
            user2,
            maxPrice,
            amount,
            block.timestamp + 1 days,
            bytes32(0)
        );
    }
}
