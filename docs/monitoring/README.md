# Monitoring & Observability Guide

## Overview

Comprehensive monitoring strategy for Energrid smart contracts and infrastructure, providing real-time visibility into system health, performance, and security.

## Monitoring Stack

### Core Components
- **CloudWatch**: AWS native monitoring and logging
- **Grafana**: Visualization and dashboards
- **Prometheus**: Metrics collection and alerting
- **ElasticSearch**: Log aggregation and search
- **Jaeger**: Distributed tracing
- **Custom Blockchain Monitors**: Smart contract specific monitoring

## Infrastructure Monitoring

### AWS CloudWatch Dashboards

#### Application Performance Dashboard
```json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0, "y": 0, "width": 12, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "energrid-alb"],
          [".", "TargetResponseTime", ".", "."],
          [".", "HTTPCode_Target_2XX_Count", ".", "."],
          [".", "HTTPCode_Target_4XX_Count", ".", "."],
          [".", "HTTPCode_Target_5XX_Count", ".", "."]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "us-east-1",
        "title": "Load Balancer Metrics",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 6, "width": 12, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/ECS", "CPUUtilization", "ServiceName", "energrid-api", "ClusterName", "energrid-cluster"],
          [".", "MemoryUtilization", ".", ".", ".", "."],
          [".", "RunningTaskCount", ".", ".", ".", "."]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "us-east-1",
        "title": "ECS Service Metrics",
        "period": 300,
        "stat": "Average"
      }
    }
  ]
}
```

#### Database Performance Dashboard
```json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0, "y": 0, "width": 12, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "energrid-primary"],
          [".", "DatabaseConnections", ".", "."],
          [".", "ReadLatency", ".", "."],
          [".", "WriteLatency", ".", "."],
          [".", "NetworkReceiveThroughput", ".", "."],
          [".", "NetworkTransmitThroughput", ".", "."]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "us-east-1",
        "title": "RDS Performance Metrics",
        "period": 300,
        "stat": "Average"
      }
    }
  ]
}
```

### Custom Application Metrics

#### API Metrics Collection
```javascript
// metrics.js - Custom metrics for Node.js application
const AWS = require('aws-sdk');
const cloudwatch = new AWS.CloudWatch({ region: 'us-east-1' });

class MetricsCollector {
  static async recordAPICall(endpoint, statusCode, responseTime) {
    const params = {
      Namespace: 'Energrid/API',
      MetricData: [
        {
          MetricName: 'RequestCount',
          Dimensions: [
            { Name: 'Endpoint', Value: endpoint },
            { Name: 'StatusCode', Value: statusCode.toString() }
          ],
          Value: 1,
          Unit: 'Count',
          Timestamp: new Date()
        },
        {
          MetricName: 'ResponseTime',
          Dimensions: [
            { Name: 'Endpoint', Value: endpoint }
          ],
          Value: responseTime,
          Unit: 'Milliseconds',
          Timestamp: new Date()
        }
      ]
    };
    
    await cloudwatch.putMetricData(params).promise();
  }

  static async recordContractInteraction(contractAddress, method, gasUsed, success) {
    const params = {
      Namespace: 'Energrid/Contracts',
      MetricData: [
        {
          MetricName: 'ContractCalls',
          Dimensions: [
            { Name: 'Contract', Value: contractAddress },
            { Name: 'Method', Value: method },
            { Name: 'Success', Value: success.toString() }
          ],
          Value: 1,
          Unit: 'Count',
          Timestamp: new Date()
        },
        {
          MetricName: 'GasUsed',
          Dimensions: [
            { Name: 'Contract', Value: contractAddress },
            { Name: 'Method', Value: method }
          ],
          Value: gasUsed,
          Unit: 'Count',
          Timestamp: new Date()
        }
      ]
    };
    
    await cloudwatch.putMetricData(params).promise();
  }
}

module.exports = MetricsCollector;
```

## Smart Contract Monitoring

### Blockchain Event Monitoring

