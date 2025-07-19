# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.networking.public_subnet_ids
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs.service_name
}

# Load Balancer Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.ecs.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = module.ecs.alb_zone_id
}

output "application_url" {
  description = "URL of the application"
  value       = "https://${module.ecs.alb_dns_name}"
}

# Security Outputs
output "waf_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = module.security.waf_acl_arn
}

# Database Outputs
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = var.enable_rds ? aws_db_instance.energrid[0].endpoint : null
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = var.enable_rds ? aws_db_instance.energrid[0].port : null
}

# Cache Outputs
output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = var.enable_elasticache ? aws_elasticache_replication_group.energrid[0].configuration_endpoint_address : null
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = var.enable_elasticache ? aws_elasticache_replication_group.energrid[0].port : null
}

# IAM Outputs
output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = module.ecs.task_execution_role_arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role"
  value       = module.ecs.task_role_arn
}

# S3 Outputs
output "alb_logs_bucket" {
  description = "S3 bucket for ALB logs"
  value       = var.enable_alb_logs ? aws_s3_bucket.alb_logs[0].bucket : null
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    project_name      = var.project_name
    environment       = var.environment
    aws_region        = data.aws_region.current.name
    vpc_cidr          = var.vpc_cidr
    blockchain_network = var.blockchain_network
    app_port          = var.app_port
    desired_count     = var.desired_count
    task_cpu          = var.task_cpu
    task_memory       = var.task_memory
    rds_enabled       = var.enable_rds
    cache_enabled     = var.enable_elasticache
    auto_scaling      = var.enable_auto_scaling
  }
}
