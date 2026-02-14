# Ephemeral Environment Provisioning System

A scalable backend that accepts "Computer Use" jobs via API, provisions isolated ECS Fargate containers to execute a browser automation agent, captures outputs to S3, and tears down the environment — all managed with Terraform.

## Architecture

```
Client → API Gateway (rate-limited) → Lambda (Submit) → DynamoDB + SQS
                                                              ↓
                                                     Lambda (Process)
                                                              ↓
                                                     ECS Fargate Task
                                                     (Playwright Agent)
                                                              ↓
                                               S3 (screenshot + logs)
                                                              ↓
Client → API Gateway → Lambda (Status) → DynamoDB + S3 pre-signed URLs
```

### Key Components

| Component | Purpose |
|-----------|---------|
| **API Gateway** | REST API with rate limiting (10 req/s) and API key auth |
| **Lambda Submit** | Validates input, writes DynamoDB, queues job in SQS |
| **Lambda Process** | SQS-triggered, provisions ECS Fargate task |
| **Lambda Status** | Returns task metadata + pre-signed S3 URLs for outputs |
| **ECS Fargate** | Runs isolated Playwright containers per job |
| **Squid Proxy** | Forward proxy that strips identifying headers |
| **DynamoDB** | Task metadata with TTL and tenant GSI |
| **SQS** | Job queue with DLQ (max 3 retries) |
| **S3** | Screenshots, logs, errors — 30-day lifecycle |
| **SSM** | Secure credential storage |
| **CloudWatch** | Centralized logging, DLQ alarm |
| **VPC** | Private subnets, NAT gateway, metadata endpoint blocked |

## Prerequisites

- [Terraform](https://terraform.io) >= 1.5
- [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials
- [Docker](https://docker.com) for building the agent image

## Deployment

### 1. Build & Push Docker Image

```bash
cd agent
docker build -t infra-demo-agent .
```

After Terraform creates the ECR repository:

```bash
# Get ECR URL from Terraform output
ECR_URL=$(cd ../terraform && terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin "$ECR_URL"

# Tag and push
docker tag infra-demo-agent:latest "$ECR_URL:latest"
docker push "$ECR_URL:latest"
```

### 2. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. Test the API

```bash
# Get API URL and key
API_URL=$(terraform output -raw api_gateway_url)
API_KEY=$(terraform output -raw api_key)

# Submit a job
curl -X POST "$API_URL/jobs" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "terraform ECS fargate tutorial", "tenant_id": "test-tenant"}'

# Check job status (use the task_id from the response)
curl "$API_URL/jobs/<TASK_ID>" \
  -H "x-api-key: $API_KEY"
```

### 4. Cleanup

```bash
terraform destroy
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `project_name` | `infra-demo` | Resource naming prefix |
| `environment` | `dev` | Environment tag |
| `agent_cpu` | `1024` | Agent task CPU (1 vCPU) |
| `agent_memory` | `2048` | Agent task memory (2 GB) |
| `api_rate_limit` | `10` | API requests per second |
| `api_burst_limit` | `20` | API burst limit |

## Security

- **Network isolation**: Agent tasks run in private subnets with no inbound access
- **Metadata blocked**: NACLs deny access to `169.254.169.254` from agent subnets
- **Fargate isolation**: Each job runs in its own container with isolated filesystem and memory
- **Least privilege IAM**: Each Lambda and ECS task has its own role scoped to minimum permissions
- **Encrypted storage**: S3 uses AES-256 server-side encryption
- **Credential management**: SSM Parameter Store for secrets (proxy creds, API keys)

## Cost Notes

- **NAT Gateway**: ~$0.045/hr + data transfer
- **Squid Proxy**: Always-on Fargate task (0.25 vCPU, 512 MB) ~$0.01/hr
- **Per-job**: Fargate task (1 vCPU, 2 GB) ~$0.04/hr, billed per second
- **Teardown** with `terraform destroy` when not in use