#### Event Listener Service
```javascript
// blockchain-monitor.js
const { ethers } = require('ethers');
const MetricsCollector = require('./metrics');

class BlockchainMonitor {
  constructor(rpcUrl, contractAddresses) {
    this.provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    this.contracts = contractAddresses;
    this.setupEventListeners();
  }

  setupEventListeners() {
    // Monitor kWhToken events
    const kwhTokenABI = [
      "event Transfer(address indexed from, address indexed to, uint256 value)",
      "event Paused(address account)",
      "event Unpaused(address account)"
    ];
    
    const kwhToken = new ethers.Contract(
      this.contracts.kwhToken,
      kwhTokenABI,
      this.provider
    );

    // Track token transfers
    kwhToken.on('Transfer', async (from, to, value, event) => {
      await MetricsCollector.recordContractInteraction(
        this.contracts.kwhToken,
        'Transfer',
        event.gasUsed || 0,
        true
      );
      
      console.log(`Token Transfer: ${ethers.utils.formatEther(value)} kWh from ${from} to ${to}`);
    });

    // Track pause events
    kwhToken.on('Paused', async (account, event) => {
      await this.sendAlert('CRITICAL', 'kWhToken contract paused', {
        account,
        blockNumber: event.blockNumber,
        transactionHash: event.transactionHash
      });
    });

    // Monitor Factory contract deployments
    const factoryABI = [
      "event TradeContractDeployed(address indexed seller, address indexed buyer, address contractAddress, uint256 price, uint256 amount)"
    ];
    
    const factory = new ethers.Contract(
      this.contracts.factory,
      factoryABI,
      this.provider
    );

    factory.on('TradeContractDeployed', async (seller, buyer, contractAddress, price, amount, event) => {
      await MetricsCollector.recordContractInteraction(
        this.contracts.factory,
        'DeployTradeContract',
        event.gasUsed || 0,
        true
      );
      
      console.log(`New trade contract deployed: ${contractAddress} for ${ethers.utils.formatEther(amount)} kWh`);
    });
  }

  async sendAlert(severity, message, data) {
    const sns = new AWS.SNS({ region: 'us-east-1' });
    const topicArn = severity === 'CRITICAL' 
      ? 'arn:aws:sns:us-east-1:ACCOUNT:energrid-critical-alerts'
      : 'arn:aws:sns:us-east-1:ACCOUNT:energrid-alerts';

    await sns.publish({
      TopicArn: topicArn,
      Message: JSON.stringify({ message, data, timestamp: new Date().toISOString() }),
      Subject: `Energrid Alert: ${message}`
    }).promise();
  }

  async monitorGasPrices() {
    setInterval(async () => {
      try {
        const gasPrice = await this.provider.getGasPrice();
        const gasPriceGwei = ethers.utils.formatUnits(gasPrice, 'gwei');
        
        await MetricsCollector.recordCustomMetric('GasPrice', parseFloat(gasPriceGwei), 'None');
        
        // Alert if gas price is unusually high
        if (parseFloat(gasPriceGwei) > 100) {
          await this.sendAlert('HIGH', 'High gas prices detected', {
            gasPrice: gasPriceGwei,
            timestamp: new Date().toISOString()
          });
        }
      } catch (error) {
        console.error('Error monitoring gas prices:', error);
      }
    }, 60000); // Check every minute
  }

  async monitorBlockTimes() {
    let lastBlockNumber = await this.provider.getBlockNumber();
    let lastBlockTime = Date.now();

    setInterval(async () => {
      try {
        const currentBlockNumber = await this.provider.getBlockNumber();
        const currentTime = Date.now();
        
        if (currentBlockNumber > lastBlockNumber) {
          const blockTime = (currentTime - lastBlockTime) / (currentBlockNumber - lastBlockNumber);
          await MetricsCollector.recordCustomMetric('BlockTime', blockTime, 'Milliseconds');
          
          lastBlockNumber = currentBlockNumber;
          lastBlockTime = currentTime;
        }
      } catch (error) {
        console.error('Error monitoring block times:', error);
      }
    }, 30000); // Check every 30 seconds
  }
}

module.exports = BlockchainMonitor;
```

