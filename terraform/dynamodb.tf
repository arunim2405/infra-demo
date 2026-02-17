# ============================================================================
# DynamoDB — Task Metadata
# ============================================================================

resource "aws_dynamodb_table" "tasks" {
  name         = "${local.name_prefix}-tasks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "task_id"

  attribute {
    name = "task_id"
    type = "S"
  }

  attribute {
    name = "tenant_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  # GSI for per-tenant queries
  global_secondary_index {
    name            = "tenant-index"
    hash_key        = "tenant_id"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  # Auto-cleanup old records
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${local.name_prefix}-tasks"
  }
}

# ============================================================================
# DynamoDB — Users & Tenants
# ============================================================================

resource "aws_dynamodb_table" "users" {
  name         = "${local.name_prefix}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "cognito_id"

  attribute {
    name = "cognito_id"
    type = "S"
  }

  attribute {
    name = "tenant_id"
    type = "S"
  }

  # GSI for listing all users in a tenant
  global_secondary_index {
    name            = "tenant-index"
    hash_key        = "tenant_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${local.name_prefix}-users"
  }
}
