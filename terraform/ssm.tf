# ============================================================================
# SSM Parameter Store — Secure Credentials
# ============================================================================


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
