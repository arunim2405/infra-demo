# ============================================================================
# Variables
# ============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "infra-demo"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "agent_cpu" {
  description = "CPU units for the agent ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "agent_memory" {
  description = "Memory (MiB) for the agent ECS task"
  type        = number
  default     = 2048
}

variable "max_concurrent_jobs" {
  description = "Maximum concurrent jobs allowed"
  type        = number
  default     = 10
}

variable "api_rate_limit" {
  description = "API Gateway rate limit (requests per second)"
  type        = number
  default     = 10
}

variable "api_burst_limit" {
  description = "API Gateway burst limit"
  type        = number
  default     = 20
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
