# ============================================================================
# Lambda Functions
# ============================================================================

# ---------------------------------------------------------------------------
# Package Lambda code as zip archives
# ---------------------------------------------------------------------------
data "archive_file" "submit_job" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/submit_job"
  output_path = "${path.module}/.build/submit_job.zip"
}

data "archive_file" "process_job" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/process_job"
  output_path = "${path.module}/.build/process_job.zip"
}

data "archive_file" "get_status" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/get_status"
  output_path = "${path.module}/.build/get_status.zip"
}

# ---------------------------------------------------------------------------
# Submit Job Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "submit_job" {
  function_name    = "${local.name_prefix}-submit-job"
  role             = aws_iam_role.lambda_submit.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.submit_job.output_path
  source_code_hash = data.archive_file.submit_job.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.tasks.name
      SQS_QUEUE_URL  = aws_sqs_queue.job_queue.url
    }
  }

  tags = {
    Name = "${local.name_prefix}-submit-job"
  }
}

# Permission for API Gateway to invoke
resource "aws_lambda_permission" "submit_job_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.submit_job.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# Process Job Lambda (triggered by SQS)
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "process_job" {
  function_name    = "${local.name_prefix}-process-job"
  role             = aws_iam_role.lambda_process.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.process_job.output_path
  source_code_hash = data.archive_file.process_job.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE  = aws_dynamodb_table.tasks.name
      ECS_CLUSTER     = aws_ecs_cluster.main.arn
      TASK_DEFINITION = aws_ecs_task_definition.agent.arn
      SUBNETS         = join(",", aws_subnet.private[*].id)
      SECURITY_GROUP  = aws_security_group.agent.id
      S3_BUCKET       = aws_s3_bucket.outputs.id
      CONTAINER_NAME  = "agent"
      PROXY_URL       = "http://${aws_lb.proxy.dns_name}:3128"
    }
  }

  tags = {
    Name = "${local.name_prefix}-process-job"
  }
}

# SQS event source mapping
resource "aws_lambda_event_source_mapping" "process_job_sqs" {
  event_source_arn                   = aws_sqs_queue.job_queue.arn
  function_name                      = aws_lambda_function.process_job.arn
  batch_size                         = 1
  maximum_batching_window_in_seconds = 0
  enabled                            = true
}

# ---------------------------------------------------------------------------
# Get Status Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "get_status" {
  function_name    = "${local.name_prefix}-get-status"
  role             = aws_iam_role.lambda_status.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.get_status.output_path
  source_code_hash = data.archive_file.get_status.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.tasks.name
      S3_BUCKET      = aws_s3_bucket.outputs.id
      PRESIGN_EXPIRY = "3600"
    }
  }

  tags = {
    Name = "${local.name_prefix}-get-status"
  }
}

# Permission for API Gateway to invoke
resource "aws_lambda_permission" "get_status_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
