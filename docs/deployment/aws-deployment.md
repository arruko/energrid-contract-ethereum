# AWS Deployment Guide for Energrid Smart Contracts

## Overview

This guide provides comprehensive instructions for deploying Energrid smart contracts to production on AWS infrastructure with high availability, security, and monitoring.

## Prerequisites

### AWS Services Required
- **ECS Fargate**: Container orchestration
- **Application Load Balancer**: Traffic distribution
- **RDS**: Database for indexing and caching
- **ElastiCache**: Redis for session management
- **Secrets Manager**: Private key management
- **CloudWatch**: Monitoring and logging
- **Systems Manager**: Parameter store
- **VPC**: Network isolation
- **IAM**: Identity and access management

### External Dependencies
- **Ethereum Node Provider**: Infura/Alchemy/QuickNode
- **Domain**: Route53 or external DNS
- **SSL Certificate**: AWS Certificate Manager

## Infrastructure Setup

### 1. VPC Configuration

```yaml
# terraform/vpc.tf
resource "aws_vpc" "energrid" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name        = "energrid-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.energrid.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = {
    Name = "energrid-private-${count.index + 1}"
    Type = "private"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.energrid.id
  cidr_block              = "10.0.${count.index + 10}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "energrid-public-${count.index + 1}"
    Type = "public"
  }
}
```

### 2. Security Groups

```yaml
# terraform/security.tf
resource "aws_security_group" "alb" {
  name_prefix = "energrid-alb-"
  vpc_id      = aws_vpc.energrid.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name_prefix = "energrid-ecs-"
  vpc_id      = aws_vpc.energrid.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 3. Secrets Management

```bash
#!/bin/bash
# scripts/setup-secrets.sh

# Store private keys in AWS Secrets Manager
aws secretsmanager create-secret \
    --name "energrid/deployer-private-key" \
    --description "Private key for contract deployment" \
    --secret-string "$DEPLOYER_PRIVATE_KEY"

aws secretsmanager create-secret \
    --name "energrid/admin-private-key" \
    --description "Private key for admin operations" \
    --secret-string "$ADMIN_PRIVATE_KEY"

# Store Ethereum RPC URLs
aws ssm put-parameter \
    --name "/energrid/ethereum/mainnet-rpc" \
    --value "$MAINNET_RPC_URL" \
    --type "SecureString"

aws ssm put-parameter \
    --name "/energrid/ethereum/sepolia-rpc" \
    --value "$SEPOLIA_RPC_URL" \
    --type "SecureString"
