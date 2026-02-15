# ============================================================================
# API Gateway — REST API with Rate Limiting
# ============================================================================

resource "aws_api_gateway_rest_api" "main" {
  name        = "${local.name_prefix}-api"
  description = "Ephemeral Environment Provisioning API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

# ---------------------------------------------------------------------------
# /jobs resource
# ---------------------------------------------------------------------------
resource "aws_api_gateway_resource" "jobs" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "jobs"
}

# POST /jobs → submit_job Lambda
resource "aws_api_gateway_method" "post_jobs" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.jobs.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "post_jobs" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.jobs.id
  http_method             = aws_api_gateway_method.post_jobs.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.submit_job.invoke_arn
}

# ---------------------------------------------------------------------------
# /jobs/{task_id} resource
# ---------------------------------------------------------------------------
resource "aws_api_gateway_resource" "job_by_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.jobs.id
  path_part   = "{task_id}"
}

# GET /jobs/{task_id} → get_status Lambda
resource "aws_api_gateway_method" "get_job" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.job_by_id.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true

  request_parameters = {
    "method.request.path.task_id" = true
  }
}

resource "aws_api_gateway_integration" "get_job" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.job_by_id.id
  http_method             = aws_api_gateway_method.get_job.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_status.invoke_arn
}

# ---------------------------------------------------------------------------
# /jobs/{task_id}/logs resource
# ---------------------------------------------------------------------------
resource "aws_api_gateway_resource" "job_logs" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.job_by_id.id
  path_part   = "logs"
}

# GET /jobs/{task_id}/logs → get_logs Lambda
resource "aws_api_gateway_method" "get_logs" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.job_logs.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true

  request_parameters = {
    "method.request.path.task_id" = true
  }
}

resource "aws_api_gateway_integration" "get_logs" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.job_logs.id
  http_method             = aws_api_gateway_method.get_logs.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_logs.invoke_arn
}

# ---------------------------------------------------------------------------
# Deployment & Stage
# ---------------------------------------------------------------------------
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.jobs.id,
      aws_api_gateway_resource.job_by_id.id,
      aws_api_gateway_resource.job_logs.id,
      aws_api_gateway_method.post_jobs.id,
      aws_api_gateway_method.get_job.id,
      aws_api_gateway_method.get_logs.id,
      aws_api_gateway_integration.post_jobs.id,
      aws_api_gateway_integration.get_job.id,
      aws_api_gateway_integration.get_logs.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "v1" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "v1"

  tags = {
    Name = "${local.name_prefix}-api-v1"
  }
}

# ---------------------------------------------------------------------------
# Rate Limiting — Usage Plan & API Key
# ---------------------------------------------------------------------------
resource "aws_api_gateway_usage_plan" "main" {
  name        = "${local.name_prefix}-usage-plan"
  description = "Rate-limited usage plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.v1.stage_name
  }

  throttle_settings {
    rate_limit  = var.api_rate_limit
    burst_limit = var.api_burst_limit
  }

  quota_settings {
    limit  = 10000
    period = "DAY"
  }
}

resource "aws_api_gateway_api_key" "main" {
  name    = "${local.name_prefix}-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan_key" "main" {
  key_id        = aws_api_gateway_api_key.main.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.main.id
}

# ---------------------------------------------------------------------------
# Method Settings (logging)
# ---------------------------------------------------------------------------
# resource "aws_api_gateway_method_settings" "all" {
#   rest_api_id = aws_api_gateway_rest_api.main.id
#   stage_name  = aws_api_gateway_stage.v1.stage_name
#   method_path = "*/*"

#   settings {
#     throttling_rate_limit  = var.api_rate_limit
#     throttling_burst_limit = var.api_burst_limit
#     metrics_enabled        = true
#     logging_level          = "INFO"
#   }
# }
