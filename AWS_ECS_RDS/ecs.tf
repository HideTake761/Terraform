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
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
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
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Secrets Managerの読み取り権限
data "aws_iam_policy_document" "ecs_task_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
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

# ECS Exec(execute-command)用のポリシー(name:ecs-exec-policy,中身policy= 以下)
# をTask Roleに追加
resource "aws_iam_role_policy" "ecs_exec_policy" {
  name = "ecs-exec-policy"
  role = aws_iam_role.ecs_task_role.id

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
  task_role_arn = aws_iam_role.ecs_task_role.arn

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
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "portfolio-container"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
}
