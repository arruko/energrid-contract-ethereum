# Energrid Hybrid Architecture Implementation Guide

## 🎯 Implemented Architecture

### Hybrid Solution Overview

We have implemented a **hybrid architecture** that combines the best of ECS Fargate and Lambda according to the specific requirements of each component:

```
┌─────────────────────────────────────────────────────────────────┐
│                     API Gateway (Unified Entry)                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────┐    ┌─────────────────────────────────┐  │
│  │   ECS FARGATE       │    │      LAMBDA FUNCTIONS           │  │
│  │   (High Performance)│    │      (Scalable & Cost-Effective)│  │
│  │                     │    │                                 │  │
│  │ • Trading Engine    │    │ • Authentication (Cognito)     │  │
│  │ • Blockchain Node   │    │ • Notifications (SNS/SES)      │  │
│  │ • IoT Processor     │    │ • Analytics & Reports          │  │
│  │                     │    │ • Certificate Generation       │  │
│  └─────────────────────┘    │ • CRUD APIs (DynamoDB)         │  │
│                             │ • Webhook Handlers              │  │
│                             └─────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│              Shared Infrastructure                              │
│  RDS MySQL | ElastiCache Redis | S3 | CloudWatch              │
└─────────────────────────────────────────────────────────────────┘
```

## 🏗️ Implemented Components

### 1. ECS Fargate Services (Total Control & High Performance)

#### Trading Engine Service
```
Resources: 2 vCPU, 4GB RAM
Port: 8080
Function: Core trading logic, EnergyTradeContract interactions
Performance: <100ms latency, >1000 TPS
```

#### Blockchain Node Service
```
Resources: 1 vCPU, 2GB RAM
Port: 8545
Function: Ethereum/Polygon node, smart contract deployment
Performance: 24/7 uptime, persistent connections
```

#### IoT Stream Processor
```
Resources: 1 vCPU, 2GB RAM
Port: 8090
Function: Real-time energy meter data processing
Performance: <50ms latency, continuous processing
```

### 2. Lambda Functions (Scalability & Cost-Effectiveness)

#### Authentication Service
```
Runtime: Python 3.11
Memory: 256MB
Timeout: 30s
Integration: AWS Cognito User Pool
Function: Login, logout, token management
```

#### Notification Service
```
Runtime: Python 3.11
Memory: 512MB
Timeout: 60s
Integration: SNS, SES
Function: Email/SMS alerts, trade notifications
```

#### Analytics Service
```
Runtime: Python 3.11
Memory: 1024MB
Timeout: 15min
Integration: S3, RDS
Function: Data processing, reports generation
```

#### Certificate Generation
```
Runtime: Python 3.11
Memory: 512MB
Timeout: 5min
Integration: S3, PDF generation
Function: CELToken certificate PDFs
```

#### CRUD API Service
```
Runtime: Python 3.11
Memory: 256MB
Timeout: 30s
Integration: DynamoDB
Function: User profiles, simple queries
```

#### Webhook Handler
```
Runtime: Python 3.11
Memory: 256MB
Timeout: 60s
Integration: SQS
Function: External payment callbacks, IoT webhooks
```

### 3. API Gateway Routes

```
/auth/*          → Lambda (Authentication)
/api/*           → Lambda (CRUD API)
/webhooks/*      → Lambda (Webhook Handler)
/trading/*       → ECS (Trading Engine)
/blockchain/*    → ECS (Blockchain Node)
/iot/*           → ECS (IoT Processor)
```

### 4. Shared Infrastructure

#### Database (RDS MySQL)
- **Primary**: MySQL 8.0, db.t3.micro
- **Read Replica**: For production
- **Backup**: 30 days (prod), 7 days (dev)
- **Monitoring**: Enhanced monitoring enabled

#### Cache (ElastiCache Redis)
- **Engine**: Redis 7.0
- **Multi-AZ**: Enabled in production
- **Auth Token**: Encryption in transit/rest
- **Backup**: Automatic snapshots

#### Storage
- **S3 Buckets**: Analytics, certificates, templates
- **DynamoDB**: CRUD operations data
- **CloudWatch Logs**: Centralized logging

#### Monitoring
- **CloudWatch Dashboard**: Hybrid metrics
- **SNS Alerts**: For all services
- **Custom Metrics**: Trading transactions, performance

## 🚀 Deployment Instructions

### Step 1: Configure Variables

