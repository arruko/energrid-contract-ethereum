# Energrid Security Guide

## Overview

This document outlines comprehensive security measures, best practices, and procedures for the Energrid smart contract platform. All production deployments must adhere to these security guidelines.

## Security Architecture

### Defense in Depth

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                        │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐   │
│  │   WAF/CDN   │ │   API Rate  │ │   Input Validation  │   │
│  │  Protection │ │   Limiting  │ │   & Sanitization   │   │
│  └─────────────┘ └─────────────┘ └─────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                               │
┌─────────────────────────────────────────────────────────────┐
│                  Infrastructure Layer                       │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐   │
│  │   Network   │ │  Identity & │ │   Encryption at     │   │
│  │ Segmentation│ │    Access   │ │   Rest & Transit    │   │
│  └─────────────┘ └─────────────┘ └─────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                               │
┌─────────────────────────────────────────────────────────────┐
│                   Smart Contract Layer                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐   │
│  │    Access   │ │ Reentrancy  │ │   Emergency Pause   │   │
│  │   Control   │ │ Protection  │ │     Mechanisms      │   │
│  └─────────────┘ └─────────────┘ └─────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Smart Contract Security

### Access Control Implementation

#### Role-Based Security Matrix

| Role | Contract | Permissions | Risk Level |
|------|----------|-------------|------------|
| `DEFAULT_ADMIN_ROLE` | All | Full admin access | **Critical** |
| `MINTER_ROLE` | kWhToken, Energy1155 | Mint tokens | **High** |
| `PAUSER_ROLE` | All | Emergency pause | **High** |
| `ISSUER_ROLE` | CELToken | Issue certificates | **Medium** |
| `DEPLOYER_ROLE` | Factory | Deploy contracts | **Medium** |
| `TRADE_ROLE` | EnergyTradeContract | Execute trades | **Medium** |
| `ARBITRATOR_ROLE` | EnergyTradeContract | Resolve disputes | **Low** |

#### Multi-Signature Requirements

**Critical Operations** (3/5 multi-sig required):
- Granting/revoking `DEFAULT_ADMIN_ROLE`
- Contract upgrades
- Emergency pause/unpause
- Treasury operations

**High-Risk Operations** (2/3 multi-sig required):
- Granting/revoking `MINTER_ROLE`
- Setting contract parameters
- Role transfers

### Reentrancy Protection

All external calls implement `ReentrancyGuard`:
```solidity
contract EnergyTradeContract is ReentrancyGuard {
    function deliverEnergy(uint256 amount) external nonReentrant {
        // Safe external calls
    }
}
```

**Protected Functions**:
- Token transfers
- Escrow operations
- External contract calls
- State-changing operations with external dependencies

### Economic Security

#### Escrow Mechanism
- **Pre-trade Validation**: Buyer must deposit sufficient kWh tokens
- **Atomic Operations**: Trade completion or full refund
- **Slashing Conditions**: Penalties for failed deliveries
- **Dispute Resolution**: Arbitrator intervention for contested trades

#### Supply Limits
```solidity
// Maximum supply constraints
uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1B kWh

modifier withinSupplyLimit(uint256 amount) {
    require(totalSupply() + amount <= MAX_SUPPLY, "ExceedsMaxSupply");
    _;
}
```

### Input Validation

#### Address Validation
```solidity
modifier validAddress(address addr) {
    require(addr != address(0), "InvalidAddress");
    require(addr != address(this), "SelfReference");
    _;
}
```

#### Amount Validation
```solidity
modifier validAmount(uint256 amount) {
    require(amount > 0, "ZeroAmount");
    require(amount <= MAX_SUPPLY, "ExceedsMaxSupply");
    _;
}
```

#### Deadline Validation
```solidity
modifier validDeadline(uint256 deadline) {
    require(deadline > block.timestamp, "InvalidDeadline");
    require(deadline <= block.timestamp + 365 days, "DeadlineTooFar");
    _;
}
```

## Infrastructure Security

### AWS Security Configuration

#### VPC Security
```yaml
# Network ACLs
resource "aws_network_acl_rule" "private_inbound" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  port_range {
    from = 3000
    to   = 3000
  }
  cidr_block = "10.0.0.0/16"
}

# Security Groups (Least Privilege)
resource "aws_security_group_rule" "alb_to_ecs" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs.id
}
```

