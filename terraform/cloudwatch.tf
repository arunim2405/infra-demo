# ============================================================================
# CloudWatch — Log Groups & Alarms
# ============================================================================

# ---------------------------------------------------------------------------
# Log Groups
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs_agent" {
  name              = "/ecs/${local.name_prefix}-agent"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-ecs-agent-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda_submit" {
  name              = "/aws/lambda/${local.name_prefix}-submit-job"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-submit-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda_process" {
  name              = "/aws/lambda/${local.name_prefix}-process-job"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-process-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda_status" {
  name              = "/aws/lambda/${local.name_prefix}-get-status"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-status-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-get-logs"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-get-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda_authorizer" {
  name              = "/aws/lambda/${local.name_prefix}-authorizer"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-authorizer-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda_list_jobs" {
  name              = "/aws/lambda/${local.name_prefix}-list-jobs"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-list-jobs-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda_register_tenant" {
  name              = "/aws/lambda/${local.name_prefix}-register-tenant"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-register-tenant-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda_manage_users" {
  name              = "/aws/lambda/${local.name_prefix}-manage-users"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-manage-users-logs"
  }
}


# ---------------------------------------------------------------------------
# Alarms — SQS DLQ messages (jobs failing repeatedly)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${local.name_prefix}-dlq-messages"
  alarm_description   = "Alert when jobs are landing in the dead-letter queue"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.job_dlq.name
  }

  tags = {
    Name = "${local.name_prefix}-dlq-alarm"
  }
}
