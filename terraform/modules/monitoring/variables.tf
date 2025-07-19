# Monitoring Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = ""
}

variable "ecs_service_names" {
  description = "List of ECS service names"
  type        = list(string)
  default     = []
}

variable "lambda_function_names" {
  description = "List of Lambda function names"
  type        = list(string)
  default     = []
}

variable "api_gateway_name" {
  description = "API Gateway name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
