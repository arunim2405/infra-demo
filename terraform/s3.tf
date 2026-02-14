# ============================================================================
# S3 — Task Outputs
# ============================================================================

resource "aws_s3_bucket" "outputs" {
  bucket_prefix = "${local.name_prefix}-outputs-"
  force_destroy = true

  tags = {
    Name = "${local.name_prefix}-outputs"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "outputs" {
  bucket = aws_s3_bucket.outputs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "outputs" {
  bucket = aws_s3_bucket.outputs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle — delete objects after 30 days
resource "aws_s3_bucket_lifecycle_configuration" "outputs" {
  bucket = aws_s3_bucket.outputs.id

  rule {
    id     = "cleanup-old-outputs"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

# Versioning (for safety)
resource "aws_s3_bucket_versioning" "outputs" {
  bucket = aws_s3_bucket.outputs.id

  versioning_configuration {
    status = "Enabled"
  }
}