#### IAM Policies
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:energrid/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/energrid/*"
    }
  ]
}
```

### Secrets Management

#### AWS Secrets Manager Implementation
```bash
# Create secret with automatic rotation
aws secretsmanager create-secret \
    --name "energrid/admin-private-key" \
    --description "Admin private key for Energrid contracts" \
    --secret-string "$ADMIN_PRIVATE_KEY" \
    --replica-regions Region=us-west-2

# Configure automatic rotation (if applicable)
aws secretsmanager update-secret \
    --secret-id "energrid/admin-private-key" \
    --description "Admin private key with automatic rotation"
```

#### Key Rotation Policy
- **Private Keys**: Manual rotation every 90 days
- **API Keys**: Automatic rotation every 30 days
- **Database Passwords**: Automatic rotation every 7 days
- **TLS Certificates**: Automatic renewal 30 days before expiration

### Encryption

#### Data at Rest
- **EBS Volumes**: AES-256 encryption
- **RDS**: Encryption enabled with AWS KMS
- **S3 Buckets**: Server-side encryption with AWS KMS
- **Secrets Manager**: Automatic encryption with dedicated KMS keys

#### Data in Transit
- **API Communication**: TLS 1.3 only
- **Database Connections**: SSL/TLS required
- **Inter-service Communication**: mTLS within VPC
- **Blockchain RPC**: HTTPS with certificate pinning

## Monitoring and Detection

### Security Monitoring

#### CloudWatch Alarms
```yaml
# Suspicious API activity
resource "aws_cloudwatch_metric_alarm" "suspicious_api_calls" {
  alarm_name          = "energrid-suspicious-api-activity"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "4XXError"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "High number of 4XX errors detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

# Failed authentication attempts
resource "aws_cloudwatch_metric_alarm" "auth_failures" {
  alarm_name          = "energrid-auth-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "AuthenticationFailures"
  namespace           = "Energrid/Security"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Multiple authentication failures detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}
```

#### Smart Contract Monitoring
```bash
#!/bin/bash
# monitor-contracts.sh

# Monitor for unauthorized role grants
FACTORY_ADDRESS=$(aws ssm get-parameter --name /energrid/contracts/factory --query Parameter.Value --output text)
RPC_URL=$(aws ssm get-parameter --name /energrid/ethereum/mainnet-rpc --with-decryption --query Parameter.Value --output text)

# Check for RoleGranted events in last 100 blocks
ROLE_EVENTS=$(cast logs \
  --address $FACTORY_ADDRESS \
  --topic 0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d \
  --from-block latest-100 \
  --rpc-url $RPC_URL)

if [ -n "$ROLE_EVENTS" ]; then
  echo "⚠️ Role grants detected: $ROLE_EVENTS"
  # Send alert
  aws sns publish \
    --topic-arn arn:aws:sns:us-east-1:ACCOUNT:energrid-security-alerts \
    --message "Unauthorized role grant detected: $ROLE_EVENTS"
fi
```

### Incident Response

#### Automated Response
```python
# security-response.py
import boto3
import json

def lambda_handler(event, context):
    """Automated security incident response"""
    
    # Parse CloudWatch alarm
    message = json.loads(event['Records'][0]['Sns']['Message'])
    alarm_name = message['AlarmName']
    
    if 'suspicious-api' in alarm_name:
        # Block suspicious IPs using WAF
        waf = boto3.client('wafv2')
        
        # Add IP to block list
        waf.update_ip_set(
            Scope='CLOUDFRONT',
            Id='energrid-blocked-ips',
            Addresses=['192.168.1.100/32']  # Extract from logs
        )
        
    elif 'auth-failures' in alarm_name:
        # Temporarily disable API access
        elb = boto3.client('elbv2')
        
        # Redirect to maintenance page
        elb.modify_listener(
            ListenerArn='arn:aws:elasticloadbalancing:...',
            DefaultActions=[{
                'Type': 'fixed-response',
                'FixedResponseConfig': {
                    'StatusCode': '503',
                    'ContentType': 'text/html',
                    'MessageBody': 'Service temporarily unavailable'
                }
            }]
        )
```

## Vulnerability Management

### Smart Contract Auditing

#### Pre-Deployment Audit Checklist
- [ ] **Static Analysis**: Slither, Mythril, Securify
- [ ] **Dynamic Analysis**: Echidna fuzzing, MythX
- [ ] **Manual Review**: Third-party security audit
- [ ] **Test Coverage**: Minimum 90% line coverage
- [ ] **Gas Optimization**: Gas usage analysis
- [ ] **Documentation**: Complete security documentation

#### Automated Security Scanning
```yaml
# .github/workflows/security-scan.yml
name: Security Scan

on: [push, pull_request]

jobs:
  slither:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: crytic/slither-action@v0.3.0
        with:
          target: 'src/'
          slither-args: '--exclude-dependencies'
        
  mythril:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: |
          pip install mythril
          myth analyze src/Energrid.sol --execution-timeout 300
```

### Dependency Management

#### Supply Chain Security
```json
{
  "scripts": {
    "audit": "npm audit --audit-level moderate",
    "audit-fix": "npm audit fix",
    "check-updates": "npm outdated"
  },
  "overrides": {
    "@openzeppelin/contracts": "4.9.3"
  }
}
```

#### Automated Dependency Updates
```yaml
# dependabot.yml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    reviewers:
      - "security-team"
```

## Compliance and Governance

### Regulatory Compliance

#### GDPR Compliance
- **Data Minimization**: Only collect necessary blockchain data
- **Right to Erasure**: Implement off-chain data deletion
- **Data Portability**: Export user transaction history
- **Privacy by Design**: Default privacy settings

#### SOC 2 Type II
- **Security**: Multi-factor authentication required
- **Availability**: 99.9% uptime SLA with monitoring
- **Processing Integrity**: Transaction validation and logging
- **Confidentiality**: Encryption and access controls
- **Privacy**: Data handling procedures documented

### Security Governance

#### Security Review Board
- **Composition**: CTO, Security Lead, Blockchain Architect
- **Frequency**: Monthly security reviews
- **Responsibilities**: Risk assessment, policy updates, incident review

#### Change Management
```bash
# security-review.sh
#!/bin/bash

echo "🔒 Security Review Checklist for Change: $1"
echo "1. Security impact assessment completed? (y/n)"
read SECURITY_IMPACT

echo "2. Code review by security team completed? (y/n)"
read CODE_REVIEW

echo "3. Automated security tests passing? (y/n)"
read AUTO_TESTS

echo "4. Manual security testing completed? (y/n)"
read MANUAL_TESTS

if [[ "$SECURITY_IMPACT" == "y" && "$CODE_REVIEW" == "y" && "$AUTO_TESTS" == "y" && "$MANUAL_TESTS" == "y" ]]; then
    echo "✅ Security review approved for deployment"
    exit 0
else
    echo "❌ Security review failed - address issues before deployment"
    exit 1
fi
```

## Emergency Procedures

### Security Incident Response Plan

#### Phase 1: Detection and Analysis (0-15 minutes)
1. **Automated Detection**: CloudWatch alarms trigger
2. **Manual Detection**: Security team notification
3. **Initial Assessment**: Determine incident severity
4. **Team Assembly**: Activate incident response team

#### Phase 2: Containment (15-60 minutes)
1. **Immediate Containment**: Pause affected contracts
2. **Network Isolation**: Block suspicious traffic
3. **Access Revocation**: Disable compromised accounts
4. **Evidence Preservation**: Capture logs and state

#### Phase 3: Eradication and Recovery (1-24 hours)
1. **Root Cause Analysis**: Identify vulnerability source
2. **Patch Development**: Create and test fixes
3. **System Recovery**: Restore services securely
4. **Monitoring Enhancement**: Implement additional controls

#### Phase 4: Post-Incident (24+ hours)
1. **Incident Documentation**: Complete incident report
2. **Lessons Learned**: Update procedures and controls
3. **Stakeholder Communication**: Notify affected parties
4. **Legal/Regulatory**: Comply with disclosure requirements

### Emergency Contacts

**Incident Response Team**:
- **Incident Commander**: +1-XXX-XXX-XXXX
- **Security Lead**: +1-XXX-XXX-XXXX
- **Blockchain Developer**: +1-XXX-XXX-XXXX
- **DevOps Engineer**: +1-XXX-XXX-XXXX

**External Contacts**:
- **Security Audit Firm**: security@auditor.com
- **Legal Counsel**: legal@lawfirm.com
- **AWS Support**: Enterprise support case
- **Insurance Provider**: cyber@insurance.com

## Security Testing

### Penetration Testing Schedule
- **Quarterly**: External penetration testing
- **Monthly**: Internal vulnerability assessment
- **Weekly**: Automated security scanning
- **Daily**: Configuration compliance checking

### Bug Bounty Program
- **Scope**: Smart contracts and infrastructure
- **Rewards**: $100 - $50,000 based on severity
- **Platform**: HackerOne or Immunefi
- **Disclosure**: Responsible disclosure policy

## Security Metrics and KPIs

### Key Performance Indicators
- **Mean Time to Detection (MTTD)**: < 15 minutes
- **Mean Time to Response (MTTR)**: < 1 hour
- **Security Test Coverage**: > 95%
- **Vulnerability Remediation**: Critical < 24h, High < 72h
- **Security Training Completion**: 100% annual

### Continuous Monitoring
```bash
# Generate security dashboard
aws cloudwatch put-dashboard \
  --dashboard-name "Energrid-Security" \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "properties": {
          "metrics": [
            ["Energrid/Security", "SecurityIncidents"],
            ["Energrid/Security", "VulnerabilitiesDetected"],
            ["Energrid/Security", "PatchComplianceRate"]
          ],
          "period": 3600,
          "stat": "Sum",
          "region": "us-east-1",
          "title": "Security Metrics"
        }
      }
    ]
  }'
```
