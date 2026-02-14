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
