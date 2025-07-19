variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "app_image" {
  description = "Docker image for the application"
  type        = string
}

variable "app_port" {
  description = "Port on which the application runs"
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "CPU units for the task"
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Memory for the task in MB"
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 2
}

variable "network" {
  description = "Blockchain network (mainnet, sepolia, etc.)"
  type        = string
  default     = "mainnet"
}

variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate"
  type        = string
}

variable "enable_alb_logs" {
  description = "Enable ALB access logs"
  type        = bool
  default     = true
}

variable "alb_logs_bucket" {
  description = "S3 bucket for ALB logs"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "enable_execute_command" {
  description = "Enable ECS Execute Command"
  type        = bool
  default     = false
}
