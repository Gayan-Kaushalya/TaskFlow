# Subnet group placing RDS strictly across private subnets
resource "aws_db_subnet_group" "main" {
  name       = "taskflow-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "taskflow-db-subnet-group" }
}

# Security group allowing PostgreSQL traffic only from the ECS cluster
resource "aws_security_group" "rds" {
  name        = "taskflow-rds-sg"
  description = "Allow inbound postgres traffic from ECS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_db_instance" "postgres" {
  identifier             = "taskflow-postgres"
  engine                 = "postgres"
  engine_version         = "15.4"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  db_name                = "taskflow"
  username               = "taskflow_admin"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
}

# Store database connection URL in Secrets Manager
resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "taskflow/db-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    DATABASE_URL = "postgresql://${aws_db_instance.postgres.username}:${random_password.db_password.result}@${aws_db_instance.postgres.endpoint}/${aws_db_instance.postgres.db_name}"
  })
}
