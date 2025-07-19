# API Gateway Module Outputs

output "api_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.energrid.id
}

output "api_name" {
  description = "API Gateway REST API name"
  value       = aws_api_gateway_rest_api.energrid.name
}

output "api_endpoint" {
  description = "API Gateway invoke URL"
  value       = "https://${aws_api_gateway_rest_api.energrid.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_deployment.energrid.stage_name}"
}

output "api_key_id" {
  description = "API Gateway API Key ID"
  value       = aws_api_gateway_api_key.energrid.id
}

output "usage_plan_id" {
  description = "API Gateway Usage Plan ID"
  value       = aws_api_gateway_usage_plan.energrid.id
}

# Data source for current AWS region
data "aws_region" "current" {}
