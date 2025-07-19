// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Energrid.sol";

contract EnergridEdgeCases2Test is Test {
    // Constants for roles
    bytes32 constant TRADE_ROLE = keccak256("TRADE_ROLE");
    bytes32 constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    // Test state variables
    address admin;
    address seller;
    address buyer;
    address arbitrator;
    
    kWhToken kwhToken;
    CELToken celToken;
    ContractFactory factory;
    EnergyTradeContract trade;

    function setUp() public {
        admin = address(this);
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        arbitrator = makeAddr("arbitrator");

        vm.startPrank(admin);

        // Deploy token contracts
        kwhToken = new kWhToken();
        celToken = new CELToken();

        // Setup roles for tokens
        // KwhToken setup
        kwhToken.grantRole(kwhToken.DEFAULT_ADMIN_ROLE(), admin);
        kwhToken.grantRole(kwhToken.MINTER_ROLE(), admin);
        kwhToken.grantRole(kwhToken.PAUSER_ROLE(), admin);

        // CELToken setup
        celToken.grantRole(celToken.DEFAULT_ADMIN_ROLE(), admin);
        celToken.grantRole(celToken.ISSUER_ROLE(), admin);
        celToken.grantRole(celToken.PAUSER_ROLE(), admin);

        // Deploy factory
        factory = new ContractFactory(
            address(kwhToken),
            address(celToken),
            address(kwhToken)  // Using kWhToken as payment token
        );

        // Setup factory roles
        factory.grantRole(DEFAULT_ADMIN_ROLE, admin);
        factory.grantRole(factory.DEPLOYER_ROLE(), admin);

        // Grant permissions to factory
        kwhToken.grantRole(kwhToken.MINTER_ROLE(), address(factory));
        celToken.grantRole(celToken.ISSUER_ROLE(), address(factory));

        // Setup initial state
        kwhToken.mint(admin, 10000 ether);
        kwhToken.mint(buyer, 1000 ether);
        kwhToken.mint(seller, 1000 ether);

        vm.stopPrank();
    }    function testBitFlagOperations() public {
        setupTradeContract();

        // Test initial state
        (bool active,,,,,,) = trade.getTradeStatus();
        assertTrue(active, "Trade should start active");

        // Test flag transitions
        vm.prank(seller);
        trade.raiseDispute("Test dispute");
        assertTrue(trade.isDisputed(), "Trade should be disputed");

        // Test resolving dispute
        vm.prank(arbitrator);
        trade.resolveDispute("Resolved", true);
        assertFalse(trade.isDisputed(), "Trade should not be disputed after resolution");
    }

    function testCommitRevealLogic() public {
        setupTradeContract();
        
        // Buyer deposits escrow for the delivery (10 kWh at 1 ether per kWh = 10 ether)
        vm.startPrank(buyer);
        kwhToken.approve(address(trade), type(uint256).max);
        trade.depositEscrow(10 ether);
        vm.stopPrank();

        // Test early reveal
        bytes32 commitment = keccak256(abi.encodePacked(uint256(10), "metadata", uint256(1), seller));
        
        vm.prank(seller);
        trade.commitDelivery(commitment);

        vm.prank(seller);
        vm.expectRevert(CommitmentTooEarly.selector);
        trade.revealDelivery(10, "metadata", 1);

        // Wait for commitment delay
        vm.warp(block.timestamp + 1 minutes);

        vm.prank(seller);
        trade.revealDelivery(10, "metadata", 1);
    }

    function testNonceManagement() public {
        setupTradeContract();

        // Buyer deposits escrow for the delivery (10 kWh at 1 ether per kWh = 10 ether)
        vm.startPrank(buyer);
        kwhToken.approve(address(trade), type(uint256).max);
        trade.depositEscrow(10 ether);
        vm.stopPrank();

        assertEq(trade.getNonce(buyer), 0, "Initial nonce should be 0");
        
        // Create dummy signature for invalid sig test
        bytes memory invalidSig = hex"1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890";
        
        // Test delivery with invalid signature
        vm.expectRevert(); // Use generic revert since ECDSA might throw different errors
        vm.prank(seller);
        trade.deliver(10, "test", invalidSig);
        
        // Nonce should not increment after failed delivery
        assertEq(trade.getNonce(buyer), 0, "Nonce should not increment after failed delivery");
        
        // Now test without signature
        vm.prank(seller);
        trade.deliver(10, "test", "");
        
        // Nonce should still be 0 as no signature was used
        assertEq(trade.getNonce(buyer), 0, "Nonce should not increment for non-signed delivery");
    }

    function testDeadlineHandling() public {
        uint256 deadline = block.timestamp + 1 days;
        setupTradeContract();

        // Test near deadline warning
        vm.warp(deadline - 23 hours);
        (bool nearDeadline, bool pastDeadline) = trade.checkDeadlineStatus();
        assertTrue(nearDeadline, "Should warn when near deadline");
        assertFalse(pastDeadline, "Should not be past deadline yet");

        // Test deadline warning event
        vm.expectEmit(true, false, false, true);
        emit DeadlineWarning(address(trade), 23 hours);
        trade.emitDeadlineWarning();

        // Test past deadline
        vm.warp(deadline + 1);
        (nearDeadline, pastDeadline) = trade.checkDeadlineStatus();
        assertFalse(nearDeadline, "Should not show near deadline when past it");
        assertTrue(pastDeadline, "Should be past deadline");
    }

    function testEscrowUtilization() public {
        setupTradeContract();
        kwhToken.mint(buyer, 200 ether);

        // Approve tokens
        vm.prank(buyer);
        kwhToken.approve(address(trade), type(uint256).max);

        // Test partial deposit (50 ether out of 100 ether total = 50%)
        vm.prank(buyer);
        trade.depositEscrow(50 ether);

        uint256 utilization = trade.getEscrowUtilization();
        assertEq(utilization, 5000, "50% utilization should be 5000 basis points");

        // Test batch deposit
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 25 ether;
        amounts[1] = 25 ether;

        vm.prank(buyer);
        trade.depositEscrowBatch(amounts);

        utilization = trade.getEscrowUtilization();
        assertEq(utilization, 10000, "100% utilization should be 10000 basis points");
    }

    event DeadlineWarning(address indexed trade, uint256 timeRemaining);

    function setupTradeContract() internal {
        // Deploy and setup trade contract
        vm.startPrank(admin);

        // Deploy contract
        trade = EnergyTradeContract(factory.deployTradeContract(
            seller,
            buyer,
            1 ether,
            100, // 100 kWh (not 100 ether)
            block.timestamp + 1 days,
            bytes32(0)
        ));

        // Factory is the initial admin, so factory grants admin role to test admin
        vm.startPrank(address(factory));
        trade.grantRole(DEFAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        // Now admin can grant other roles
        vm.startPrank(admin);
        trade.grantRole(TRADE_ROLE, seller);
        trade.grantRole(ARBITRATOR_ROLE, arbitrator);

        // Grant all roles to test contract address to avoid AccessControl errors
        trade.grantRole(DEFAULT_ADMIN_ROLE, address(this));
        trade.grantRole(TRADE_ROLE, address(this));
        trade.grantRole(ARBITRATOR_ROLE, address(this));
        
        // Set up token permissions
        kwhToken.grantRole(kwhToken.MINTER_ROLE(), address(trade));
        celToken.grantRole(celToken.ISSUER_ROLE(), address(trade));

        vm.stopPrank();

        // Setup token approvals
        vm.startPrank(buyer);
        kwhToken.approve(address(trade), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(seller);
        kwhToken.approve(address(trade), type(uint256).max);
        vm.stopPrank();
    }
}
