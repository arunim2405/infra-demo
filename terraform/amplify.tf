# ============================================================================
# AWS Amplify — Frontend Hosting
# ============================================================================

resource "aws_amplify_app" "frontend" {
  name = "${local.name_prefix}-frontend"

  # Manual deployment (no Git integration)
  platform = "WEB"

  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        build:
          commands:
            - echo "Pre-built app — no build step needed"
      artifacts:
        baseDirectory: /
        files:
          - '**/*'
  EOT

  custom_rule {
    source = "/<*>"
    status = "404-200"
    target = "/index.html"
  }

  environment_variables = {
    VITE_API_URL           = aws_api_gateway_stage.v1.invoke_url
    VITE_COGNITO_POOL_ID   = aws_cognito_user_pool.main.id
    VITE_COGNITO_CLIENT_ID = aws_cognito_user_pool_client.frontend.id
    VITE_AWS_REGION        = var.aws_region
  }

  tags = {
    Name = "${local.name_prefix}-frontend"
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "main"

  stage = "PRODUCTION"

  tags = {
    Name = "${local.name_prefix}-frontend-main"
  }
}
