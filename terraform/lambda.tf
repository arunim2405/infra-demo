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

data "archive_file" "get_logs" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/get_logs"
  output_path = "${path.module}/.build/get_logs.zip"
}

data "archive_file" "list_jobs" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/list_jobs"
  output_path = "${path.module}/.build/list_jobs.zip"
}

data "archive_file" "register_tenant" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/register_tenant"
  output_path = "${path.module}/.build/register_tenant.zip"
}

data "archive_file" "manage_users" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/manage_users"
  output_path = "${path.module}/.build/manage_users.zip"
}

# ---------------------------------------------------------------------------
# Authorizer Lambda — packaged with pip dependencies
# ---------------------------------------------------------------------------
resource "null_resource" "authorizer_deps" {
  triggers = {
    requirements = filemd5("${path.module}/../lambda/authorizer/requirements.txt")
    handler      = filemd5("${path.module}/../lambda/authorizer/handler.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/.build/authorizer_pkg
      mkdir -p ${path.module}/.build/authorizer_pkg
      pip3 install -r ${path.module}/../lambda/authorizer/requirements.txt \
        -t ${path.module}/.build/authorizer_pkg \
        --platform manylinux2014_x86_64 \
        --only-binary=:all: \
        --python-version 3.12 \
        --implementation cp \
        --quiet
      cp ${path.module}/../lambda/authorizer/handler.py ${path.module}/.build/authorizer_pkg/
    EOT
  }
}

data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = "${path.module}/.build/authorizer_pkg"
  output_path = "${path.module}/.build/authorizer.zip"
  depends_on  = [null_resource.authorizer_deps]
}

# ---------------------------------------------------------------------------
# Authorizer Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "authorizer" {
  function_name    = "${local.name_prefix}-authorizer"
  role             = aws_iam_role.lambda_authorizer.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256

  environment {
    variables = {
      USERS_TABLE   = aws_dynamodb_table.users.name
      USER_POOL_ID  = aws_cognito_user_pool.main.id
      APP_CLIENT_ID = aws_cognito_user_pool_client.frontend.id
    }
  }

  tags = {
    Name = "${local.name_prefix}-authorizer"
  }
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
    }
  }

  tags = {
    Name = "${local.name_prefix}-process-job"
  }
}

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

resource "aws_lambda_permission" "get_status_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# Get Logs Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "get_logs" {
  function_name    = "${local.name_prefix}-get-logs"
  role             = aws_iam_role.lambda_logs.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.get_logs.output_path
  source_code_hash = data.archive_file.get_logs.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE    = aws_dynamodb_table.tasks.name
      LOG_GROUP         = aws_cloudwatch_log_group.ecs_agent.name
      LOG_STREAM_PREFIX = "agent"
      CONTAINER_NAME    = "agent"
    }
  }

  tags = {
    Name = "${local.name_prefix}-get-logs"
  }
}

resource "aws_lambda_permission" "get_logs_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_logs.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# List Jobs Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "list_jobs" {
  function_name    = "${local.name_prefix}-list-jobs"
  role             = aws_iam_role.lambda_list_jobs.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.list_jobs.output_path
  source_code_hash = data.archive_file.list_jobs.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.tasks.name
    }
  }

  tags = {
    Name = "${local.name_prefix}-list-jobs"
  }
}

resource "aws_lambda_permission" "list_jobs_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_jobs.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# Register Tenant Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "register_tenant" {
  function_name    = "${local.name_prefix}-register-tenant"
  role             = aws_iam_role.lambda_register_tenant.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.register_tenant.output_path
  source_code_hash = data.archive_file.register_tenant.output_base64sha256

  environment {
    variables = {
      USERS_TABLE = aws_dynamodb_table.users.name
    }
  }

  tags = {
    Name = "${local.name_prefix}-register-tenant"
  }
}

resource "aws_lambda_permission" "register_tenant_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.register_tenant.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# Manage Users Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "manage_users" {
  function_name    = "${local.name_prefix}-manage-users"
  role             = aws_iam_role.lambda_manage_users.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.manage_users.output_path
  source_code_hash = data.archive_file.manage_users.output_base64sha256

  environment {
    variables = {
      USERS_TABLE  = aws_dynamodb_table.users.name
      USER_POOL_ID = aws_cognito_user_pool.main.id
    }
  }

  tags = {
    Name = "${local.name_prefix}-manage-users"
  }
}

resource "aws_lambda_permission" "manage_users_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.manage_users.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
