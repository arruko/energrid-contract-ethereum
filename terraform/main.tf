# Main Terraform configuration for Energrid production deployment

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    # Backend configuration will be provided via -backend-config
    # or through environment variables
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Local values
locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = data.aws_region.current.name
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "devops"
  }
}

# Networking Module
module "networking" {
  source = "./modules/networking"
  
  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr          = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Security Module
module "security" {
  source = "./modules/security"
  
  project_name       = var.project_name
  environment        = var.environment
  vpc_id            = module.networking.vpc_id
  app_port          = var.app_port
  admin_cidr_blocks = var.admin_cidr_blocks
  enable_bastion    = var.enable_bastion
  rate_limit        = var.waf_rate_limit
}

# ECS Module
module "ecs" {
  source = "./modules/ecs"
  
  project_name           = var.project_name
  environment           = var.environment
  aws_region            = local.aws_region
  aws_account_id        = local.aws_account_id
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  ecs_security_group_id = module.security.ecs_security_group_id
  
  # Application configuration
  app_image             = var.app_image
  app_port             = var.app_port
  task_cpu             = var.task_cpu
  task_memory          = var.task_memory
  desired_count        = var.desired_count
  network              = var.blockchain_network
  ssl_certificate_arn  = var.ssl_certificate_arn
  
  # Logging and monitoring
  enable_alb_logs      = var.enable_alb_logs
  alb_logs_bucket      = var.alb_logs_bucket
  log_retention_days   = var.log_retention_days
  enable_execute_command = var.enable_ecs_exec
}

# RDS Subnet Group
resource "aws_db_subnet_group" "energrid" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = module.networking.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

# RDS Instance (if enabled)
resource "aws_db_instance" "energrid" {
  count = var.enable_rds ? 1 : 0
  
  identifier     = "${var.project_name}-${var.environment}"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.rds_instance_class
  
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type         = "gp3"
  storage_encrypted    = true
  
  db_name  = var.database_name
  username = var.database_username
  password = var.database_password
  
  vpc_security_group_ids = [module.security.rds_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.energrid.name
  
  backup_retention_period = var.rds_backup_retention
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  skip_final_snapshot = var.environment != "production"
  deletion_protection = var.environment == "production"
  
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-database"
  })
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "energrid" {
  count = var.enable_elasticache ? 1 : 0
  
  name       = "${var.project_name}-cache-subnet"
  subnet_ids = module.networking.private_subnet_ids
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cache-subnet"
  })
}

# ElastiCache Redis Cluster
resource "aws_elasticache_replication_group" "energrid" {
  count = var.enable_elasticache ? 1 : 0
  
  replication_group_id       = "${var.project_name}-redis"
  description                = "Redis cluster for ${var.project_name}"
  
  node_type                  = var.redis_node_type
  port                       = 6379
  parameter_group_name       = "default.redis7"
  
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled          = true
  
  subnet_group_name = aws_elasticache_subnet_group.energrid[0].name
  security_group_ids = [module.security.elasticache_security_group_id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow[0].name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-redis"
  })
}

resource "aws_cloudwatch_log_group" "redis_slow" {
  count = var.enable_elasticache ? 1 : 0
  
  name              = "/aws/elasticache/${var.project_name}/redis-slow"
  retention_in_days = 7
  
  tags = local.common_tags
}

# S3 Bucket for ALB logs
resource "aws_s3_bucket" "alb_logs" {
  count = var.enable_alb_logs ? 1 : 0
  
  bucket        = "${var.project_name}-alb-logs-${local.aws_account_id}"
  force_destroy = var.environment != "production"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb-logs"
  })
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  count = var.enable_alb_logs ? 1 : 0
  
  bucket = aws_s3_bucket.alb_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "alb_logs" {
  count = var.enable_alb_logs ? 1 : 0
  
  bucket = aws_s3_bucket.alb_logs[0].id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count = var.enable_alb_logs ? 1 : 0
  
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "delete_old_logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
