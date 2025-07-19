#!/bin/bash

# AWS Deployment Script for Energrid Smart Contracts
# This script sets up the complete AWS infrastructure for production deployment

set -e

# Configuration
ENVIRONMENT=${1:-production}
AWS_REGION=${2:-us-east-1}
PROJECT_NAME="energrid"

echo "🚀 Starting AWS deployment for Energrid - Environment: $ENVIRONMENT"

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI not found. Please install it."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform not found. Please install it."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "❌ Docker not found. Please install it."; exit 1; }

# Verify AWS credentials
aws sts get-caller-identity >/dev/null 2>&1 || { echo "❌ AWS credentials not configured"; exit 1; }
echo "✅ Prerequisites check passed"

# Create S3 bucket for Terraform state
echo "📦 Setting up Terraform backend..."
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${ENVIRONMENT}"
aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION 2>/dev/null || echo "Bucket already exists"
aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled

# Initialize Terraform
echo "🔧 Initializing Terraform..."
cd terraform/
terraform init \
  -backend-config="bucket=$BUCKET_NAME" \
  -backend-config="key=energrid/terraform.tfstate" \
  -backend-config="region=$AWS_REGION"

# Plan and apply infrastructure
echo "🏗️ Planning infrastructure..."
terraform plan \
  -var="environment=$ENVIRONMENT" \
  -var="aws_region=$AWS_REGION" \
  -var="project_name=$PROJECT_NAME" \
  -out=tfplan

echo "🚧 Applying infrastructure..."
terraform apply tfplan

# Get outputs
VPC_ID=$(terraform output -raw vpc_id)
ALB_DNS=$(terraform output -raw alb_dns_name)
ECS_CLUSTER=$(terraform output -raw ecs_cluster_name)

echo "✅ Infrastructure deployed successfully"
echo "   VPC ID: $VPC_ID"
echo "   Load Balancer: $ALB_DNS"
echo "   ECS Cluster: $ECS_CLUSTER"

cd ..

# Build and push Docker images
echo "🐳 Building Docker images..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com

# Build API image
docker build -t energrid-api -f docker/Dockerfile.api .
docker tag energrid-api:latest $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com/energrid-api:latest
docker push $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com/energrid-api:latest

# Build contract deployer image
docker build -t energrid-deployer -f docker/Dockerfile.deployer .
docker tag energrid-deployer:latest $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com/energrid-deployer:latest
docker push $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com/energrid-deployer:latest

echo "✅ Docker images built and pushed"

# Deploy smart contracts
echo "📜 Deploying smart contracts..."
if [ "$ENVIRONMENT" = "production" ]; then
  echo "⚠️  Production deployment requires manual approval"
  echo "   Run: ./deploy-contracts.sh production"
else
  ./deploy-contracts.sh $ENVIRONMENT
fi

# Update ECS services
echo "🔄 Updating ECS services..."
aws ecs update-service \
  --cluster $ECS_CLUSTER \
  --service energrid-api \
  --force-new-deployment \
  --region $AWS_REGION

# Wait for service to be stable
echo "⏳ Waiting for service deployment..."
aws ecs wait services-stable \
  --cluster $ECS_CLUSTER \
  --services energrid-api \
  --region $AWS_REGION

echo "🎉 Deployment completed successfully!"
echo "📊 Access your application at: https://$ALB_DNS"
echo "📈 CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=Energrid"

# Run health check
echo "🔍 Running health check..."
sleep 30
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$ALB_DNS/health)
if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Health check passed"
else
  echo "❌ Health check failed (HTTP $HTTP_CODE)"
  exit 1
fi

echo "🎯 Deployment summary:"
echo "   Environment: $ENVIRONMENT"
echo "   Region: $AWS_REGION"
echo "   Application URL: https://$ALB_DNS"
echo "   ECS Cluster: $ECS_CLUSTER"
echo "   VPC: $VPC_ID"
