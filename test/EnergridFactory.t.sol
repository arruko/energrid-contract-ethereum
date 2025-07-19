// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Energrid.sol";
import "./mocks/MockERC20.sol";

contract EnergridFactoryTest is Test {
    ContractFactory factory;
    kWhToken kwhTemplate;
    CELToken celTemplate;
    MockERC20 paymentTemplate;
    EnergyTradeContract implementation;
    
    address admin = address(this);
    address deployer = address(1);
    address seller = address(2);
    address buyer = address(3);

    function setUp() public {
        // Deploy template contracts
        kwhTemplate = new kWhToken();
        celTemplate = new CELToken();
        paymentTemplate = new MockERC20("Test Token", "TEST");

        // Set up roles for template contracts
        vm.startPrank(admin);
        kwhTemplate.grantRole(kwhTemplate.DEFAULT_ADMIN_ROLE(), admin);
        kwhTemplate.grantRole(kwhTemplate.MINTER_ROLE(), admin);
        celTemplate.grantRole(celTemplate.DEFAULT_ADMIN_ROLE(), admin);
        celTemplate.grantRole(celTemplate.ISSUER_ROLE(), admin);

        // Deploy factory and grant roles
        factory = new ContractFactory(
            address(kwhTemplate),
            address(celTemplate),
            address(paymentTemplate)
        );

        // Grant roles to factory
        kwhTemplate.grantRole(kwhTemplate.MINTER_ROLE(), address(factory));
        celTemplate.grantRole(celTemplate.ISSUER_ROLE(), address(factory));
        factory.grantRole(factory.DEPLOYER_ROLE(), deployer);
        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();
    }

    function testFactoryDeployment() public {
        vm.startPrank(deployer);
        
        // Deploy trade contract
        address tradeContract = factory.deployTradeContract(
            seller,
            buyer,
            1 ether,
            100,
            block.timestamp + 1 days,
            bytes32(uint256(1))
        );
        
        assertTrue(factory.isValidContract(tradeContract));
        assertEq(factory.deployedContracts(0), tradeContract);
        
        vm.stopPrank();
    }

    function testPredictableAddress() public {
        bytes32 salt = bytes32(uint256(1));
        
        address predicted = factory.predictTradeContractAddress(
            seller,
            buyer,
            1 ether,
            100,
            block.timestamp + 1 days,
            salt
        );
        
        vm.startPrank(deployer);
        address deployed = factory.deployTradeContract(
            seller,
            buyer,
            1 ether,
            100,
            block.timestamp + 1 days,
            salt
        );
        vm.stopPrank();
        
        assertEq(predicted, deployed);
    }

    function testContractRemoval() public {
        vm.startPrank(deployer);
        address tradeContract = factory.deployTradeContract(
            seller,
            buyer,
            1 ether,
            100,
            block.timestamp + 1 days,
            bytes32(uint256(1))
        );
        vm.stopPrank();
        
        // Remove contract
        factory.removeContract(tradeContract);
        
        assertFalse(factory.isValidContract(tradeContract));
        assertEq(factory.getContractCount(), 0);
    }

    function testUnauthorizedOperations() public {
        vm.startPrank(buyer);
        
        // Try unauthorized deployment
        vm.expectRevert();
        factory.deployTradeContract(
            seller,
            buyer,
            1 ether,
            100,
            block.timestamp + 1 days,
            bytes32(uint256(1))
        );
        
        // Try unauthorized removal
        vm.expectRevert();
        factory.removeContract(address(1));
        
        vm.stopPrank();
    }

    function testInvalidRegistration() public {
        vm.startPrank(deployer);
        
        // Try to register zero address
        vm.expectRevert(InvalidAddress.selector);
        factory.register(address(0));
        
        // Try to register non-contract address
        vm.expectRevert(NotContract.selector);
        factory.register(address(1));
        
        vm.stopPrank();
    }

    function testDuplicateRegistration() public {
        vm.startPrank(deployer);
        
        // Deploy a contract
        address tradeContract = factory.deployTradeContract(
            seller,
            buyer,
            1 ether,
            100,
            block.timestamp + 1 days,
            bytes32(uint256(1))
        );
        
        // Try to register the same contract again
        vm.expectRevert(AlreadyRegistered.selector);
        factory.register(tradeContract);
        
        vm.stopPrank();
    }

    function testContractListing() public {
        vm.startPrank(deployer);
        
        // Deploy multiple contracts
        address[] memory deployed = new address[](3);
        for(uint i = 0; i < 3; i++) {
            deployed[i] = factory.deployTradeContract(
                seller,
                buyer,
                1 ether,
                100,
                block.timestamp + 1 days,
                bytes32(uint256(i + 1))
            );
        }
        
        vm.stopPrank();
        
        // Check contract listing
        address[] memory listed = factory.getAllContracts();
        assertEq(listed.length, 3);
        
        for(uint i = 0; i < 3; i++) {
            assertEq(listed[i], deployed[i]);
            assertTrue(factory.isValidContract(deployed[i]));
        }
    }

}