### Contract Health Checks

#### Automated Health Check Script
```bash
#!/bin/bash
# contract-health-check.sh

set -e

RPC_URL=$(aws ssm get-parameter --name /energrid/ethereum/mainnet-rpc --with-decryption --query Parameter.Value --output text)
KWH_TOKEN=$(aws ssm get-parameter --name /energrid/contracts/kwh-token --query Parameter.Value --output text)
CEL_TOKEN=$(aws ssm get-parameter --name /energrid/contracts/cel-token --query Parameter.Value --output text)
ENERGY_1155=$(aws ssm get-parameter --name /energrid/contracts/energy-1155 --query Parameter.Value --output text)
FACTORY=$(aws ssm get-parameter --name /energrid/contracts/factory --query Parameter.Value --output text)

echo "🔍 Starting contract health checks..."

# Check if contracts are paused
echo "Checking pause status..."
KWH_PAUSED=$(cast call $KWH_TOKEN "paused()(bool)" --rpc-url $RPC_URL)
CEL_PAUSED=$(cast call $CEL_TOKEN "paused()(bool)" --rpc-url $RPC_URL)
ENERGY_PAUSED=$(cast call $ENERGY_1155 "paused()(bool)" --rpc-url $RPC_URL)

if [ "$KWH_PAUSED" = "true" ]; then
  echo "⚠️ kWhToken is paused"
  aws cloudwatch put-metric-data \
    --namespace "Energrid/Contracts" \
    --metric-data MetricName=ContractPaused,Value=1,Unit=Count,Dimensions=Contract=kWhToken
fi

if [ "$CEL_PAUSED" = "true" ]; then
  echo "⚠️ CELToken is paused"
  aws cloudwatch put-metric-data \
    --namespace "Energrid/Contracts" \
    --metric-data MetricName=ContractPaused,Value=1,Unit=Count,Dimensions=Contract=CELToken
fi

if [ "$ENERGY_PAUSED" = "true" ]; then
  echo "⚠️ Energy1155 is paused"
  aws cloudwatch put-metric-data \
    --namespace "Energrid/Contracts" \
    --metric-data MetricName=ContractPaused,Value=1,Unit=Count,Dimensions=Contract=Energy1155
fi

# Check contract bytecode (detect if contracts have been modified)
echo "Verifying contract bytecode..."
KWH_CODE_SIZE=$(cast code $KWH_TOKEN --rpc-url $RPC_URL | wc -c)
CEL_CODE_SIZE=$(cast code $CEL_TOKEN --rpc-url $RPC_URL | wc -c)
FACTORY_CODE_SIZE=$(cast code $FACTORY --rpc-url $RPC_URL | wc -c)

if [ $KWH_CODE_SIZE -lt 1000 ]; then
  echo "❌ kWhToken bytecode size suspicious: $KWH_CODE_SIZE"
  aws sns publish \
    --topic-arn arn:aws:sns:us-east-1:ACCOUNT:energrid-critical-alerts \
    --message "kWhToken contract bytecode size is suspiciously small: $KWH_CODE_SIZE bytes"
fi

# Check token supply limits
echo "Checking supply limits..."
KWH_TOTAL_SUPPLY=$(cast call $KWH_TOKEN "totalSupply()(uint256)" --rpc-url $RPC_URL)
KWH_MAX_SUPPLY=$(cast call $KWH_TOKEN "MAX_SUPPLY()(uint256)" --rpc-url $RPC_URL)

KWH_SUPPLY_PERCENT=$((KWH_TOTAL_SUPPLY * 100 / KWH_MAX_SUPPLY))
echo "kWh Token supply: $KWH_SUPPLY_PERCENT% of maximum"

aws cloudwatch put-metric-data \
  --namespace "Energrid/Contracts" \
  --metric-data MetricName=SupplyUtilization,Value=$KWH_SUPPLY_PERCENT,Unit=Percent,Dimensions=Contract=kWhToken

if [ $KWH_SUPPLY_PERCENT -gt 90 ]; then
  echo "⚠️ kWh Token supply approaching maximum (${KWH_SUPPLY_PERCENT}%)"
  aws sns publish \
    --topic-arn arn:aws:sns:us-east-1:ACCOUNT:energrid-alerts \
    --message "kWh Token supply is at ${KWH_SUPPLY_PERCENT}% of maximum capacity"
fi

# Check recent transaction success rates
echo "Analyzing recent transaction success rates..."
CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL)
START_BLOCK=$((CURRENT_BLOCK - 1000))

# Count successful vs failed transactions to our contracts
SUCCESS_COUNT=0
TOTAL_COUNT=0

for ADDRESS in $KWH_TOKEN $CEL_TOKEN $FACTORY; do
  LOGS=$(cast logs --address $ADDRESS --from-block $START_BLOCK --to-block $CURRENT_BLOCK --rpc-url $RPC_URL 2>/dev/null || echo "")
  if [ -n "$LOGS" ]; then
    COUNT=$(echo "$LOGS" | wc -l)
    TOTAL_COUNT=$((TOTAL_COUNT + COUNT))
    SUCCESS_COUNT=$((SUCCESS_COUNT + COUNT))  # If we can retrieve logs, transaction was successful
  fi
done

if [ $TOTAL_COUNT -gt 0 ]; then
  SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))
  echo "Transaction success rate: ${SUCCESS_RATE}% ($SUCCESS_COUNT/$TOTAL_COUNT)"
  
  aws cloudwatch put-metric-data \
    --namespace "Energrid/Contracts" \
    --metric-data MetricName=TransactionSuccessRate,Value=$SUCCESS_RATE,Unit=Percent
fi

echo "✅ Contract health check completed"
```

