# Lambda Functions Module for Energrid - Auxiliary Services
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local values for Lambda configuration
locals {
  lambda_functions = {
    auth = {
      filename     = "auth.zip"
      handler      = "index.handler"
      runtime      = "python3.11"
      timeout      = 30
      memory_size  = 256
      environment_variables = {
        ENVIRONMENT = var.environment
        COGNITO_USER_POOL_ID = aws_cognito_user_pool.energrid.id
        COGNITO_CLIENT_ID = aws_cognito_user_pool_client.energrid.id
      }
      vpc_config = false
    }
    
    notifications = {
      filename     = "notifications.zip"
      handler      = "index.handler"
      runtime      = "python3.11"
      timeout      = 60
      memory_size  = 512
      environment_variables = {
        ENVIRONMENT = var.environment
        SNS_TOPIC_ARN = aws_sns_topic.energrid_notifications.arn
        SES_REGION = var.aws_region
      }
      vpc_config = false
    }
    
    analytics = {
      filename     = "analytics.zip"
      handler      = "index.handler"
      runtime      = "python3.11"
      timeout      = 900
      memory_size  = 1024
      environment_variables = {
        ENVIRONMENT = var.environment
        S3_BUCKET = aws_s3_bucket.analytics.id
        DATABASE_URL = var.database_endpoint
      }
      vpc_config = true
    }
    
    certificates = {
      filename     = "certificates.zip"
      handler      = "index.handler"
      runtime      = "python3.11"
      timeout      = 300
      memory_size  = 512
      environment_variables = {
        ENVIRONMENT = var.environment
        S3_BUCKET = aws_s3_bucket.certificates.id
        TEMPLATE_BUCKET = aws_s3_bucket.certificate_templates.id
      }
      vpc_config = false
    }
    
    crud_api = {
      filename     = "crud-api.zip"
      handler      = "index.handler"
      runtime      = "python3.11"
      timeout      = 30
      memory_size  = 256
      environment_variables = {
        ENVIRONMENT = var.environment
        DYNAMODB_TABLE = aws_dynamodb_table.energrid_data.name
        AWS_REGION = var.aws_region
      }
      vpc_config = false
    }
    
    webhooks = {
      filename     = "webhooks.zip"
      handler      = "index.handler"
      runtime      = "python3.11"
      timeout      = 60
      memory_size  = 256
      environment_variables = {
        ENVIRONMENT = var.environment
        SQS_QUEUE_URL = aws_sqs_queue.webhook_queue.url
      }
      vpc_config = false
    }
  }
}

# Lambda Functions
resource "aws_lambda_function" "energrid_functions" {
  for_each = local.lambda_functions
  
  filename         = "${path.module}/lambda-packages/${each.value.filename}"
  function_name    = "${var.project_name}-${each.key}-${var.environment}"
  role            = var.lambda_execution_role_arn
  handler         = each.value.handler
  runtime         = each.value.runtime
  timeout         = each.value.timeout
  memory_size     = each.value.memory_size
  
  # VPC configuration for functions that need database access
  dynamic "vpc_config" {
    for_each = each.value.vpc_config ? [1] : []
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [var.lambda_security_group_id]
    }
  }
  
  environment {
    variables = each.value.environment_variables
  }
  
  depends_on = [
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(var.tags, {
    Name        = "${var.project_name}-${each.key}-lambda"
    Function    = each.key
    ServiceType = "lambda"
  })
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = local.lambda_functions
  
  name              = "/aws/lambda/${var.project_name}-${each.key}-${var.environment}"
  retention_in_days = 14
  
  tags = var.tags
}

# Cognito User Pool for Authentication
resource "aws_cognito_user_pool" "energrid" {
  name = "${var.project_name}-users-${var.environment}"
  
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  
  auto_verified_attributes = ["email"]
  
  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
  }
  
  tags = var.tags
}

resource "aws_cognito_user_pool_client" "energrid" {
  name         = "${var.project_name}-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.energrid.id
  
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["phone", "email", "openid", "profile"]
  supported_identity_providers         = ["COGNITO"]
  
  callback_urls = [
    "https://${var.project_name}-${var.environment}.example.com/callback"
  ]
  
  logout_urls = [
    "https://${var.project_name}-${var.environment}.example.com/logout"
  ]
}

# SNS Topic for Notifications
resource "aws_sns_topic" "energrid_notifications" {
  name = "${var.project_name}-notifications-${var.environment}"
  
  tags = var.tags
}

# SQS Queue for Webhooks
resource "aws_sqs_queue" "webhook_queue" {
  name                      = "${var.project_name}-webhooks-${var.environment}"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 1209600
  receive_wait_time_seconds = 10
  
  tags = var.tags
}

# Dead Letter Queue for failed webhook processing
resource "aws_sqs_queue" "webhook_dlq" {
  name = "${var.project_name}-webhooks-dlq-${var.environment}"
  
  tags = var.tags
}

# Redrive policy for webhook queue
resource "aws_sqs_queue_redrive_policy" "webhook_redrive" {
  queue_url = aws_sqs_queue.webhook_queue.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhook_dlq.arn
    maxReceiveCount     = 3
  })
}

# Lambda trigger for SQS
resource "aws_lambda_event_source_mapping" "webhook_trigger" {
  event_source_arn = aws_sqs_queue.webhook_queue.arn
  function_name    = aws_lambda_function.energrid_functions["webhooks"].arn
  batch_size       = 10
}

# DynamoDB Table for CRUD operations
resource "aws_dynamodb_table" "energrid_data" {
  name           = "${var.project_name}-data-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  
  attribute {
    name = "id"
    type = "S"
  }
  
  attribute {
    name = "user_id"
    type = "S"
  }
  
  attribute {
    name = "created_at"
    type = "S"
  }
  
  global_secondary_index {
    name               = "UserIndex"
    hash_key           = "user_id"
    range_key          = "created_at"
    projection_type    = "ALL"
  }
  
  point_in_time_recovery {
    enabled = var.environment == "production"
  }
  
  server_side_encryption {
    enabled = true
  }
  
  tags = var.tags
}

# S3 Buckets for Lambda services
resource "aws_s3_bucket" "analytics" {
  bucket = "${var.project_name}-analytics-${var.environment}-${random_id.bucket_suffix.hex}"
  
  tags = var.tags
}

resource "aws_s3_bucket" "certificates" {
  bucket = "${var.project_name}-certificates-${var.environment}-${random_id.bucket_suffix.hex}"
  
  tags = var.tags
}

resource "aws_s3_bucket" "certificate_templates" {
  bucket = "${var.project_name}-cert-templates-${var.environment}-${random_id.bucket_suffix.hex}"
  
  tags = var.tags
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket configurations
resource "aws_s3_bucket_versioning" "analytics" {
  bucket = aws_s3_bucket.analytics.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "analytics" {
  bucket = aws_s3_bucket.analytics.id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_encryption" "certificates" {
  bucket = aws_s3_bucket.certificates.id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_encryption" "certificate_templates" {
  bucket = aws_s3_bucket.certificate_templates.id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}