```bash
# terraform/terraform.tfvars
project_name = "energrid"
environment  = "production"
vpc_cidr     = "10.0.0.0/16"

# Database configuration
database_password = "your-secure-password"
cache_auth_token  = "your-redis-token"

# ECR repository
ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/energrid"

# Monitoring
alarm_email = "devops@energrid.com"
```

### Step 2: Deploy Infrastructure

```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="terraform.tfvars"

# Deploy infrastructure
terraform apply -var-file="terraform.tfvars"
```

### Step 3: Build and Push Container Images

```bash
# Trading Engine
docker build -t energrid/trading-engine ./src/trading-engine
docker tag energrid/trading-engine:latest $ECR_URL/trading-engine:latest
docker push $ECR_URL/trading-engine:latest

# Blockchain Node
docker build -t energrid/blockchain-node ./src/blockchain-node
docker tag energrid/blockchain-node:latest $ECR_URL/blockchain-node:latest
docker push $ECR_URL/blockchain-node:latest

# IoT Processor
docker build -t energrid/iot-processor ./src/iot-processor
docker tag energrid/iot-processor:latest $ECR_URL/iot-processor:latest
docker push $ECR_URL/iot-processor:latest
```

### Step 4: Deploy Lambda Functions

```bash
# Build Lambda packages
cd src/lambda/
./build-packages.sh

# Functions will be deployed automatically with Terraform
```

## 📊 Monitoring and Metrics

### CloudWatch Dashboard
Access: `https://console.aws.amazon.com/cloudwatch/home#dashboards`

### Key Metrics:
- **ECS Services**: CPU, Memory, Task Health
- **Lambda Functions**: Duration, Errors, Invocations
- **API Gateway**: Latency, 4XX/5XX errors, Request count
- **Database**: CPU, Connections, Read/Write latency
- **Cache**: CPU, Memory usage, Hit ratio

### Configured Alerts:
- ECS CPU/Memory > 80%
- Lambda errors > 5 in 5 minutes
- API Gateway latency > 2 seconds
- Database connections > 80% capacity
- Trading transactions < 1 per 15 minutes

## 💰 Cost Estimation

### ECS Services (24/7)
```
Trading Engine: 2 vCPU, 4GB → ~$85/mes
Blockchain Node: 1 vCPU, 2GB → ~$43/mes
IoT Processor: 1 vCPU, 2GB → ~$43/mes
Total ECS: ~$171/mes
```

### Lambda Services (Pay-per-use)
```
Authentication: ~$5/mes (100K requests)
Notifications: ~$8/mes (50K requests)
Analytics: ~$10/mes (10K requests)
Other functions: ~$7/mes
Total Lambda: ~$30/mes
```

### Infrastructure
```
RDS (db.t3.micro): ~$25/mes
ElastiCache (cache.t3.micro): ~$15/mes
API Gateway: ~$3.50/mes (1M requests)
S3 Storage: ~$5/mes
CloudWatch: ~$5/mes
Total Infrastructure: ~$53.50/mes
```

**Total Estimated: ~$254.50/month**

## 🔒 Security Considerations

### Network Security
- VPC with private/public subnets
- Security groups with least privilege
- NACLs for additional protection
- NAT Gateways for outbound access

### Application Security
- WAF protection on ALB
- API Gateway throttling
- Lambda execution roles with minimal permissions
- Database encryption at rest/transit
- Redis auth tokens

### Monitoring Security
- CloudTrail for API logging
- VPC Flow Logs
- Security group analysis
- Automated security scanning

## 🔄 Operations

### Scaling
- **ECS**: Auto Scaling based on CPU/Memory
- **Lambda**: Automatic concurrent scaling
- **Database**: Read replicas for read scaling
- **API Gateway**: Built-in throttling protection

### Backup & Recovery
- **Database**: Automated backups with point-in-time recovery
- **Redis**: Automated snapshots
- **Application State**: Stored in RDS for persistence
- **Code**: Version controlled in ECR/Lambda

### Updates
- **ECS**: Blue/green deployments
- **Lambda**: Versioning and aliases
- **Database**: Schema migrations with zero downtime
- **Infrastructure**: Terraform state management

## 🎛️ Development Configuration

For development environment:
```bash
terraform workspace new development
terraform apply -var="environment=development" -var-file="dev.tfvars"
```

Differences in dev:
- Single AZ deployment
- Smaller instance sizes
- Reduced backup retention
- Less intensive monitoring

---

**The hybrid architecture is ready for deployment!** 

It combines the power and control of ECS for critical components with the scalability and cost-effectiveness of Lambda for auxiliary operations, providing the optimal solution for Energrid.