## Alerting Configuration

### CloudWatch Alarms

#### Critical Alerts
```yaml
# terraform/alarms.tf
resource "aws_cloudwatch_metric_alarm" "contract_paused" {
  alarm_name          = "energrid-contract-paused"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ContractPaused"
  namespace           = "Energrid/Contracts"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Smart contract has been paused"
  alarm_actions       = [aws_sns_topic.critical_alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "high_gas_usage" {
  alarm_name          = "energrid-high-gas-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "GasUsed"
  namespace           = "Energrid/Contracts"
  period              = "300"
  statistic           = "Average"
  threshold           = "500000"
  alarm_description   = "High gas usage detected in contract interactions"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "transaction_failure_rate" {
  alarm_name          = "energrid-high-failure-rate"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "TransactionSuccessRate"
  namespace           = "Energrid/Contracts"
  period              = "900"
  statistic           = "Average"
  threshold           = "95"
  alarm_description   = "Transaction success rate below 95%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
```

#### Performance Alerts
```yaml
resource "aws_cloudwatch_metric_alarm" "api_response_time" {
  alarm_name          = "energrid-slow-api-response"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "2"
  alarm_description   = "API response time is too high"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.energrid.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "energrid-high-db-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Database CPU utilization is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.energrid.id
  }
}
```

### SNS Topics and Subscriptions

#### Alert Routing
```yaml
# Critical alerts (immediate response required)
resource "aws_sns_topic" "critical_alerts" {
  name = "energrid-critical-alerts"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = "*"
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "critical_pagerduty" {
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "https"
  endpoint  = "https://events.pagerduty.com/integration/..."
}

resource "aws_sns_topic_subscription" "critical_slack" {
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "https"
  endpoint  = "https://hooks.slack.com/services/..."
}

# Standard alerts (normal response time)
resource "aws_sns_topic" "alerts" {
  name = "energrid-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "devops@energrid.com"
}
```

## Log Management

### Centralized Logging

#### ECS Log Configuration
```json
{
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/energrid-api",
      "awslogs-region": "us-east-1",
      "awslogs-stream-prefix": "ecs",
      "awslogs-datetime-format": "%Y-%m-%d %H:%M:%S"
    }
  }
}
```

