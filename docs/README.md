# Energrid Smart Contracts Documentation

## Overview

Energrid is a comprehensive energy trading platform built on Ethereum, featuring multiple token standards and sophisticated trading mechanisms. This documentation provides complete deployment and operational guidance for production environments.

## Table of Contents

1. [Architecture Overview](./architecture.md)
2. [AWS Deployment Guide](./deployment/aws-deployment.md)
3. [Smart Contract Reference](./contracts/README.md)
4. [Security Guidelines](./security/security-guide.md)
5. [Monitoring & Observability](./monitoring/README.md)
6. [Operations Runbook](./operations/runbook.md)
7. [Disaster Recovery](./operations/disaster-recovery.md)
8. [API Documentation](./api/README.md)

## Quick Start for DevOps

### Prerequisites
- AWS Account with appropriate permissions
- Ethereum node access (Infura/Alchemy recommended)
- Private keys securely managed (AWS Secrets Manager)
- Docker and AWS CLI configured

### Production Deployment Checklist
- [ ] Review [Security Guidelines](./security/security-guide.md)
- [ ] Configure [AWS Infrastructure](./deployment/aws-deployment.md)
- [ ] Deploy contracts using [Deployment Scripts](./deployment/scripts/)
- [ ] Setup [Monitoring](./monitoring/README.md)
- [ ] Test [Disaster Recovery](./operations/disaster-recovery.md) procedures

## Contract Addresses (Production)

| Contract | Mainnet Address | Network | Status |
|----------|-----------------|---------|--------|
| kWhToken | `TBD` | Ethereum Mainnet | Pending |
| CELToken | `TBD` | Ethereum Mainnet | Pending |
| Energy1155 | `TBD` | Ethereum Mainnet | Pending |
| ContractFactory | `TBD` | Ethereum Mainnet | Pending |

## Support

For production issues:
- **Critical**: Create incident in AWS Systems Manager
- **Non-Critical**: File issue in repository
- **Security**: Follow [Security Guidelines](./security/security-guide.md)

## Version

Current Version: v1.0.0
Solidity Version: ^0.8.19
Test Coverage: 88.19% lines, 86.92% functions
