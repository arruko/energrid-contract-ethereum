# API Gateway Module for Energrid - Unified Entry Point
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "energrid" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "Unified API Gateway for Energrid hybrid architecture"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  binary_media_types = ["*/*"]
  
  tags = var.tags
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "energrid" {
  depends_on = [
    aws_api_gateway_integration.lambda_proxy,
    aws_api_gateway_integration.ecs_proxy,
  ]
  
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  stage_name  = var.environment
  
  lifecycle {
    create_before_destroy = true
  }
}

# ============================================
# Lambda Function Integrations
# ============================================

# Auth endpoints
resource "aws_api_gateway_resource" "auth" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  parent_id   = aws_api_gateway_rest_api.energrid.root_resource_id
  path_part   = "auth"
}

resource "aws_api_gateway_method" "auth_post" {
  rest_api_id   = aws_api_gateway_rest_api.energrid.id
  resource_id   = aws_api_gateway_resource.auth.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "auth_lambda" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  resource_id = aws_api_gateway_resource.auth.id
  http_method = aws_api_gateway_method.auth_post.http_method
  
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = lookup(var.lambda_functions, "auth", "")
}

# CRUD API endpoints
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  parent_id   = aws_api_gateway_rest_api.energrid.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "api_proxy" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "api_any" {
  rest_api_id   = aws_api_gateway_rest_api.energrid.id
  resource_id   = aws_api_gateway_resource.api_proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_proxy" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  resource_id = aws_api_gateway_resource.api_proxy.id
  http_method = aws_api_gateway_method.api_any.http_method
  
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = lookup(var.lambda_functions, "crud_api", "")
}

# Webhooks endpoints
resource "aws_api_gateway_resource" "webhooks" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  parent_id   = aws_api_gateway_rest_api.energrid.root_resource_id
  path_part   = "webhooks"
}

resource "aws_api_gateway_method" "webhooks_post" {
  rest_api_id   = aws_api_gateway_rest_api.energrid.id
  resource_id   = aws_api_gateway_resource.webhooks.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "webhooks_lambda" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  resource_id = aws_api_gateway_resource.webhooks.id
  http_method = aws_api_gateway_method.webhooks_post.http_method
  
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = lookup(var.lambda_functions, "webhooks", "")
}

# ============================================
# ECS Service Integrations
# ============================================

# Trading engine endpoints (high-performance)
resource "aws_api_gateway_resource" "trading" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  parent_id   = aws_api_gateway_rest_api.energrid.root_resource_id
  path_part   = "trading"
}

resource "aws_api_gateway_resource" "trading_proxy" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  parent_id   = aws_api_gateway_resource.trading.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "trading_any" {
  rest_api_id   = aws_api_gateway_rest_api.energrid.id
  resource_id   = aws_api_gateway_resource.trading_proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "ecs_proxy" {
  count = var.ecs_alb_dns != "" ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  resource_id = aws_api_gateway_resource.trading_proxy.id
  http_method = aws_api_gateway_method.trading_any.http_method
  
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${var.ecs_alb_dns}/trading/{proxy}"
  
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

# Blockchain node endpoints
resource "aws_api_gateway_resource" "blockchain" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  parent_id   = aws_api_gateway_rest_api.energrid.root_resource_id
  path_part   = "blockchain"
}

resource "aws_api_gateway_resource" "blockchain_proxy" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  parent_id   = aws_api_gateway_resource.blockchain.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "blockchain_any" {
  rest_api_id   = aws_api_gateway_rest_api.energrid.id
  resource_id   = aws_api_gateway_resource.blockchain_proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "blockchain_ecs" {
  count = var.ecs_alb_dns != "" ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  resource_id = aws_api_gateway_resource.blockchain_proxy.id
  http_method = aws_api_gateway_method.blockchain_any.http_method
  
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${var.ecs_alb_dns}/blockchain/{proxy}"
  
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

# ============================================
# Lambda Permissions
# ============================================

resource "aws_lambda_permission" "api_gateway_auth" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = lookup(var.lambda_functions, "auth", "")
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.energrid.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_crud" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = lookup(var.lambda_functions, "crud_api", "")
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.energrid.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_webhooks" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = lookup(var.lambda_functions, "webhooks", "")
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.energrid.execution_arn}/*/*"
}

# ============================================
# API Gateway Throttling and Usage Plan
# ============================================

resource "aws_api_gateway_usage_plan" "energrid" {
  name = "${var.project_name}-usage-plan-${var.environment}"
  
  api_stages {
    api_id = aws_api_gateway_rest_api.energrid.id
    stage  = aws_api_gateway_deployment.energrid.stage_name
  }
  
  quota_settings {
    limit  = 10000
    period = "DAY"
  }
  
  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }
  
  tags = var.tags
}

# API Key for external integrations
resource "aws_api_gateway_api_key" "energrid" {
  name = "${var.project_name}-api-key-${var.environment}"
  
  tags = var.tags
}

resource "aws_api_gateway_usage_plan_key" "energrid" {
  key_id        = aws_api_gateway_api_key.energrid.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.energrid.id
}

# ============================================
# CloudWatch Logging
# ============================================

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = 14
  
  tags = var.tags
}

resource "aws_api_gateway_account" "energrid" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${var.project_name}-api-gateway-cloudwatch-${var.environment}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Enable access logging for the API Gateway stage
resource "aws_api_gateway_method_settings" "energrid" {
  rest_api_id = aws_api_gateway_rest_api.energrid.id
  stage_name  = aws_api_gateway_deployment.energrid.stage_name
  method_path = "*/*"
  
  settings {
    logging_level      = "INFO"
    data_trace_enabled = var.environment != "production"
    metrics_enabled    = true
    
    throttling_rate_limit  = 100
    throttling_burst_limit = 200
  }
}