#### Log Aggregation with ElasticSearch
```yaml
# docker-compose.elasticsearch.yml
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.8.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
    ports:
      - "9200:9200"
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data

  logstash:
    image: docker.elastic.co/logstash/logstash:8.8.0
    volumes:
      - ./logstash.conf:/usr/share/logstash/pipeline/logstash.conf
    ports:
      - "5044:5044"
    depends_on:
      - elasticsearch

  kibana:
    image: docker.elastic.co/kibana/kibana:8.8.0
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on:
      - elasticsearch

volumes:
  elasticsearch_data:
```

#### Logstash Configuration
```ruby
# logstash.conf
input {
  beats {
    port => 5044
  }
  
  cloudwatch_logs {
    log_group => "/ecs/energrid-api"
    region => "us-east-1"
    start_position => "end"
  }
}

filter {
  if [source] == "/var/log/energrid/api.log" {
    json {
      source => "message"
    }
    
    mutate {
      add_field => { "log_type" => "api" }
    }
  }
  
  if [source] == "/var/log/energrid/blockchain.log" {
    json {
      source => "message"
    }
    
    mutate {
      add_field => { "log_type" => "blockchain" }
    }
  }
  
  # Parse transaction hashes and addresses
  if [log_type] == "blockchain" {
    grok {
      match => { "message" => "Transaction: %{DATA:transaction_hash}" }
    }
    
    grok {
      match => { "message" => "Contract: %{DATA:contract_address}" }
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "energrid-logs-%{+YYYY.MM.dd}"
  }
  
  stdout {
    codec => rubydebug
  }
}
```

### Log Analysis Queries

#### Kibana Dashboard Queries
```json
{
  "dashboard": {
    "title": "Energrid Operations Dashboard",
    "panels": [
      {
        "title": "Error Rate by Service",
        "query": {
          "query_string": {
            "query": "level:ERROR AND @timestamp:[now-1h TO now]"
          }
        },
        "aggregations": {
          "services": {
            "terms": {
              "field": "service.keyword",
              "size": 10
            }
          }
        }
      },
      {
        "title": "Transaction Volume",
        "query": {
          "query_string": {
            "query": "log_type:blockchain AND message:*Transaction*"
          }
        },
        "aggregations": {
          "hourly_volume": {
            "date_histogram": {
              "field": "@timestamp",
              "interval": "1h"
            }
          }
        }
      },
      {
        "title": "Contract Interactions",
        "query": {
          "query_string": {
            "query": "contract_address:* AND @timestamp:[now-24h TO now]"
          }
        },
        "aggregations": {
          "by_contract": {
            "terms": {
              "field": "contract_address.keyword",
              "size": 5
            }
          }
        }
      }
    ]
  }
}
```

## Performance Monitoring

### Application Performance Monitoring (APM)

#### New Relic Integration
```javascript
// newrelic.js
'use strict'

exports.config = {
  app_name: ['Energrid API'],
  license_key: process.env.NEW_RELIC_LICENSE_KEY,
  distributed_tracing: {
    enabled: true
  },
  logging: {
    level: 'info'
  },
  allow_all_headers: true,
  attributes: {
    exclude: [
      'request.headers.cookie',
      'request.headers.authorization',
      'request.headers.proxyAuthorization',
      'request.headers.setCookie*',
      'request.headers.x*',
      'response.headers.cookie',
      'response.headers.authorization',
      'response.headers.proxyAuthorization',
      'response.headers.setCookie*',
      'response.headers.x*'
    ]
  }
}
```

#### Custom Performance Tracking
```javascript
// performance-monitor.js
const newrelic = require('newrelic');

class PerformanceMonitor {
  static trackContractCall(contractName, methodName, duration, gasUsed) {
    // Record custom metrics
    newrelic.recordMetric(`Custom/Contract/${contractName}/${methodName}/Duration`, duration);
    newrelic.recordMetric(`Custom/Contract/${contractName}/${methodName}/GasUsed`, gasUsed);
    
    // Add custom attributes to current transaction
    newrelic.addCustomAttributes({
      'contract.name': contractName,
      'contract.method': methodName,
      'contract.gasUsed': gasUsed
    });
  }
  
  static trackAPIEndpoint(endpoint, responseTime, statusCode) {
    newrelic.recordMetric(`Custom/API/${endpoint}/ResponseTime`, responseTime);
    newrelic.recordMetric(`Custom/API/${endpoint}/Calls`, 1);
    
    if (statusCode >= 400) {
      newrelic.recordMetric(`Custom/API/${endpoint}/Errors`, 1);
    }
  }
}

module.exports = PerformanceMonitor;
```

