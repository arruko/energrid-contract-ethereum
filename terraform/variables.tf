# Project Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "energrid"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

# Networking Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed for admin access"
  type        = list(string)
  default     = []
}

variable "enable_bastion" {
  description = "Enable bastion host for emergency access"
  type        = bool
  default     = false
}

# Application Configuration
variable "app_image" {
  description = "Docker image for the application"
  type        = string
  default     = "energrid/api:latest"
}

variable "app_port" {
  description = "Port on which the application runs"
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "CPU units for ECS tasks (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 1024
  
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.task_cpu)
    error_message = "Task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  description = "Memory for ECS tasks in MB"
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "blockchain_network" {
  description = "Blockchain network to connect to"
  type        = string
  default     = "mainnet"
  
  validation {
    condition     = contains(["mainnet", "sepolia", "goerli", "polygon", "arbitrum"], var.blockchain_network)
    error_message = "Blockchain network must be one of: mainnet, sepolia, goerli, polygon, arbitrum."
  }
}

# SSL Configuration
variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = ""
}

# Database Configuration
variable "enable_rds" {
  description = "Enable RDS database"
  type        = bool
  default     = true
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Initial storage allocation for RDS"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum storage allocation for RDS"
  type        = number
  default     = 100
}

variable "rds_backup_retention" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "energrid"
}

variable "database_username" {
  description = "Database username"
  type        = string
  default     = "energrid"
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

# ElastiCache Configuration
variable "enable_elasticache" {
  description = "Enable ElastiCache Redis"
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

# Security Configuration
variable "waf_rate_limit" {
  description = "WAF rate limit (requests per 5 minutes)"
  type        = number
  default     = 2000
}

# Logging Configuration
variable "enable_alb_logs" {
  description = "Enable ALB access logs"
  type        = bool
  default     = true
}

variable "alb_logs_bucket" {
  description = "S3 bucket for ALB logs (will be created if enable_alb_logs is true)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# Monitoring and Debugging
variable "enable_ecs_exec" {
  description = "Enable ECS Execute Command for debugging"
  type        = bool
  default     = false
}

# Auto Scaling Configuration
variable "enable_auto_scaling" {
  description = "Enable ECS service auto scaling"
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Minimum number of tasks for auto scaling"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto scaling"
  type        = number
  default     = 10
}

variable "scale_up_threshold" {
  description = "CPU utilization threshold to scale up"
  type        = number
  default     = 70
}

variable "scale_down_threshold" {
  description = "CPU utilization threshold to scale down"
  type        = number
  default     = 30
}
