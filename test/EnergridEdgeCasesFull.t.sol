// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Energrid.sol";

contract EnergridEdgeCasesFullTest is Test {
    // Token contracts
    kWhToken kwhToken;
    CELToken celToken;
    Energy1155 energy1155;
    ContractFactory factory;
    EnergyTradeContract trade;
    
    // Test addresses
    address admin;
    address seller;
    address buyer;
    address arbitrator;
    address user1;
    address user2;

    function setUp() public {
        admin = address(this);
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        arbitrator = makeAddr("arbitrator");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy contracts
        kwhToken = new kWhToken();
        celToken = new CELToken();
        energy1155 = new Energy1155("https://api.example.com/token/{id}");
        
        // Setup roles for token contracts
        kwhToken.grantRole(kwhToken.DEFAULT_ADMIN_ROLE(), admin);
        kwhToken.grantRole(kwhToken.MINTER_ROLE(), admin);
        kwhToken.grantRole(kwhToken.PAUSER_ROLE(), admin);

        celToken.grantRole(celToken.DEFAULT_ADMIN_ROLE(), admin);
        celToken.grantRole(celToken.ISSUER_ROLE(), admin);
        celToken.grantRole(celToken.PAUSER_ROLE(), admin);

        energy1155.grantRole(energy1155.DEFAULT_ADMIN_ROLE(), admin);
        energy1155.grantRole(energy1155.MINTER_ROLE(), admin);
        energy1155.grantRole(energy1155.PAUSER_ROLE(), admin);

        // Deploy factory with proper roles
        factory = new ContractFactory(
            address(kwhToken),
            address(celToken),
            address(kwhToken) // Using kWhToken as payment token for testing
        );

        // Setup factory roles - ensure admin has all required roles
        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), admin);
        factory.grantRole(factory.DEPLOYER_ROLE(), admin);

        // Ensure admin is granted DEFAULT_ADMIN_ROLE by the factory
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE on factory");
    }

    function testTradeContractBitFlags() public {
        trade = EnergyTradeContract(factory.deployTradeContract(
            seller, 
            buyer,
            1 ether,
            100 ether,
            block.timestamp + 1 days,
            bytes32(0)
        ));

        vm.startPrank(address(factory));
        trade.grantRole(trade.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();

        vm.startPrank(admin);
        trade.grantRole(trade.TRADE_ROLE(), seller);
        trade.grantRole(trade.TRADE_ROLE(), buyer);
        trade.grantRole(trade.ARBITRATOR_ROLE(), arbitrator);
        vm.stopPrank();

        // Test initial state
        (bool active,,,,,,) = trade.getTradeStatus();
        assertTrue(active, "Trade should start active");

        // Test dispute flag transitions
        vm.startPrank(seller);
        trade.raiseDispute("Test dispute");
        assertTrue(trade.isDisputed(), "Trade should be disputed");
        vm.stopPrank();

        // Resolve dispute as admin first granting arbitrator role
        vm.startPrank(admin);
        trade.grantRole(trade.ARBITRATOR_ROLE(), arbitrator);
        vm.stopPrank();

        // Now act as arbitrator
        vm.startPrank(arbitrator);
        trade.resolveDispute("Resolved", true);
        assertFalse(trade.isDisputed(), "Trade should not be disputed after resolution");
        vm.stopPrank();
    }

    function testCommitRevealMechanism() public {
        trade = EnergyTradeContract(factory.deployTradeContract(
            seller,
            buyer,
            1 ether,
            100, // 100 kWh (not 100 ether) 
            block.timestamp + 1 days,
            bytes32(0)
        ));

        vm.startPrank(address(factory));
        trade.grantRole(trade.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();

        vm.startPrank(admin);
        trade.grantRole(trade.TRADE_ROLE(), seller);
        trade.grantRole(trade.TRADE_ROLE(), buyer);

        // Verify roles are set correctly
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE on factory");
        assertTrue(trade.hasRole(trade.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE on trade");

        // Grant required roles and setup
        trade.grantRole(trade.TRADE_ROLE(), seller);
        trade.grantRole(trade.TRADE_ROLE(), buyer);
        
        // Grant all roles to test contract address to avoid AccessControl errors
        trade.grantRole(trade.DEFAULT_ADMIN_ROLE(), address(this));
        trade.grantRole(trade.TRADE_ROLE(), address(this));
        trade.grantRole(trade.ARBITRATOR_ROLE(), address(this));
        
        // Grant token roles to seller and trade participants
        kwhToken.grantRole(kwhToken.MINTER_ROLE(), seller);
        kwhToken.grantRole(kwhToken.MINTER_ROLE(), buyer);
        // Grant MINTER_ROLE to the trade contract so it can mint tokens during delivery
        kwhToken.grantRole(kwhToken.MINTER_ROLE(), address(trade));
        celToken.grantRole(celToken.ISSUER_ROLE(), seller);
        celToken.grantRole(celToken.ISSUER_ROLE(), buyer);
        
        assertTrue(trade.hasRole(trade.TRADE_ROLE(), seller), "Seller should have TRADE_ROLE");
        
        // Fund buyer with kWh tokens and approve
        kwhToken.mint(buyer, 1000 ether);
        vm.stopPrank();

        // Calculate required escrow (for 10 kWh at 1 ether per kWh = 10 ether)
        uint256 escrowAmount = 10 ether; // Enough for the delivery test
        
        // Buyer deposits escrow
        vm.startPrank(buyer);
        kwhToken.approve(address(trade), escrowAmount);
        trade.depositEscrow(escrowAmount);
        vm.stopPrank();

        // Test commitment flow
        bytes32 commitment = keccak256(abi.encodePacked(uint256(10), "metadata", uint256(1), seller));
        
        vm.startPrank(seller);

        // Submit commitment
        trade.commitDelivery(commitment);
        
        // Try early reveal - should fail
        vm.expectRevert(CommitmentTooEarly.selector);
        trade.revealDelivery(10, "metadata", 1);
        vm.stopPrank();

        // Wait required time and reveal successfully
        vm.warp(block.timestamp + 1 minutes);
        vm.prank(seller);
        trade.revealDelivery(10, "metadata", 1);

        // Verify final admin permissions
        assertTrue(trade.hasRole(trade.DEFAULT_ADMIN_ROLE(), admin), "Admin should maintain DEFAULT_ADMIN_ROLE");
    }

    function testDeadlineLogic() public {
        uint256 deadline = block.timestamp + 1 days;
        
        trade = EnergyTradeContract(factory.deployTradeContract(
            seller,
            buyer,
            1 ether,
            100 ether,
            deadline,
            bytes32(0)
        ));

        // Test near deadline
        vm.warp(deadline - 23 hours);
        (bool nearDeadline, bool pastDeadline) = trade.checkDeadlineStatus();
        assertTrue(nearDeadline, "Should warn when near deadline");
        assertFalse(pastDeadline, "Should not be past deadline yet");

        // Test deadline warning event
        vm.expectEmit(true, false, false, true);
        emit DeadlineWarning(address(trade), 23 hours);
        trade.emitDeadlineWarning();

        // Test past deadline state
        vm.warp(deadline + 1);
        (nearDeadline, pastDeadline) = trade.checkDeadlineStatus();
        assertFalse(nearDeadline, "Should not show near deadline when past it");
        assertTrue(pastDeadline, "Should be past deadline");

        // Test automatic penalty after deadline
        trade.processAutomaticPenalty();
        (bool active,,,,,,) = trade.getTradeStatus();
        assertFalse(active, "Trade should be inactive after penalty");
    }

    function testSupplyLimits() public {
        // Test kWhToken limits
        uint256 maxAmount = kwhToken.MAX_SUPPLY();
        vm.expectRevert(ExceedsMaxSupply.selector);
        kwhToken.mint(user1, maxAmount + 1);

        // Test Energy1155 limits
        uint256 kwhMaxSupply = energy1155.maxSupply(energy1155.KWH_ID());
        vm.expectRevert(ExceedsMaxSupply.selector);
        energy1155.mintKWh(user1, kwhMaxSupply + 1);
    }

    function testBatchOperations() public {
        // Test batch size limits
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

    function testPauseLogic() public {
        // Test pause transitions
        kwhToken.pause();
        celToken.pause();
        energy1155.pause();
        
        assertTrue(kwhToken.paused());
        assertTrue(celToken.paused());
        assertTrue(energy1155.paused());

        // Test paused operations
        vm.expectRevert(ContractPaused.selector);
        kwhToken.mint(user1, 1 ether);

        vm.expectRevert(ContractPaused.selector);
        celToken.mintCertificate(user1, "test");

        vm.expectRevert(ContractPaused.selector);
        energy1155.mintKWh(user1, 1 ether);

        // Test unpause
        kwhToken.unpause();
        celToken.unpause();
        energy1155.unpause();
        
        assertFalse(kwhToken.paused());
        assertFalse(celToken.paused());
        assertFalse(energy1155.paused());
    }

    function testCertificateLifecycle() public {
        // Test minting
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

        // Test double revocation
        vm.expectRevert(CertificateAlreadyRevoked.selector);
        celToken.revokeCertificate(tokenId);
    }

    function testFactoryValidations() public {
        // Test invalid addresses
        vm.expectRevert();
        factory.deployTradeContract(
            address(0),
            user2,
            1 ether,
            100 ether,
            block.timestamp + 1 days,
            bytes32(0)
        );

        // Test same buyer/seller
        vm.expectRevert();
        factory.deployTradeContract(
            user1,
            user1,
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
            block.timestamp,
            bytes32(0)
        );
    }

    function testNumericOverflows() public {
        // Test price calculation overflow
        uint256 maxPrice = type(uint256).max / 2;
        uint256 amount = 3;

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

    event DeadlineWarning(address indexed trade, uint256 timeRemaining);
}