## Synthetic Monitoring

### Health Check Endpoints

#### API Health Checks
```javascript
// health-check.js
const express = require('express');
const { ethers } = require('ethers');

const router = express.Router();

router.get('/health', async (req, res) => {
  const health = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    checks: {}
  };

  try {
    // Database health
    const dbStart = Date.now();
    await db.query('SELECT 1');
    health.checks.database = {
      status: 'healthy',
      responseTime: Date.now() - dbStart
    };
  } catch (error) {
    health.checks.database = {
      status: 'unhealthy',
      error: error.message
    };
    health.status = 'unhealthy';
  }

  try {
    // Blockchain connectivity
    const blockchainStart = Date.now();
    const blockNumber = await provider.getBlockNumber();
    health.checks.blockchain = {
      status: 'healthy',
      responseTime: Date.now() - blockchainStart,
      blockNumber: blockNumber
    };
  } catch (error) {
    health.checks.blockchain = {
      status: 'unhealthy',
      error: error.message
    };
    health.status = 'unhealthy';
  }

  try {
    // Contract accessibility
    const contractStart = Date.now();
    const kwhToken = new ethers.Contract(
      process.env.KWH_TOKEN_ADDRESS,
      ['function totalSupply() view returns (uint256)'],
      provider
    );
    const totalSupply = await kwhToken.totalSupply();
    health.checks.contracts = {
      status: 'healthy',
      responseTime: Date.now() - contractStart,
      kwhTotalSupply: totalSupply.toString()
    };
  } catch (error) {
    health.checks.contracts = {
      status: 'unhealthy',
      error: error.message
    };
    health.status = 'unhealthy';
  }

  const statusCode = health.status === 'healthy' ? 200 : 503;
  res.status(statusCode).json(health);
});

router.get('/ready', async (req, res) => {
  // Readiness check for Kubernetes/ECS
  try {
    await db.query('SELECT 1');
    await provider.getBlockNumber();
    res.status(200).json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});

module.exports = router;
```

#### External Health Monitoring
```bash
#!/bin/bash
# external-health-check.sh

API_ENDPOINT="https://api.energrid.com"
HEALTH_ENDPOINT="$API_ENDPOINT/health"

# Check API availability
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $HEALTH_ENDPOINT)
RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" $HEALTH_ENDPOINT)

# Send metrics to CloudWatch
aws cloudwatch put-metric-data \
  --namespace "Energrid/Synthetic" \
  --metric-data MetricName=HealthCheckResponseCode,Value=$HTTP_CODE,Unit=Count

aws cloudwatch put-metric-data \
  --namespace "Energrid/Synthetic" \
  --metric-data MetricName=HealthCheckResponseTime,Value=$RESPONSE_TIME,Unit=Seconds

# Alert if unhealthy
if [ "$HTTP_CODE" != "200" ]; then
  aws sns publish \
    --topic-arn arn:aws:sns:us-east-1:ACCOUNT:energrid-alerts \
    --message "Health check failed: HTTP $HTTP_CODE, Response time: ${RESPONSE_TIME}s"
fi

echo "Health check: HTTP $HTTP_CODE, Response time: ${RESPONSE_TIME}s"
```

## Monitoring Automation

### Automated Report Generation

