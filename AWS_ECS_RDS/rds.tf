# RDS PostgreSQL

# サブネット
resource "aws_db_subnet_group" "main" {
  name       = "myapi-db-subnet"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name = "myapi-db-subnet"
  }
}

# RDSセキュリティグループ。ECSタスク用SGからのみ接続可能
resource "aws_security_group" "rds" {
  name        = "myapi-rds-sg"
  description = "Allow ECS tasks to access RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS。パスワードはSecrets Managerから参照
resource "aws_db_instance" "main" {
  identifier             = "myapi-db"
  engine                 = "postgres"
  engine_version         = "17.6"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = "iamuser01"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = false
  skip_final_snapshot    = true
  publicly_accessible    = false
}

# パスワード生成。@はRDSでNG
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "-_+"
  lifecycle {
    prevent_destroy = true # destroy時はfalse
  }
}

resource "random_password" "django_secret_key" {
  length           = 50
  special          = true
  override_special = "-_+"
}

# Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.project_name}/${var.environment}/db-password"
}

# シークレットの値(パスワード)をSecrets Managerに登録
resource "aws_secretsmanager_secret_version" "db_password_value" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_secretsmanager_secret" "django_secret_key" {
  name = "api_server/portfolio/secret-key"
}

resource "aws_secretsmanager_secret_version" "django_secret_key" {
  secret_id     = aws_secretsmanager_secret.django_secret_key.id
  secret_string = random_password.django_secret_key.result
}
