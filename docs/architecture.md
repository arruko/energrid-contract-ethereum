# Energrid Architecture Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Frontend Layer                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   Web3 DApp     │  │   Admin Portal  │  │   Mobile App    │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
                        ┌───────┴───────┐
                        │   API Gateway │
                        │   (AWS ALB)   │
                        └───────┬───────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                      Application Layer                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   Trade API     │  │   Monitor API   │  │   Admin API     │ │
│  │   (ECS Fargate) │  │   (ECS Fargate) │  │   (ECS Fargate) │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
                        ┌───────┴───────┐
                        │   Ethereum    │
                        │   JSON-RPC    │
                        │   (Infura)    │
                        └───────┬───────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                      Blockchain Layer                           │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐│
│  │  kWhToken   │ │  CELToken   │ │ Energy1155  │ │   Factory   ││
│  │   (ERC20)   │ │  (ERC721)   │ │  (ERC1155)  │ │  Contract   ││
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘│
│                                │                                │
│  ┌─────────────────────────────┴─────────────────────────────┐  │
│  │              EnergyTradeContract (Dynamic)               │  │
│  │              Deployed via CREATE2 Factory               │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Smart Contract Components

### Core Contracts

#### 1. kWhToken (ERC20)
- **Purpose**: Represents kilowatt-hour energy units
- **Features**: Mintable, Burnable, Pausable, Role-based access
- **Max Supply**: 1,000,000,000 kWh
- **Decimals**: 18

#### 2. CELToken (ERC721)
- **Purpose**: Clean Energy Certificates (Non-fungible)
- **Features**: Mintable, Revocable, Metadata URI
- **Use Case**: Proof of clean energy generation/consumption

#### 3. Energy1155 (ERC1155)
- **Purpose**: Multi-token standard for various energy assets
- **Token Types**:
  - kWh Units (ID: 1)
  - Carbon Credits (ID: 2)
  - Renewable Certificates (ID: 3)

#### 4. ContractFactory
- **Purpose**: Deploys EnergyTradeContract instances
- **Features**: CREATE2 deterministic deployment, Role management
- **Gas Optimization**: Predictable addresses for trade contracts

#### 5. EnergyTradeContract (Dynamic)
- **Purpose**: Individual energy trade execution
- **Features**: Escrow, Commit-Reveal, Dispute resolution
- **Lifecycle**: Created → Active → Committed → Delivered → Completed

### Role-Based Access Control

```
DEFAULT_ADMIN_ROLE
├── MINTER_ROLE (kWhToken, Energy1155)
├── PAUSER_ROLE (All contracts)
├── ISSUER_ROLE (CELToken)
├── DEPLOYER_ROLE (Factory)
├── TRADE_ROLE (EnergyTradeContract)
└── ARBITRATOR_ROLE (EnergyTradeContract)
```

## Data Flow

### Trade Creation Flow
1. **Initiation**: Factory.deployTradeContract()
2. **Role Setup**: Factory grants admin role to trade contract
3. **Participant Setup**: Admin grants TRADE_ROLE to buyer/seller
4. **Escrow Deposit**: Buyer deposits kWh tokens
5. **Trade Execution**: Commit-reveal mechanism for delivery

### Token Flow
1. **Energy Generation**: Mint kWh tokens to producer
2. **Certificate Issuance**: Mint CEL tokens for clean energy
3. **Trade Escrow**: Transfer tokens to trade contract
4. **Delivery**: Release escrowed tokens to seller
5. **Settlement**: Update balances and mint certificates

## Security Architecture

### Access Control
- OpenZeppelin AccessControl implementation
- Multi-signature requirement for admin operations
- Role-based permissions with least privilege

### Economic Security
- Escrow mechanism prevents trade default
- Commit-reveal prevents front-running
- Dispute resolution with arbitrator role

### Technical Security
- Reentrancy protection (ReentrancyGuard)
- Pausable emergency stops
- Overflow protection (Solidity ^0.8.19)

## Gas Optimization

### Design Patterns
- **CREATE2 Factory**: Predictable addresses, reduced lookup costs
- **Batch Operations**: Process multiple transactions efficiently
- **Packed Structs**: Minimize storage slots
- **Event Indexing**: Efficient log filtering

### Estimated Gas Costs
| Operation | Gas Cost | USD (50 gwei) |
|-----------|----------|---------------|
| Deploy Factory | ~2,500,000 | ~$125 |
| Deploy Trade | ~800,000 | ~$40 |
| kWh Transfer | ~65,000 | ~$3.25 |
| CEL Mint | ~85,000 | ~$4.25 |
| Trade Complete | ~120,000 | ~$6 |

## Scalability Considerations

### Layer 2 Compatibility
- Contracts designed for Polygon/Arbitrum deployment
- Minimal external dependencies
- Standard interface compliance

### State Management
- Efficient storage patterns
- Event-driven architecture
- Minimal on-chain state

### Integration Points
- JSON-RPC API compatibility
- Web3 standard compliance
- Multi-wallet support