#### Daily Operations Report
```python
#!/usr/bin/env python3
# daily-report.py

import boto3
import json
from datetime import datetime, timedelta
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def generate_daily_report():
    cloudwatch = boto3.client('cloudwatch')
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=1)
    
    report = {
        'date': end_time.strftime('%Y-%m-%d'),
        'metrics': {}
    }
    
    # Get API metrics
    api_metrics = cloudwatch.get_metric_statistics(
        Namespace='AWS/ApplicationELB',
        MetricName='RequestCount',
        Dimensions=[{'Name': 'LoadBalancer', 'Value': 'energrid-alb'}],
        StartTime=start_time,
        EndTime=end_time,
        Period=86400,
        Statistics=['Sum']
    )
    
    if api_metrics['Datapoints']:
        report['metrics']['api_requests'] = api_metrics['Datapoints'][0]['Sum']
    
    # Get contract metrics
    contract_metrics = cloudwatch.get_metric_statistics(
        Namespace='Energrid/Contracts',
        MetricName='ContractCalls',
        StartTime=start_time,
        EndTime=end_time,
        Period=86400,
        Statistics=['Sum']
    )
    
    if contract_metrics['Datapoints']:
        report['metrics']['contract_calls'] = contract_metrics['Datapoints'][0]['Sum']
    
    # Get error count
    error_metrics = cloudwatch.get_metric_statistics(
        Namespace='AWS/ApplicationELB',
        MetricName='HTTPCode_Target_5XX_Count',
        Dimensions=[{'Name': 'LoadBalancer', 'Value': 'energrid-alb'}],
        StartTime=start_time,
        EndTime=end_time,
        Period=86400,
        Statistics=['Sum']
    )
    
    if error_metrics['Datapoints']:
        report['metrics']['api_errors'] = error_metrics['Datapoints'][0]['Sum']
    else:
        report['metrics']['api_errors'] = 0
    
    # Generate and send report
    send_daily_report(report)

def send_daily_report(report):
    ses = boto3.client('ses')
    
    html_content = f"""
    <html>
    <body>
        <h2>Energrid Daily Operations Report - {report['date']}</h2>
        <table border="1">
            <tr><th>Metric</th><th>Value</th></tr>
            <tr><td>API Requests</td><td>{report['metrics'].get('api_requests', 'N/A')}</td></tr>
            <tr><td>Contract Calls</td><td>{report['metrics'].get('contract_calls', 'N/A')}</td></tr>
            <tr><td>API Errors</td><td>{report['metrics'].get('api_errors', 'N/A')}</td></tr>
        </table>
        
        <h3>Status</h3>
        <p>System Status: {'🟢 Healthy' if report['metrics'].get('api_errors', 0) < 10 else '🔴 Attention Required'}</p>
        
        <h3>Next Actions</h3>
        <ul>
            <li>Review error logs if error count > 10</li>
            <li>Monitor gas price trends</li>
            <li>Check contract supply utilization</li>
        </ul>
    </body>
    </html>
    """
    
    ses.send_email(
        Source='noreply@energrid.com',
        Destination={
            'ToAddresses': ['devops@energrid.com', 'management@energrid.com']
        },
        Message={
            'Subject': {'Data': f'Energrid Daily Report - {report["date"]}'},
            'Body': {
                'Html': {'Data': html_content}
            }
        }
    )

if __name__ == '__main__':
    generate_daily_report()
```

### Monitoring as Code

#### Terraform Monitoring Module
```hcl
# modules/monitoring/main.tf
module "energrid_monitoring" {
  source = "./modules/monitoring"
  
  project_name     = "energrid"
  environment      = var.environment
  alert_email      = var.alert_email
  pagerduty_key    = var.pagerduty_integration_key
  slack_webhook    = var.slack_webhook_url
  
  # Contract addresses
  kwh_token_address    = var.kwh_token_address
  cel_token_address    = var.cel_token_address
  factory_address      = var.factory_address
  
  # Thresholds
  api_response_time_threshold    = 2000  # milliseconds
  error_rate_threshold          = 5     # percentage
  gas_price_threshold           = 100   # gwei
  cpu_utilization_threshold     = 80    # percentage
}
```

This comprehensive monitoring setup provides:
- Real-time visibility into smart contract and infrastructure health
- Automated alerting for critical issues
- Performance tracking and optimization insights
- Compliance reporting and audit trails
- Proactive issue detection and resolution
