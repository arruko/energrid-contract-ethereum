# Energrid Operations Runbook

## Overview

This runbook provides step-by-step procedures for common operational tasks in the Energrid production environment. All procedures assume you have appropriate AWS and smart contract admin permissions.

## Emergency Procedures

### 🚨 Critical Security Incident

**When to Use**: Suspected smart contract exploit, unauthorized access, or security breach

**Immediate Actions (< 5 minutes)**:
```bash
# 1. Pause all contracts immediately
aws ecs run-task \
  --cluster energrid-cluster \
  --task-definition energrid-emergency-pause \
  --launch-type FARGATE

# 2. Alert security team
aws sns publish \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:energrid-security-alerts \
  --message "CRITICAL: Security incident detected - All contracts paused"

# 3. Disable API access
aws elbv2 modify-listener \
  --listener-arn arn:aws:elasticloadbalancing:us-east-1:ACCOUNT:listener/app/energrid-alb \
  --default-actions Type=fixed-response,FixedResponseConfig='{StatusCode=503,ContentType=text/plain,MessageBody=Service Temporarily Unavailable}'
```

**Investigation Actions (< 30 minutes)**:
```bash
# 1. Gather transaction logs
aws logs filter-log-events \
  --log-group-name /ecs/energrid-api \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "ERROR"

# 2. Check contract events
cast logs \
  --address $(aws ssm get-parameter --name /energrid/contracts/factory --query Parameter.Value --output text) \
  --from-block latest-100 \
  --rpc-url $(aws ssm get-parameter --name /energrid/ethereum/mainnet-rpc --with-decryption --query Parameter.Value --output text)

# 3. Analyze suspicious transactions
# Use Etherscan API or internal monitoring tools
```

### 🔥 Service Outage

**When to Use**: API unavailable, ECS tasks failing, or database connectivity issues

**Diagnosis Steps**:
```bash
# 1. Check ECS service health
aws ecs describe-services \
  --cluster energrid-cluster \
  --services energrid-api

# 2. Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names energrid-api-tg --query 'TargetGroups[0].TargetGroupArn' --output text)

# 3. Check CloudWatch alarms
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --alarm-names energrid-high-cpu energrid-high-memory energrid-api-errors
```

**Recovery Actions**:
```bash
# 1. Force new deployment
aws ecs update-service \
  --cluster energrid-cluster \
  --service energrid-api \
  --force-new-deployment

# 2. Scale up if needed
aws ecs update-service \
  --cluster energrid-cluster \
  --service energrid-api \
  --desired-count 4

# 3. Clear ELB DNS cache
aws route53 change-resource-record-sets \
  --hosted-zone-id ZONE_ID \
  --change-batch file://dns-flush.json
```

## Routine Maintenance

### Daily Operations

**Morning Checklist** (9:00 AM UTC):
```bash
# 1. Check service health
./scripts/health-check.sh

# 2. Review overnight logs
aws logs filter-log-events \
  --log-group-name /ecs/energrid-api \
  --start-time $(date -d 'yesterday' +%s)000 \
  --filter-pattern "ERROR|WARN"

# 3. Verify contract states
cast call $(aws ssm get-parameter --name /energrid/contracts/factory --query Parameter.Value --output text) \
  "paused()(bool)" \
  --rpc-url $(aws ssm get-parameter --name /energrid/ethereum/mainnet-rpc --with-decryption --query Parameter.Value --output text)

# 4. Check gas price trends
curl -s "https://api.etherscan.io/api?module=gastracker&action=gasoracle&apikey=YourApiKeyToken"
```

**Evening Checklist** (6:00 PM UTC):
```bash
# 1. Backup configuration
aws s3 sync /tmp/energrid-config s3://energrid-backups/config/$(date +%Y%m%d)/

# 2. Update monitoring dashboards
aws cloudwatch put-dashboard \
  --dashboard-name "Energrid-Daily" \
  --dashboard-body file://dashboard-config.json

# 3. Review resource utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=energrid-api \
  --start-time $(date -d '24 hours ago' --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 3600 \
  --statistics Average
```

### Weekly Operations

