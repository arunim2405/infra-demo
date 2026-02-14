# ============================================================================
# SSM Parameter Store — Secure Credentials
# ============================================================================

resource "aws_ssm_parameter" "proxy_credentials" {
  name        = "/${var.project_name}/proxy/credentials"
  description = "Proxy authentication credentials"
  type        = "SecureString"
  value       = "placeholder-change-me"

  tags = {
    Name = "${local.name_prefix}-proxy-credentials"
  }

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "agent_api_key" {
  name        = "/${var.project_name}/agent/api-key"
  description = "Agent API key for external services"
  type        = "SecureString"
  value       = "placeholder-change-me"

  tags = {
    Name = "${local.name_prefix}-agent-api-key"
  }

  lifecycle {
    ignore_changes = [value]
  }
}
