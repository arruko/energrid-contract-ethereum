# Database Module Outputs

output "endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.energrid.endpoint
}

output "port" {
  description = "RDS instance port"
  value       = aws_db_instance.energrid.port
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.energrid.db_name
}

output "username" {
  description = "Database username"
  value       = aws_db_instance.energrid.username
  sensitive   = true
}

output "replica_endpoint" {
  description = "RDS read replica endpoint"
  value       = var.environment == "production" ? aws_db_instance.energrid_replica[0].endpoint : null
}

output "instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.energrid.id
}

output "arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.energrid.arn
}