```

## Application Deployment

### 1. ECS Task Definition

```json
{
  "family": "energrid-api",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/energrid-task-role",
  "containerDefinitions": [
    {
      "name": "energrid-api",
      "image": "energrid/api:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "NETWORK",
          "value": "mainnet"
        }
      ],
      "secrets": [
        {
          "name": "DEPLOYER_PRIVATE_KEY",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:energrid/deployer-private-key"
        },
        {
          "name": "ETHEREUM_RPC_URL",
          "valueFrom": "arn:aws:ssm:REGION:ACCOUNT:parameter/energrid/ethereum/mainnet-rpc"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/energrid-api",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

### 2. ECS Service Configuration

```yaml
# terraform/ecs.tf
resource "aws_ecs_cluster" "energrid" {
  name = "energrid-cluster"
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_service" "api" {
  name            = "energrid-api"
  cluster         = aws_ecs_cluster.energrid.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "energrid-api"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.api]
}
```

## Smart Contract Deployment

### 1. Deployment Scripts

```typescript
// scripts/deploy-production.ts
import { ethers } from "hardhat";
import AWS from "aws-sdk";

const secretsManager = new AWS.SecretsManager({ region: 'us-east-1' });

async function getSecret(secretName: string): Promise<string> {
  const result = await secretsManager.getSecretValue({ SecretId: secretName }).promise();
  return result.SecretString!;
}

async function main() {
  // Get deployer private key from AWS Secrets Manager
  const deployerKey = await getSecret("energrid/deployer-private-key");
  const wallet = new ethers.Wallet(deployerKey, ethers.provider);

  console.log("Deploying contracts with account:", wallet.address);
  console.log("Account balance:", ethers.utils.formatEther(await wallet.getBalance()));

  // Deploy kWhToken
  const KWhToken = await ethers.getContractFactory("kWhToken", wallet);
  const kwhToken = await KWhToken.deploy();
  await kwhToken.deployed();
  console.log("kWhToken deployed to:", kwhToken.address);

  // Deploy CELToken
  const CELToken = await ethers.getContractFactory("CELToken", wallet);
  const celToken = await CELToken.deploy();
  await celToken.deployed();
  console.log("CELToken deployed to:", celToken.address);

  // Deploy Energy1155
  const Energy1155 = await ethers.getContractFactory("Energy1155", wallet);
  const energy1155 = await Energy1155.deploy("https://api.energrid.com/metadata/{id}");
  await energy1155.deployed();
  console.log("Energy1155 deployed to:", energy1155.address);

  // Deploy ContractFactory
  const ContractFactory = await ethers.getContractFactory("ContractFactory", wallet);
  const factory = await ContractFactory.deploy(
    kwhToken.address,
    celToken.address,
    kwhToken.address // Using kWh as payment token
  );
  await factory.deployed();
  console.log("ContractFactory deployed to:", factory.address);

  // Store contract addresses in AWS Systems Manager
  const ssm = new AWS.SSM({ region: 'us-east-1' });
  
  await ssm.putParameter({
    Name: "/energrid/contracts/kwh-token",
    Value: kwhToken.address,
    Type: "String",
    Overwrite: true
  }).promise();

  await ssm.putParameter({
    Name: "/energrid/contracts/cel-token",
    Value: celToken.address,
    Type: "String",
    Overwrite: true
  }).promise();

  await ssm.putParameter({
    Name: "/energrid/contracts/energy-1155",
    Value: energy1155.address,
    Type: "String",
    Overwrite: true
  }).promise();

  await ssm.putParameter({
    Name: "/energrid/contracts/factory",
    Value: factory.address,
    Type: "String",
    Overwrite: true
  }).promise();

  console.log("Contract addresses stored in AWS Systems Manager");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

### 2. Deployment Pipeline

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: npm ci
      - run: npm run test
      - run: npm run coverage

  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Install dependencies
        run: npm ci

      - name: Compile contracts
        run: npm run compile

      - name: Deploy contracts
        run: npm run deploy:production
        env:
          NETWORK: mainnet

      - name: Verify contracts on Etherscan
        run: npm run verify:production
        env:
          ETHERSCAN_API_KEY: ${{ secrets.ETHERSCAN_API_KEY }}

      - name: Update ECS service
        run: |
          aws ecs update-service \
            --cluster energrid-cluster \
            --service energrid-api \
            --force-new-deployment
```

## Monitoring and Alerting

### 1. CloudWatch Dashboards

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ECS", "CPUUtilization", "ServiceName", "energrid-api"],
          ["AWS/ECS", "MemoryUtilization", "ServiceName", "energrid-api"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "ECS Resource Utilization"
      }
    },
    {
      "type": "metric", 
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "energrid-alb"],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "energrid-alb"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "Load Balancer Metrics"
      }
    }
  ]
}
```

### 2. CloudWatch Alarms

```yaml
# terraform/monitoring.tf
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "energrid-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ServiceName = aws_ecs_service.api.name
    ClusterName = aws_ecs_cluster.energrid.name
  }
}

resource "aws_cloudwatch_metric_alarm" "contract_deployment_failure" {
  alarm_name          = "energrid-deployment-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DeploymentFailures"
  namespace           = "Energrid/Contracts"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Contract deployment failure detected"
  alarm_actions       = [aws_sns_topic.critical_alerts.arn]
}
```

## Production Checklist

### Pre-Deployment
- [ ] Smart contracts audited by third party
- [ ] All tests passing (134/134)
- [ ] Coverage above 85% (current: 88.19%)
- [ ] Gas optimization completed
- [ ] Mainnet private keys secured in AWS Secrets Manager
- [ ] Infrastructure provisioned and tested
- [ ] Monitoring and alerting configured
- [ ] Backup and recovery procedures tested

### Deployment
- [ ] Deploy to Sepolia testnet first
- [ ] Verify contract functionality on testnet
- [ ] Deploy to mainnet with multi-sig approval
- [ ] Verify contracts on Etherscan
- [ ] Update API service with new contract addresses
- [ ] Smoke test all critical functions

### Post-Deployment
- [ ] Monitor gas costs and transaction success rates
- [ ] Verify role assignments and permissions
- [ ] Test emergency pause procedures
- [ ] Document all contract addresses
- [ ] Update monitoring dashboards
- [ ] Conduct security review

## Cost Optimization

### Estimated Monthly Costs (Production)
- **ECS Fargate (2 tasks)**: ~$150/month
- **Application Load Balancer**: ~$25/month
- **CloudWatch Logs**: ~$20/month
- **Secrets Manager**: ~$5/month
- **NAT Gateway**: ~$45/month
- **Total Infrastructure**: ~$245/month

### Gas Cost Management
- Deploy during low network congestion
- Use gas price oracles for optimal timing
- Implement batch operations where possible
- Monitor and alert on high gas usage

## Security Considerations

### Network Security
- Private subnets for all application instances
- Security groups with least privilege access
- VPC Flow Logs enabled
- WAF protection for public endpoints

### Application Security
- Private keys never stored in code
- All secrets managed through AWS services
- Regular security patches and updates
- Container image scanning enabled

### Smart Contract Security
- Multi-signature wallets for admin operations
- Role-based access control implemented
- Emergency pause functionality
- Regular security audits scheduled
