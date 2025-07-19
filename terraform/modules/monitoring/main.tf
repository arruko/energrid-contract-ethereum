# Monitoring Module for Energrid Hybrid Architecture
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts-${var.environment}"
  
  tags = var.tags
}

# CloudWatch Dashboard for Hybrid Architecture
resource "aws_cloudwatch_dashboard" "energrid" {
  dashboard_name = "${var.project_name}-dashboard-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      # ECS Metrics
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", var.ecs_cluster_name],
            [".", "MemoryUtilization", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "ECS Service Metrics"
          period  = 300
        }
      },
      
      # Lambda Metrics
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = flatten([
            for fn_name in var.lambda_function_names : [
              ["AWS/Lambda", "Duration", "FunctionName", fn_name],
              [".", "Errors", ".", "."],
              [".", "Invocations", ".", "."]
            ]
          ])
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Metrics"
          period  = 300
        }
      },
      
      # API Gateway Metrics
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name],
            [".", "Latency", ".", "."],
            [".", "4XXError", ".", "."],
            [".", "5XXError", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "API Gateway Metrics"
          period  = 300
        }
      },
      
      # Database Metrics
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${var.project_name}-db-${var.environment}"],
            [".", "DatabaseConnections", ".", "."],
            [".", "ReadLatency", ".", "."],
            [".", "WriteLatency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Database Metrics"
          period  = 300
        }
      }
    ]
  })
}

# ECS Service Alarms
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  count = var.ecs_cluster_name != "" ? 1 : 0
  
  alarm_name          = "${var.project_name}-ecs-cpu-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  
  dimensions = {
    ServiceName = var.ecs_cluster_name
    ClusterName = var.ecs_cluster_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  count = var.ecs_cluster_name != "" ? 1 : 0
  
  alarm_name          = "${var.project_name}-ecs-memory-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS memory utilization"
  
  dimensions = {
    ServiceName = var.ecs_cluster_name
    ClusterName = var.ecs_cluster_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = var.tags
}

# Lambda Function Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(var.lambda_function_names)
  
  alarm_name          = "${var.project_name}-lambda-${each.key}-errors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    FunctionName = each.key
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = toset(var.lambda_function_names)
  
  alarm_name          = "${var.project_name}-lambda-${each.key}-duration-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "30000"  # 30 seconds
  alarm_description   = "This metric monitors Lambda function duration"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    FunctionName = each.key
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = var.tags
}

# API Gateway Alarms
resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx" {
  alarm_name          = "${var.project_name}-api-4xx-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors API Gateway 4XX errors"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ApiName = var.api_gateway_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  alarm_name          = "${var.project_name}-api-5xx-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ApiName = var.api_gateway_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_latency" {
  alarm_name          = "${var.project_name}-api-latency-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = "2000"  # 2 seconds
  alarm_description   = "This metric monitors API Gateway latency"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ApiName = var.api_gateway_name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = var.tags
}

# Custom Metrics for Trading Engine (ECS)
resource "aws_cloudwatch_log_metric_filter" "trading_transactions" {
  count = var.ecs_cluster_name != "" ? 1 : 0
  
  name           = "TradingTransactions"
  log_group_name = "/ecs/${var.project_name}-trading-engine"
  pattern        = "[timestamp, request_id, level=\"INFO\", message=\"TRADE_COMPLETED\", ...]"

  metric_transformation {
    name      = "TradingTransactionsCount"
    namespace = "Energrid/Trading"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "trading_transactions_low" {
  count = var.ecs_cluster_name != "" ? 1 : 0
  
  alarm_name          = "${var.project_name}-trading-transactions-low-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "TradingTransactionsCount"
  namespace           = "Energrid/Trading"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors trading transaction volume"
  treat_missing_data  = "breaching"
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = var.tags
}

# Get current AWS region
data "aws_region" "current" {}
