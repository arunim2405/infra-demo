# ============================================================================
# Outputs
# ============================================================================

output "api_gateway_url" {
  description = "API Gateway invoke URL"
  value       = aws_api_gateway_stage.v1.invoke_url
}

output "api_key" {
  description = "API key for authentication"
  value       = aws_api_gateway_api_key.main.value
  sensitive   = true
}

output "ecr_repository_url" {
  description = "ECR repository URL for the agent image"
  value       = aws_ecr_repository.agent.repository_url
}

output "s3_bucket_name" {
  description = "S3 bucket for task outputs"
  value       = aws_s3_bucket.outputs.id
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.tasks.name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = aws_sqs_queue.job_queue.url
}
