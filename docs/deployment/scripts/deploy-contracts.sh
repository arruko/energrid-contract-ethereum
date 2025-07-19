#!/bin/bash

# Smart Contract Deployment Script
# Deploys Energrid contracts to specified network with proper verification

set -e

NETWORK=${1:-sepolia}
ENVIRONMENT=${2:-staging}

echo "🔗 Deploying smart contracts to $NETWORK network ($ENVIRONMENT environment)"

# Validate network
case $NETWORK in
  mainnet|sepolia|goerli|polygon|arbitrum)
    echo "✅ Valid network: $NETWORK"
    ;;
  *)
    echo "❌ Invalid network: $NETWORK"
    echo "   Supported networks: mainnet, sepolia, goerli, polygon, arbitrum"
    exit 1
    ;;
esac

# Check if we have the required private keys in AWS Secrets Manager
echo "🔐 Retrieving deployment credentials..."
DEPLOYER_KEY=$(aws secretsmanager get-secret-value --secret-id "energrid/deployer-private-key" --query SecretString --output text 2>/dev/null || echo "")
ADMIN_KEY=$(aws secretsmanager get-secret-value --secret-id "energrid/admin-private-key" --query SecretString --output text 2>/dev/null || echo "")

if [ -z "$DEPLOYER_KEY" ] || [ -z "$ADMIN_KEY" ]; then
  echo "❌ Required private keys not found in AWS Secrets Manager"
  echo "   Please store keys using: aws secretsmanager create-secret --name 'energrid/deployer-private-key' --secret-string 'YOUR_KEY'"
  exit 1
fi

# Get RPC URL from AWS Systems Manager
RPC_URL=$(aws ssm get-parameter --name "/energrid/ethereum/${NETWORK}-rpc" --with-decryption --query Parameter.Value --output text 2>/dev/null || echo "")
if [ -z "$RPC_URL" ]; then
  echo "❌ RPC URL not found for network $NETWORK"
  echo "   Please store RPC URL using: aws ssm put-parameter --name '/energrid/ethereum/${NETWORK}-rpc' --value 'YOUR_RPC_URL' --type SecureString"
  exit 1
fi

# Set environment variables for Hardhat
export PRIVATE_KEY=$DEPLOYER_KEY
export ADMIN_PRIVATE_KEY=$ADMIN_KEY
export RPC_URL=$RPC_URL
export NETWORK=$NETWORK

# Compile contracts
echo "⚙️ Compiling contracts..."
npx hardhat compile

# Run tests before deployment (for non-mainnet)
if [ "$NETWORK" != "mainnet" ]; then
  echo "🧪 Running tests..."
  npx hardhat test
fi

# Deploy contracts
echo "🚀 Deploying contracts to $NETWORK..."
npx hardhat run scripts/deploy.ts --network $NETWORK

# Verify contracts on Etherscan (if API key available)
ETHERSCAN_API_KEY=$(aws ssm get-parameter --name "/energrid/etherscan-api-key" --with-decryption --query Parameter.Value --output text 2>/dev/null || echo "")
if [ -n "$ETHERSCAN_API_KEY" ]; then
  echo "🔍 Verifying contracts on Etherscan..."
  export ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY
  
  # Get deployed addresses from previous deployment
  KWH_TOKEN=$(aws ssm get-parameter --name "/energrid/contracts/kwh-token" --query Parameter.Value --output text 2>/dev/null || echo "")
  CEL_TOKEN=$(aws ssm get-parameter --name "/energrid/contracts/cel-token" --query Parameter.Value --output text 2>/dev/null || echo "")
  ENERGY_1155=$(aws ssm get-parameter --name "/energrid/contracts/energy-1155" --query Parameter.Value --output text 2>/dev/null || echo "")
  FACTORY=$(aws ssm get-parameter --name "/energrid/contracts/factory" --query Parameter.Value --output text 2>/dev/null || echo "")
  
  if [ -n "$KWH_TOKEN" ]; then
    npx hardhat verify --network $NETWORK $KWH_TOKEN || echo "⚠️ kWhToken verification failed"
  fi
  
  if [ -n "$CEL_TOKEN" ]; then
    npx hardhat verify --network $NETWORK $CEL_TOKEN || echo "⚠️ CELToken verification failed"
  fi
  
  if [ -n "$ENERGY_1155" ]; then
    npx hardhat verify --network $NETWORK $ENERGY_1155 "https://api.energrid.com/metadata/{id}" || echo "⚠️ Energy1155 verification failed"
  fi
  
  if [ -n "$FACTORY" ]; then
    npx hardhat verify --network $NETWORK $FACTORY $KWH_TOKEN $CEL_TOKEN $KWH_TOKEN || echo "⚠️ Factory verification failed"
  fi
