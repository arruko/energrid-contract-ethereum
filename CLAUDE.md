# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Building and Testing
- `forge build` - Build the smart contracts
- `forge test` - Run all tests
- `forge test --match-test <test_name>` - Run a specific test
- `forge test -vvv` - Run tests with verbose output (shows detailed traces)
- `forge test --gas-report` - Run tests with gas usage report

### Formatting and Utilities
- `forge fmt` - Format Solidity code
- `forge snapshot` - Generate gas snapshots for tests
- `anvil` - Start local Ethereum node for development

### Deployment and Interaction
- `forge script script/Deploy.s.sol:DeployScript --rpc-url <url> --private-key <key>` - Deploy contracts
- `cast <subcommand>` - Interact with deployed contracts (e.g., `cast call`, `cast send`)

## Architecture

This is an **energy trading smart contract system** built with Foundry. The core architecture consists of:

### Main Contracts (src/Energrid.sol)

1. **kWhToken (ERC20)** - Represents kilowatt-hour energy units
   - Access control with `MINTER_ROLE` and `PAUSER_ROLE`
   - Max supply: 1 billion tokens
   - Pausable transfers

2. **CELToken (ERC721)** - Clean Energy Certificates for completed trades
   - Access control with `ISSUER_ROLE` and `PAUSER_ROLE`
   - Revokable certificates
   - Max supply: 1 million certificates

3. **Energy1155 (ERC1155)** - Multi-token contract for both kWh and CEL tokens
   - Supports both energy units (ID: 1) and certificates (ID: 2)
   - Packed supply data for gas optimization

4. **EnergyTradeContract** - Core trading contract managing escrow and delivery
   - Immutable trade parameters (seller, buyer, price, total kWh, deadline)
   - Escrow-based payment system with IERC20 payment tokens
   - Batch delivery tracking with metadata CIDs
   - Signature verification for delivery confirmation
   - Dispute resolution system with arbitrator role
   - Comprehensive state management (active, cancelled, completed, disputed)

5. **ContractFactory** - Registry for deployed trade contracts
   - Role-based registration system
   - Contract validation and tracking

### Security Features
- **Custom errors** for gas optimization instead of string reverts
- **ReentrancyGuard** with optimized implementation
- **Pausable** functionality for emergency stops
- **Access control** using OpenZeppelin's role-based system
- **Signature verification** for delivery confirmations
- **Struct packing** to minimize storage costs

### Key Design Patterns
- **Check-Effects-Interactions (CEI)** pattern in critical functions
- **Immutable contract parameters** for gas optimization
- **Packed structs** (`TradeState`, `SupplyData`, `DeliveryBatch`) for storage efficiency
- **Role-based access control** throughout the system
- **Event logging** for comprehensive off-chain tracking

### Testing
The test suite (`test/EnergyTradeContract.t.sol`) covers extensive edge cases including:
- Access control violations
- Timing constraints and deadline enforcement
- Amount validation and overflow protection
- State transition edge cases
- Reentrancy attack prevention
- Token integration failures
- Gas optimization verification

The contracts use OpenZeppelin dependencies and are designed for production deployment with comprehensive security considerations.