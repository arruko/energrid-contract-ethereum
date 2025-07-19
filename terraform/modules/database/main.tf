# Database Module for Energrid
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "energrid" {
  name       = "${var.project_name}-db-subnet-group-${var.environment}"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

# RDS Parameter Group
resource "aws_db_parameter_group" "energrid" {
  name_prefix = "${var.project_name}-db-params-"
  family      = "mysql8.0"
  description = "Custom parameter group for Energrid"

  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "max_connections"
    value = "1000"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Instance
resource "aws_db_instance" "energrid" {
  identifier = "${var.project_name}-db-${var.environment}"
  
  # Engine configuration
  engine                = "mysql"
  engine_version        = "8.0.35"
  instance_class        = var.instance_class
  
  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true
  
  # Database configuration
  db_name  = var.database_name
  username = var.database_username
  password = var.database_password
  port     = 3306
  
  # Network configuration
  vpc_security_group_ids = [var.db_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.energrid.name
  parameter_group_name   = aws_db_parameter_group.energrid.name
  
  # Backup configuration
  backup_retention_period   = var.environment == "production" ? 30 : 7
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true
  
  # Performance configuration
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
  
  # Security configuration
  deletion_protection = var.environment == "production"
  skip_final_snapshot = var.environment != "production"
  
  # Logging
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-database"
  })
}

# RDS Enhanced Monitoring Role
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Read Replica (for production)
resource "aws_db_instance" "energrid_replica" {
  count = var.environment == "production" ? 1 : 0
  
  identifier             = "${var.project_name}-db-replica-${var.environment}"
  replicate_source_db    = aws_db_instance.energrid.identifier
  instance_class         = var.instance_class
  
  vpc_security_group_ids = [var.db_security_group_id]
  
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
  
  skip_final_snapshot = true
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-database-replica"
    Role = "read-replica"
  })
}

# Database CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "db_audit" {
  name              = "/aws/rds/instance/${aws_db_instance.energrid.identifier}/audit"
  retention_in_days = 30
  
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "db_error" {
  name              = "/aws/rds/instance/${aws_db_instance.energrid.identifier}/error"
  retention_in_days = 30
  
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "db_general" {
  name              = "/aws/rds/instance/${aws_db_instance.energrid.identifier}/general"
  retention_in_days = 7
  
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "db_slowquery" {
  name              = "/aws/rds/instance/${aws_db_instance.energrid.identifier}/slowquery"
  retention_in_days = 30
  
  tags = var.tags
}