**Every Monday** (10:00 AM UTC):
```bash
# 1. Security scan
docker run --rm -v $(pwd):/src securecodewarrior/docker-security-scanner

# 2. Update dependencies
npm audit
npm update

# 3. Review access logs
aws s3 cp s3://energrid-access-logs/$(date -d 'last week' +%Y-%m-%d)/ /tmp/logs/ --recursive
./scripts/analyze-access-patterns.sh /tmp/logs/

# 4. Certificate renewal check
aws acm list-certificates \
  --certificate-statuses ISSUED \
  --query 'CertificateSummaryList[?NotAfter<=`2024-08-19T00:00:00Z`]'
```

**Every Friday** (5:00 PM UTC):
```bash
# 1. Create weekly backup
./scripts/backup-weekly.sh

# 2. Performance review
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=energrid-alb \
  --start-time $(date -d '7 days ago' --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 86400 \
  --statistics Average,Maximum

# 3. Cost analysis
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost
```

## Smart Contract Management

### Contract Pause/Unpause

**Pause Contracts** (Emergency):
```bash
# Set environment variables
export ADMIN_PRIVATE_KEY=$(aws secretsmanager get-secret-value --secret-id energrid/admin-private-key --query SecretString --output text)
export RPC_URL=$(aws ssm get-parameter --name /energrid/ethereum/mainnet-rpc --with-decryption --query Parameter.Value --output text)

# Pause kWhToken
cast send $(aws ssm get-parameter --name /energrid/contracts/kwh-token --query Parameter.Value --output text) \
  "pause()" \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $RPC_URL

# Pause CELToken
cast send $(aws ssm get-parameter --name /energrid/contracts/cel-token --query Parameter.Value --output text) \
  "pause()" \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $RPC_URL

# Pause Energy1155
cast send $(aws ssm get-parameter --name /energrid/contracts/energy-1155 --query Parameter.Value --output text) \
  "pause()" \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

**Unpause Contracts** (After issue resolution):
```bash
# Verify issue is resolved and get approval
echo "⚠️ Unpausing contracts requires approval. Enter 'APPROVED' to continue:"
read APPROVAL
[ "$APPROVAL" != "APPROVED" ] && exit 1

# Unpause kWhToken
cast send $(aws ssm get-parameter --name /energrid/contracts/kwh-token --query Parameter.Value --output text) \
  "unpause()" \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $RPC_URL

# Unpause CELToken
cast send $(aws ssm get-parameter --name /energrid/contracts/cel-token --query Parameter.Value --output text) \
  "unpause()" \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $RPC_URL

# Unpause Energy1155
cast send $(aws ssm get-parameter --name /energrid/contracts/energy-1155 --query Parameter.Value --output text) \
  "unpause()" \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

### Role Management

**Grant Role**:
```bash
# Example: Grant MINTER_ROLE to new address
CONTRACT_ADDRESS=$(aws ssm get-parameter --name /energrid/contracts/kwh-token --query Parameter.Value --output text)
NEW_MINTER="0x742d35Cc6634C0532925a3b8D186dF98a33e4234"
ROLE_HASH=$(cast call $CONTRACT_ADDRESS "MINTER_ROLE()(bytes32)" --rpc-url $RPC_URL)

cast send $CONTRACT_ADDRESS \
  "grantRole(bytes32,address)" \
  $ROLE_HASH \
  $NEW_MINTER \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

**Revoke Role**:
```bash
# Example: Revoke MINTER_ROLE from address
cast send $CONTRACT_ADDRESS \
  "revokeRole(bytes32,address)" \
  $ROLE_HASH \
  $NEW_MINTER \
  --private-key $ADMIN_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

### Contract Upgrade Process

**Preparation**:
```bash
# 1. Test upgrade on testnet
./scripts/deploy-contracts.sh sepolia staging

# 2. Verify upgrade compatibility
forge test --match-contract UpgradeTest

# 3. Create upgrade proposal
./scripts/create-upgrade-proposal.sh mainnet
```

**Execution** (Requires multi-sig approval):
```bash
# 1. Deploy new implementation
./scripts/deploy-upgrade.sh mainnet

# 2. Update proxy (if using proxy pattern)
# This would be specific to your upgrade mechanism

# 3. Verify upgrade
./scripts/verify-upgrade.sh mainnet
```

## Infrastructure Management

### Scaling Operations

