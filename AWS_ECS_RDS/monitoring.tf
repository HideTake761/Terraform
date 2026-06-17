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
  name         = "portfolio-budget"
  budget_type  = "COST"
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