else
  echo "⚠️ Etherscan API key not found, skipping verification"
fi

# Store deployment information
echo "📋 Storing deployment information..."
DEPLOYMENT_INFO=$(cat <<EOF
{
  "network": "$NETWORK",
  "environment": "$ENVIRONMENT",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployer": "$(cast wallet address --private-key $DEPLOYER_KEY)",
  "contracts": {
    "kwhToken": "$(aws ssm get-parameter --name '/energrid/contracts/kwh-token' --query Parameter.Value --output text 2>/dev/null || echo 'TBD')",
    "celToken": "$(aws ssm get-parameter --name '/energrid/contracts/cel-token' --query Parameter.Value --output text 2>/dev/null || echo 'TBD')",
    "energy1155": "$(aws ssm get-parameter --name '/energrid/contracts/energy-1155' --query Parameter.Value --output text 2>/dev/null || echo 'TBD')",
    "factory": "$(aws ssm get-parameter --name '/energrid/contracts/factory' --query Parameter.Value --output text 2>/dev/null || echo 'TBD')"
  }
}
EOF
)

# Store in S3 for audit trail
aws s3 cp - s3://energrid-deployments-${ENVIRONMENT}/deployments/$(date +%Y%m%d-%H%M%S)-${NETWORK}.json <<< "$DEPLOYMENT_INFO"

# Post-deployment validation
echo "✅ Running post-deployment validation..."

# Check contract code
KWH_TOKEN=$(aws ssm get-parameter --name "/energrid/contracts/kwh-token" --query Parameter.Value --output text 2>/dev/null || echo "")
if [ -n "$KWH_TOKEN" ]; then
  CODE_SIZE=$(cast code $KWH_TOKEN --rpc-url $RPC_URL | wc -c)
  if [ $CODE_SIZE -gt 10 ]; then
    echo "✅ kWhToken deployed successfully"
  else
    echo "❌ kWhToken deployment failed - no code at address"
    exit 1
  fi
fi

# Test basic functionality (for non-mainnet)
if [ "$NETWORK" != "mainnet" ]; then
  echo "🧪 Testing basic functionality..."
  npx hardhat run scripts/test-deployment.ts --network $NETWORK
fi

echo "🎉 Contract deployment completed successfully!"
echo "📊 Deployment summary:"
echo "   Network: $NETWORK"
echo "   Environment: $ENVIRONMENT"
echo "   kWhToken: $(aws ssm get-parameter --name '/energrid/contracts/kwh-token' --query Parameter.Value --output text 2>/dev/null || echo 'TBD')"
echo "   CELToken: $(aws ssm get-parameter --name '/energrid/contracts/cel-token' --query Parameter.Value --output text 2>/dev/null || echo 'TBD')"
echo "   Energy1155: $(aws ssm get-parameter --name '/energrid/contracts/energy-1155' --query Parameter.Value --output text 2>/dev/null || echo 'TBD')"
echo "   Factory: $(aws ssm get-parameter --name '/energrid/contracts/factory' --query Parameter.Value --output text 2>/dev/null || echo 'TBD')"

if [ "$NETWORK" = "mainnet" ]; then
  echo "🔔 PRODUCTION DEPLOYMENT COMPLETE"
  echo "   Please verify all contracts manually before announcing"
  echo "   Update frontend configuration with new addresses"
  echo "   Monitor gas usage and transaction success rates"
fi