**Scale Up** (High traffic):
```bash
# Increase ECS task count
aws ecs update-service \
  --cluster energrid-cluster \
  --service energrid-api \
  --desired-count 6

# Add RDS read replicas if needed
aws rds create-db-instance-read-replica \
  --db-instance-identifier energrid-read-replica-2 \
  --source-db-instance-identifier energrid-primary
```

**Scale Down** (Normal traffic):
```bash
# Decrease ECS task count
aws ecs update-service \
  --cluster energrid-cluster \
  --service energrid-api \
  --desired-count 2

# Remove unnecessary read replicas
aws rds delete-db-instance \
  --db-instance-identifier energrid-read-replica-2 \
  --skip-final-snapshot
```

### Database Maintenance

**Backup**:
```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier energrid-primary \
  --db-snapshot-identifier energrid-manual-$(date +%Y%m%d-%H%M%S)
```

**Restore**:
```bash
# Restore from snapshot (creates new instance)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier energrid-restored \
  --db-snapshot-identifier energrid-manual-20240719-120000
```

## Monitoring and Alerting

### Custom Metrics

**Gas Usage Monitoring**:
```bash
# Send custom metric to CloudWatch
aws cloudwatch put-metric-data \
  --namespace "Energrid/Contracts" \
  --metric-data MetricName=GasUsed,Value=150000,Unit=Count,Dimensions=Contract=Factory,Operation=Deploy
```

**Transaction Success Rate**:
```bash
# Query recent transactions and calculate success rate
SUCCESS_COUNT=$(cast logs --address $CONTRACT_ADDRESS --from-block latest-1000 | grep "Transfer" | wc -l)
TOTAL_TRANSACTIONS=1000
SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_TRANSACTIONS))

aws cloudwatch put-metric-data \
  --namespace "Energrid/Contracts" \
  --metric-data MetricName=TransactionSuccessRate,Value=$SUCCESS_RATE,Unit=Percent
```

### Log Analysis

**Search for Errors**:
```bash
# API errors
aws logs filter-log-events \
  --log-group-name /ecs/energrid-api \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern '{ $.level = "ERROR" }'

# Contract events
cast logs \
  --address $(aws ssm get-parameter --name /energrid/contracts/factory --query Parameter.Value --output text) \
  --topic 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef \
  --from-block latest-100
```

## Troubleshooting Guide

### Common Issues

**Issue: High gas costs**
```bash
# Check current gas price
cast gas-price --rpc-url $RPC_URL

# Implement gas price monitoring
./scripts/monitor-gas-prices.sh

# Solution: Implement dynamic gas pricing or queue transactions
```

**Issue: ECS tasks failing**
```bash
# Check task logs
aws ecs describe-tasks \
  --cluster energrid-cluster \
  --tasks $(aws ecs list-tasks --cluster energrid-cluster --service-name energrid-api --query 'taskArns[0]' --output text)

# Check resource utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=energrid-api \
  --start-time $(date -d '1 hour ago' --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 300 \
  --statistics Maximum
```

**Issue: Contract call failures**
```bash
# Check contract state
cast call $CONTRACT_ADDRESS "paused()(bool)" --rpc-url $RPC_URL

# Verify network connectivity
curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' $RPC_URL

# Check account balance
cast balance $(cast wallet address --private-key $ADMIN_PRIVATE_KEY) --rpc-url $RPC_URL
```

## Escalation Procedures

### Severity Levels

**P0 - Critical** (Service Down):
- Contact: On-call engineer immediately
- Response Time: 15 minutes
- Actions: Follow emergency procedures

**P1 - High** (Degraded Performance):
- Contact: Team lead within 1 hour
- Response Time: 1 hour
- Actions: Investigate and implement temporary fixes

**P2 - Medium** (Minor Issues):
- Contact: Assign to next sprint
- Response Time: 1 business day
- Actions: Standard troubleshooting

**P3 - Low** (Enhancement Requests):
- Contact: Product team
- Response Time: 1 week
- Actions: Evaluate and prioritize

### Contact Information

**Emergency Contacts**:
- On-call Engineer: +1-XXX-XXX-XXXX
- Security Team: security@energrid.com
- AWS Support: Enterprise support case

**Escalation Matrix**:
1. DevOps Engineer → Senior DevOps Engineer → DevOps Manager
2. Security Issue → Security Team → CISO
3. Contract Issue → Smart Contract Developer → Blockchain Architect
