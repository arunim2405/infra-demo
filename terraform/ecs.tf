# ============================================================================
# ECS — Cluster & Task Definition
# ============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

# ---------------------------------------------------------------------------
# Agent Task Definition
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "agent" {
  family                   = "${local.name_prefix}-agent"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.agent_cpu
  memory                   = var.agent_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "agent"
      image     = "${aws_ecr_repository.agent.repository_url}:latest"
      essential = true
      cpu       = var.agent_cpu
      memory    = var.agent_memory

      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "S3_BUCKET"
          value = aws_s3_bucket.outputs.id
        },
        {
          name  = "DYNAMODB_TABLE"
          value = aws_dynamodb_table.tasks.name
        },
        {
          name  = "AGENT_TIMEOUT_SECONDS"
          value = "1500"
        }
      ]

      # These will be overridden per-task by Lambda
      # TASK_ID, SEARCH_QUERY, PROXY_URL are injected via containerOverrides

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_agent.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "agent"
        }
      }

      stopTimeout = 30

      healthCheck = {
        command     = ["CMD-SHELL", "test -f /tmp/heartbeat || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = {
    Name = "${local.name_prefix}-agent"
  }
}
