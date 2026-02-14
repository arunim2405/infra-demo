# ============================================================================
# Main — Data Sources & Locals
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
}
