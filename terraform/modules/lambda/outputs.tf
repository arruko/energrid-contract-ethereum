# Lambda Module Outputs

output "function_arns" {
  description = "ARNs of all Lambda functions"
  value = {
    for name, func in aws_lambda_function.energrid_functions : name => func.arn
  }
}

output "function_names" {
  description = "Names of all Lambda functions"
  value = {
    for name, func in aws_lambda_function.energrid_functions : name => func.function_name
  }
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.energrid.id
}

output "cognito_client_id" {
  description = "Cognito Client ID"
  value       = aws_cognito_user_pool_client.energrid.id
}

output "sns_topic_arn" {
  description = "SNS Topic ARN for notifications"
  value       = aws_sns_topic.energrid_notifications.arn
}

output "sqs_queue_url" {
  description = "SQS Queue URL for webhooks"
  value       = aws_sqs_queue.webhook_queue.url
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for CRUD operations"
  value       = aws_dynamodb_table.energrid_data.name
}

output "s3_buckets" {
  description = "S3 bucket names"
  value = {
    analytics   = aws_s3_bucket.analytics.id
    certificates = aws_s3_bucket.certificates.id
    templates   = aws_s3_bucket.certificate_templates.id
  }
}
