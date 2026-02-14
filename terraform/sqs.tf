# ============================================================================
# SQS — Job Queue
# ============================================================================

resource "aws_sqs_queue" "job_queue" {
  name = "${local.name_prefix}-job-queue"

  # 5 minutes — enough time for Lambda to call ECS RunTask
  visibility_timeout_seconds = 300

  # Keep messages for 4 days
  message_retention_seconds = 345600

  # Long polling
  receive_wait_time_seconds = 20

  # DLQ configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.job_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${local.name_prefix}-job-queue"
  }
}

# Dead-Letter Queue
resource "aws_sqs_queue" "job_dlq" {
  name = "${local.name_prefix}-job-queue-dlq"

  # Keep DLQ messages for 14 days for debugging
  message_retention_seconds = 1209600

  tags = {
    Name = "${local.name_prefix}-job-queue-dlq"
  }
}
