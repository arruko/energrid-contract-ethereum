// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Energrid.sol";
import "./mocks/MockERC20.sol";

contract EnergyTradeBatchTest is Test {
    EnergyTradeContract trade;
    kWhToken token;
    CELToken cel;
    MockERC20 paymentToken;
    Energy1155 energy1155;
    
    uint256 constant BUYER_PRIVATE_KEY = 123;
    address seller = address(1);
    address buyer = vm.addr(BUYER_PRIVATE_KEY);
    address admin = address(this);
    address arbiter = address(4);
    
    uint256 constant PRICE_PER_KWH = 1 ether;
    uint256 constant TOTAL_KWH = 100;
    uint256 constant ESCROW_AMOUNT = 100 ether;

    function setUp() public {
        // Deploy tokens
        token = new kWhToken();
        cel = new CELToken();
        paymentToken = new MockERC20("USD Coin", "USDC");

        // Grant roles to admin
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), admin);
        cel.grantRole(cel.ISSUER_ROLE(), admin);
        cel.grantRole(cel.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();

        // Mint payment tokens for buyer
        paymentToken.mint(buyer, 1_000_000 ether);

        // Deploy trade contract
        vm.startPrank(admin);
        trade = new EnergyTradeContract(
            seller,
            buyer,
            PRICE_PER_KWH,
            TOTAL_KWH,
            block.timestamp + 1 days,
            address(token),
            address(cel),
            address(paymentToken)
        );
        
        // Set up trade contract roles and permissions
        trade.grantRole(trade.DEFAULT_ADMIN_ROLE(), admin);
        trade.grantRole(trade.TRADE_ROLE(), seller);
        trade.grantRole(trade.ARBITRATOR_ROLE(), arbiter);
        token.grantRole(token.MINTER_ROLE(), address(trade));
        cel.grantRole(cel.ISSUER_ROLE(), address(trade));
        vm.stopPrank();
        
        // Set up buyer's escrow
        vm.startPrank(buyer);
        paymentToken.approve(address(trade), type(uint256).max);
        trade.depositEscrow(ESCROW_AMOUNT);
        vm.stopPrank();
    }

    // === Batch Delivery Tests ===

    function testBatchDelivery() public {
        uint256[] memory amounts = new uint256[](2);
        string[] memory metadataCIDs = new string[](2);
        
        amounts[0] = 40;
        amounts[1] = 60;
        metadataCIDs[0] = "QmBatch1";
        metadataCIDs[1] = "QmBatch2";

        vm.startPrank(seller);
        trade.deliverBatch(amounts, metadataCIDs);
        vm.stopPrank();

        assertEq(trade.deliveredKWh(), TOTAL_KWH);
        assertTrue(token.balanceOf(buyer) == TOTAL_KWH);
    }

    function testBatchDeliveryValidations() public {
        uint256[] memory amounts = new uint256[](2);
        string[] memory metadataCIDs = new string[](2);
        amounts[0] = 40;
        amounts[1] = 70; // Exceeds total
        metadataCIDs[0] = "QmBatch1";
        metadataCIDs[1] = "QmBatch2";

        vm.startPrank(seller);
        vm.expectRevert(ExceedsAgreedAmount.selector);
        trade.deliverBatch(amounts, metadataCIDs);
        vm.stopPrank();
    }

    function testBatchSizeLimits() public {
        uint256[] memory amounts = new uint256[](11);
        string[] memory metadataCIDs = new string[](11);
        
        for(uint i = 0; i < 11; i++) {
            amounts[i] = 5;
            metadataCIDs[i] = "QmBatch";
        }

        vm.startPrank(seller);
        vm.expectRevert(BatchSizeLimit.selector);
        trade.deliverBatch(amounts, metadataCIDs);
        vm.stopPrank();
    }

    // === Commit-Reveal Tests ===

    function testCommitRevealDelivery() public {
        uint256 amount = 50;
        string memory metadataCID = "QmTest";
        uint256 nonce = 1;
        
        // Create commitment
        bytes32 commitment = keccak256(abi.encodePacked(amount, metadataCID, nonce, seller));
        
        vm.startPrank(seller);
        trade.commitDelivery(commitment);
        
        // Try to reveal too early
        vm.expectRevert(CommitmentTooEarly.selector);
        trade.revealDelivery(amount, metadataCID, nonce);
        
        // Wait required time
        skip(1 minutes);
        
        // Reveal should succeed
        trade.revealDelivery(amount, metadataCID, nonce);
        vm.stopPrank();
        
        assertEq(trade.deliveredKWh(), amount);
    }

    function testInvalidCommitReveal() public {
        uint256 amount = 50;
        string memory metadataCID = "QmTest";
        uint256 nonce = 1;
        
        vm.startPrank(seller);
        vm.expectRevert(InvalidCommitment.selector);
        trade.revealDelivery(amount, metadataCID, nonce);
        vm.stopPrank();
    }

    // === Signature Verification Tests ===

    function testSignedDelivery() public {
        uint256 amount = 50;
        string memory metadataCID = "QmTest";
        
        // Create signature
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("EnergyTradeContract"),
            keccak256("1"),
            block.chainid,
            address(trade)
        ));
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Delivery(uint256 amount,string metadataCID,uint256 nonce,address contract,uint256 deadline)"),
            amount,
            keccak256(bytes(metadataCID)),
            trade.getNonce(buyer),
            address(trade),
            trade.deadline()
        ));
        
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));
        
        // Use the constant private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BUYER_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(seller);
        trade.deliver(amount, metadataCID, signature);
        vm.stopPrank();
        
        assertEq(trade.deliveredKWh(), amount);
        
        assertEq(trade.deliveredKWh(), amount);
    }

    // === Status and Progress Tests ===

    function testTradeProgress() public {
        vm.startPrank(seller);
        trade.deliver(25, "QmTest1");
        
        (
            bool active,
            bool cancelled,
            bool completed,
            bool disputed,
            uint256 delivered,
            uint256 remaining,
            uint256 timeLeft
        ) = trade.getTradeStatus();
        
        assertTrue(active);
        assertFalse(cancelled);
        assertFalse(completed);
        assertFalse(disputed);
        assertEq(delivered, 25);
        assertEq(remaining, 75);
        assertTrue(timeLeft > 0);
        
        // Complete the trade
        trade.deliver(75, "QmTest2");
        
        (, , completed, , delivered, remaining,) = trade.getTradeStatus();
        assertTrue(completed);
        assertEq(delivered, 100);
        assertEq(remaining, 0);
        vm.stopPrank();
    }

    function testDeadlineWarnings() public {
        // Skip to near deadline
        skip(23 hours);
        
        (bool nearDeadline, bool pastDeadline) = trade.checkDeadlineStatus();
        assertTrue(nearDeadline);
        assertFalse(pastDeadline);
        
        vm.expectEmit(true, false, false, true);
        emit DeadlineWarning(address(trade), 1 hours);
        trade.emitDeadlineWarning();
    }

    // === Events ===
    event DeadlineWarning(address indexed trade, uint256 timeRemaining);
}

