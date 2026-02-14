# ============================================================================
# Proxy — Squid Forward Proxy on ECS Fargate
# ============================================================================
# Simulates IP rotation by stripping identifying headers.
# Agent tasks route through this proxy via the PROXY_URL env var.
# ============================================================================

# ---------------------------------------------------------------------------
# Squid Proxy Task Definition
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "proxy" {
  family                   = "${local.name_prefix}-proxy"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name      = "squid"
      image     = "ubuntu/squid:latest"
      essential = true
      cpu       = 256
      memory    = 512

      portMappings = [
        {
          containerPort = 3128
          hostPort      = 3128
          protocol      = "tcp"
        }
      ]

      # Inline squid configuration via entrypoint override
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOT
        cat > /etc/squid/squid.conf << 'EOF'
        # Squid proxy configuration for IP rotation simulation
        http_port 3128

        # Access control — allow traffic from VPC CIDR
        acl localnet src 10.0.0.0/16
        http_access allow localnet
        http_access deny all

        # Strip identifying headers for anonymity
        request_header_access Via deny all
        request_header_access X-Forwarded-For deny all
        request_header_access Cache-Control deny all

        # Disable caching
        cache deny all

        # Forwarded-for off
        forwarded_for delete

        # Logging
        access_log stdio:/dev/null
        cache_log stdio:/dev/null

        # DNS
        dns_nameservers 8.8.8.8 8.8.4.4

        # Timeouts
        connect_timeout 30 seconds
        read_timeout 300 seconds
        request_timeout 300 seconds
        EOF
        exec squid -f /etc/squid/squid.conf -N
        EOT
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.proxy.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "proxy"
        }
      }

      # healthCheck = {
      #   command     = ["sh", "-c", "squidclient -h localhost mgr:info || exit 1"]
      #   interval    = 30
      #   timeout     = 5
      #   retries     = 3
      #   startPeriod = 30
      # }
    }
  ])

  tags = {
    Name = "${local.name_prefix}-proxy"
  }
}

# ---------------------------------------------------------------------------
# Proxy ECS Service
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "proxy" {
  name            = "${local.name_prefix}-proxy"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.proxy.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.proxy.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.proxy.arn
    container_name   = "squid"
    container_port   = 3128
  }

  depends_on = [aws_lb_listener.proxy]

  tags = {
    Name = "${local.name_prefix}-proxy-service"
  }
}

# ---------------------------------------------------------------------------
# Internal NLB for Proxy (so agents can reach it by DNS name)
# ---------------------------------------------------------------------------
resource "aws_lb" "proxy" {
  name               = "${local.name_prefix}-proxy-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id

  tags = {
    Name = "${local.name_prefix}-proxy-nlb"
  }
}

resource "aws_lb_target_group" "proxy" {
  name        = "${local.name_prefix}-proxy-tg"
  port        = 3128
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = 3128
  }

  tags = {
    Name = "${local.name_prefix}-proxy-tg"
  }
}

resource "aws_lb_listener" "proxy" {
  load_balancer_arn = aws_lb.proxy.arn
  port              = 3128
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy.arn
  }

  tags = {
    Name = "${local.name_prefix}-proxy-listener"
  }
}
