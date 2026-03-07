terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# サブネット（パブリック）
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = element(["ap-northeast-1a", "ap-northeast-1c"], count.index)
  map_public_ip_on_launch = true
}

# サブネット（プライベート）
resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = element(["ap-northeast-1a", "ap-northeast-1c"], count.index)
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Route Tables

# Public Route Table(IGWへ)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "portfolio-rt-public"
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Public subnet -> public RT(明示的に関連付け)
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table(NAT無しなのでデフォルトルートは作らない)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "portfolio-rt-private"
  }
}

# Private subnet -> private RT(明示的に関連付け)
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ALBセキュリティグループ(FWの役割。ALBに設置)
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTP inbound"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# VPC Endpoint
locals {
  private_subnet_ids = aws_subnet.private[*].id
}

# VPC Endpointセキュリティグループ
resource "aws_security_group" "vpc_endpoint" {
  name        = "portfolio-vpce-sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id] # ECSのSGからの通信のみ許可
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECR API(VPC Endpoint)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.ecs.id]
  private_dns_enabled = true
}

# ECR DKR(VPC Endpoint)。DKR=Docker
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.ecs.id]
  private_dns_enabled = true
}

# Secrets Manager(VPC Endpoint)
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.ecs.id]
  private_dns_enabled = true
}

# CloudWatch Logs(VPC Endpoint)
resource "aws_vpc_endpoint" "logs" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.ecs.id]
  private_dns_enabled = true
}

# STS(VPC Endpoint)(IAM Role / Task Credential用)
resource "aws_vpc_endpoint" "sts" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.ecs.id]
  private_dns_enabled = true
}

# SSM Messages(VPC Endpoint)(ECS Execの通信チャネル用)
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages" # 東京なら ap-northeast-1
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id] # エンドポイント用SG
  private_dns_enabled = true
}

# SSM(VPC Endpoint)(SSMコア機能用)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true
}

# ALB。インターネットからアクセスされるのでパブリックサブネットに置く
resource "aws_lb" "alb" {
  name               = "portfolio-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

# ターゲットグループ(ALBがリクエストを転送する先のグループ)
resource "aws_lb_target_group" "tg" {
  name     = "portfolio-tg"
  port     = var.container_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/healthz"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
}

# リスナー(受け取る通信の入り口)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
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
  length  = 50
  special = true
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
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
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
  identifier         = "myapi-db"
  engine             = "postgres"
  engine_version     = "17.6"
  instance_class     = "db.t3.micro"
  allocated_storage  = 20
  db_name               = var.db_name
  username           = "iamuser01"
  password           = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az           = false
  skip_final_snapshot = true
  publicly_accessible = false
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.ecs_cluster_name
}

# ECR
resource "aws_ecr_repository" "main" {
  name = var.ecr_repository_name
}
# destroy時に、残っているイメージもまとめて削除したい場合は
# name = の次にforce_delete = trueを追記してdestroy(変更反映のapplyは必要ない) 

# Execution Role：ECSエージェントが使う(ECR pull,CloudWatch Logs,Secrets取得,など「起動時」)
# Task Role：アプリ(Django)コンテナが使う(実行中にAWS APIを叩く等)
# 1つのIAMロールにTask RoleとExecution Roleを両方定義するのではない。
# Task Role用とExecution Role用に、別々のIAMロールを2つ作る
# それをaws_ecs_task_definitionでコンテナ(タスク)に紐づける

# Execution Role定義
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "portfolio-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# 標準のExecution Roleポリシーをアタッチ
# AWSリソースにアクセスするならポリシーの定義は必要(Task Roleも)
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role定義。(タスク内アプリ用)
resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# Secrets Managerの読み取り権限
data "aws_iam_policy_document" "ecs_task_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.db_password.arn,
      aws_secretsmanager_secret.django_secret_key.arn
      ]
  }
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name   = "ecs-task-secrets"
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.ecs_task_secrets.json
}

resource "aws_iam_role_policy" "ecs_task_execution_policy" {
  name   = "ecs-task-execution-secrets"
  role   = aws_iam_role.ecs_task_execution_role.id
  policy = data.aws_iam_policy_document.ecs_task_secrets.json
}

# ECS Exec(execute-command)用のポリシーをTask Roleに追加
resource "aws_iam_role_policy" "ecs_exec_policy" {
  name   = "ecs-exec-policy"
  role   = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# ECSタスク定義
resource "aws_ecs_task_definition" "main" {
  family                   = "portfolio-task"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  # ECSがタスクを起動するときに使う権限
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  # コンテナ内アプリがAWSリソースにアクセスするときに使う権限
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "portfolio-container"
    image     = "${aws_ecr_repository.main.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
    }]
    secrets = [
      {
        name      = "DB_PASSWORD"
        valueFrom = aws_secretsmanager_secret.db_password.arn
        },
      {
        name      = "SECRET_KEY"
        valueFrom = aws_secretsmanager_secret.django_secret_key.arn
        }
      ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/portfolio"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
    environment = [
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "DB_PORT", value = tostring(aws_db_instance.main.port) },
      { name = "DB_USER", value = aws_db_instance.main.username },
      { name = "DB_NAME", value = var.db_name },
      { name = "PGSSLMODE", value = "require" }, # RDSがSSL接続を要求するので
      { name = "ALLOWED_HOSTS", value = "*" }
    ]
  }])
}

# ECSセキュリティグループ
resource "aws_security_group" "ecs" {
  name   = "ecs-task-sg"
  vpc_id = aws_vpc.main.id

  # ALBからの通信許可
  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Endpointからの通信許可(Interface Endpoint用)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # ENI作成時にSGで制御
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECSサービス。プライベートサブネットに置く
resource "aws_ecs_service" "main" {
  name            = "portfolio-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true # python manage.py migrate実行のため必要

  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "portfolio-container"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
}

# S3 Gateway Endpoint
# ECRは歴史的にS3をバックエンドストレージとして使っているため、イメージの実データはS3に保存されている。
# ECRのVPC Endpointはメタデータ/認証までは処理できるが、最終的なレイヤダウンロードはS3への通信。
# NAT Gateway無し構成でECRを使うならS3 Gateway Endpointは実質必須。

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

# CloudWatchロググループ
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/portfolio"
  retention_in_days = 7
}

# ECS CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "portfolio-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS CPU utilization > 80% for 5 minutes"
  treat_missing_data  = "missing"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ALB 5XX Error Alarm
# LoadBalancerのdimension値としてARN全体ではなく「ARNのサフィックス部分」を指定する必要がある
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "portfolio-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "ALB 5xx errors exceed 5 in 5 minutes"
  treat_missing_data  = "missing"

  dimensions = {
    LoadBalancer = aws_lb.alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# CloudWatch Alarms for ECS & ALB
# SNS topic for alert notifications
resource "aws_sns_topic" "alerts" {
  name = "portfolio-alerts-topic"
}

# Email subscription (dummy email for portfolio)
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "example@mail.com"
}

# Budgets
resource "aws_budgets_budget" "monthly_budget" {
  name        = "portfolio-budget"
  budget_type = "COST"
  limit_amount = var.budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$${var.project_name}"]
  }

  notification {
    comparison_operator = "GREATER_THAN"
    notification_type   = "ACTUAL"
    threshold           = 80
    threshold_type      = "PERCENTAGE"

    subscriber_email_addresses = ["example@mail.com"]
  }
}

