#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EnergridStack } from '../lib/energrid-stack';
// import { EnergridMonitoringStack } from '../lib/energrid-monitoring-stack';

const app = new cdk.App();

// Get environment configuration
const environment = app.node.tryGetContext('environment') || 'development';
const region = app.node.tryGetContext('region') || 'us-east-1';
const account = app.node.tryGetContext('account');

if (!account) {
  throw new Error('Account ID must be provided via context: --context account=123456789012');
}

const env = {
  account,
  region,
};

// Common tags for all resources
const tags = {
  Project: 'Energrid',
  Environment: environment,
  ManagedBy: 'AWS CDK',
  Owner: 'DevOps Team',
};

// Main infrastructure stack
const energridStack = new EnergridStack(app, `Energrid-${environment}`, {
  env,
  environment,
  tags,
});

// Monitoring and alerting stack
// const monitoringStack = new EnergridMonitoringStack(app, `Energrid-Monitoring-${environment}`, {
//   env,
//   environment,
//   vpc: energridStack.vpc,
//   cluster: energridStack.cluster,
//   service: energridStack.service,
//   loadBalancer: energridStack.loadBalancer,
//   tags,
// });

// Add dependencies
// monitoringStack.addDependency(energridStack);

// Add stack-level tags
Object.entries(tags).forEach(([key, value]) => {
  cdk.Tags.of(energridStack).add(key, value);
//   cdk.Tags.of(monitoringStack).add(key, value);
});
