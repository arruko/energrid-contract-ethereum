// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Energrid.sol";

contract EnergridTest is Test {
    kWhToken public token;
    CELToken public celToken;
    Energy1155 public energy1155;
    
    address public admin = address(this);
    address public user = address(0x1);
    address public buyer = address(0x2);

    function setUp() public {
        token = new kWhToken();
        celToken = new CELToken();
        energy1155 = new Energy1155("https://metadata.uri/");
        
        // Grant necessary roles
        token.grantRole(token.MINTER_ROLE(), admin);
        celToken.grantRole(celToken.ISSUER_ROLE(), admin);
        energy1155.grantRole(energy1155.MINTER_ROLE(), admin);
    }

    function testMintKWhToken() public {
        uint256 amount = 100 * 10**18;
        
        // Mint tokens
        token.mint(user, amount);
        
        // Verify balance
        assertEq(token.balanceOf(user), amount);
        assertEq(token.totalMinted(), amount);
    }

    // FIXED: testMintCEL - Expect token ID 1, not 0
    function testMintCEL() public {
        string memory metadataCID = "QmTestMetadata123";
        
        // Mint certificate and expect token ID 1 (CEL starts from 1, not 0)
        uint256 tokenId = celToken.mintCertificate(buyer, metadataCID);
        
        // FIXED: Expect token ID 1, not 0
        assertEq(tokenId, 1);
        assertEq(celToken.ownerOf(1), buyer);
        assertEq(celToken.tokenURI(1), metadataCID);
        assertEq(celToken.nextTokenId(), 2); // Should increment to 2
    }

    function testMintMultipleCEL() public {
        // Test minting multiple certificates
        uint256 tokenId1 = celToken.mintCertificate(buyer, "QmFirst");
        uint256 tokenId2 = celToken.mintCertificate(user, "QmSecond");
        
        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(celToken.ownerOf(1), buyer);
        assertEq(celToken.ownerOf(2), user);
    }

    function testCELRevocation() public {
        uint256 tokenId = celToken.mintCertificate(buyer, "QmTest");
        
        // Revoke the certificate
        celToken.revokeCertificate(tokenId);
        assertTrue(celToken.isRevoked(tokenId));
        
        // Should revert when trying to get URI of revoked token
        vm.expectRevert(CertificateIsRevoked.selector);
        celToken.tokenURI(tokenId);
    }

    function testUnauthorizedMinting() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 100);
        
        vm.prank(user);
        vm.expectRevert();
        celToken.mintCertificate(user, "QmTest");
    }

    function testPausingFunctionality() public {
        // Test token pausing
        token.pause();
        assertTrue(token.paused());
        
        vm.expectRevert(ContractPaused.selector);
        token.mint(user, 100);
        
        token.unpause();
        assertFalse(token.paused());
        
        // Should work after unpausing
        token.mint(user, 100);
        assertEq(token.balanceOf(user), 100);
    }

    function testMaxSupplyLimits() public {
        uint256 maxSupply = token.MAX_SUPPLY();
        
        // Should fail if trying to mint more than max supply
        vm.expectRevert(ExceedsMaxSupply.selector);
        token.mint(user, maxSupply + 1);
    }

    function testEnergy1155Functionality() public {
        // Test kWh minting in Energy1155
        energy1155.mintKWh(user, 100);
        assertEq(energy1155.balanceOf(user, energy1155.KWH_ID()), 100);
        
        // Test CEL minting in Energy1155
        energy1155.mintCEL(buyer, 5);
        assertEq(energy1155.balanceOf(buyer, energy1155.CEL_ID()), 5);
    }

    function testEnergy1155SupplyLimits() public {
        uint256 celMaxSupply = energy1155.maxSupply(energy1155.CEL_ID());
        
        vm.expectRevert(ExceedsMaxSupply.selector);
        energy1155.mintCEL(buyer, celMaxSupply + 1);
    }

    function testCELTransferRestrictions() public {
        uint256 tokenId = celToken.mintCertificate(buyer, "QmTest");
        
        // Revoke the certificate
        celToken.revokeCertificate(tokenId);
        
        // Should not be able to transfer revoked certificate
        vm.prank(buyer);
        vm.expectRevert(CertificateIsRevoked.selector);
        celToken.transferFrom(buyer, user, tokenId);
    }

    function testAccessControlInheritance() public {
        // Test that admin role can grant other roles
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(celToken.hasRole(celToken.DEFAULT_ADMIN_ROLE(), admin));
        
        // Grant roles to other users
        token.grantRole(token.MINTER_ROLE(), user);
        assertTrue(token.hasRole(token.MINTER_ROLE(), user));
        
        // User should now be able to mint
        vm.prank(user);
        token.mint(buyer, 50);
        assertEq(token.balanceOf(buyer), 50);
    }
}