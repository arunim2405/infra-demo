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
Client → API Gateway → Lambda (Status/Logs) → DynamoDB + S3 + CloudWatch
```

### Why This Architecture?

**Terraform (Infrastructure as Code)**
All infrastructure is defined declaratively in Terraform. This enables one-shot deployments — a single `make deploy` stands up the entire stack (VPC, ECS cluster, Lambdas, API Gateway, queues, storage, IAM). It also makes teardown equally trivial and ensures environments are reproducible across regions or accounts.

**ECS (Managed Container Orchestration)**
ECS handles the lifecycle of agent containers — scheduling, health checks, log routing, and teardown. It removes the operational burden of managing a scheduler or monitoring container state manually. ECS integrates natively with IAM, CloudWatch, and VPC networking, which simplifies security and observability.

**Docker (Containerization)**
The agent runs inside a Docker container built on top of the official Playwright image. This guarantees a consistent runtime environment (browser binaries, Python dependencies, OS libraries) regardless of where the image is built or deployed. The `Dockerfile` pins specific versions to prevent drift.

**Fargate (Serverless Containers)**
Fargate was chosen for several critical reasons:
- **Scalability** — Fargate provisions compute on demand. There are no EC2 instances to pre-warm or manage; each job gets its own isolated compute allocation.
- **Automatic teardown** — When the agent process exits, the Fargate task stops and is cleaned up automatically. There is no lingering infrastructure between job runs.
- **Cost optimisation** — Billing is per-second. You pay only for the CPU/memory consumed during execution, not for idle capacity.
- **Full isolation** — Each task gets its own filesystem, memory, and network interface. Job A cannot read Job B's files, memory, or network traffic. This is inherent to Fargate's VM-level isolation model.

> **Trade-off: cold start latency.**
> Fargate tasks take ~30–60 seconds to provision (image pull + ENI attachment + container startup). For the current workload this is acceptable, but for latency-sensitive use cases, **EKS with Kata Containers** would be a more optimised solution — Kata runs each container in a lightweight VM using pre-warmed node pools, reducing cold starts to seconds while preserving the same isolation guarantees.

**Lambda (Serverless Compute)**
The three orchestration functions (submit, process, get-status) and the logs function run on Lambda. They execute for milliseconds to seconds and are invoked infrequently relative to the agent, making Lambda the most cost-efficient option — there is zero cost when no jobs are being submitted.

**SQS (Decoupled Queuing)**
SQS decouples job submission from provisioning. This absorbs traffic spikes, enables retries (max 3 attempts with a dead-letter queue), and ensures no jobs are lost if the process Lambda or ECS encounters transient failures.

### Component Summary

| Component | Purpose |
|-----------|---------|
| **API Gateway** | REST API with rate limiting (10 req/s) and API key auth |
| **Lambda Submit** | Validates input, writes DynamoDB, queues job in SQS |
| **Lambda Process** | SQS-triggered, provisions ECS Fargate task |
| **Lambda Status** | Returns task metadata + pre-signed S3 URLs for outputs |
| **Lambda Logs** | Fetches CloudWatch runtime logs for a task using the ECS task ID |
| **ECS Fargate** | Runs isolated Playwright containers per job |
| **DynamoDB** | Task metadata with TTL and tenant GSI |
| **SQS** | Job queue with DLQ (max 3 retries) |
| **S3** | Screenshots, logs, errors — 30-day lifecycle |
| **SSM** | Secure credential storage |
| **CloudWatch** | Centralised logging, DLQ alarm |
| **VPC** | Private subnets, NAT gateway, metadata endpoint blocked |

---

## Prerequisites

- [Terraform](https://terraform.io) >= 1.5
- [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials
- [Docker](https://docker.com) for building the agent image
- GNU Make

---

## How to Run

### `make deploy` — Build & Deploy Everything

This is the primary command. It runs the full deployment pipeline in order:

1. `terraform init` + `terraform apply` — provisions all AWS resources (VPC, ECS, Lambdas, API Gateway, SQS, DynamoDB, S3, IAM, CloudWatch)
2. `docker build` — builds the agent Docker image locally
3. `docker push` — authenticates with ECR and pushes the image

```bash
make deploy
```

On completion, the output displays:
- **API URL** — the base URL for all endpoints
- **API Key** — the key required in the `x-api-key` header
- **ECR Repo** — the Docker image registry URL
- **S3 Bucket** — where outputs are stored

### `make destroy` — Tear Down All Resources

Destroys every AWS resource created by Terraform. This is a clean teardown — no resources are left running and no costs accumulate after it completes.

```bash
make destroy
```

---

## API Endpoints

All endpoints require the `x-api-key` header. Get the API URL and key from the deploy output, or run:

```bash
API_URL=$(cd terraform && terraform output -raw api_gateway_url)
API_KEY=$(cd terraform && terraform output -raw api_key)
```

### `POST /jobs` — Submit a Job

Creates a new task, stores metadata in DynamoDB, and queues it for execution.

**Request:**
```bash
curl -X POST "$API_URL/jobs" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "terraform ECS fargate tutorial", "tenant_id": "test-tenant"}'
```

**Response:**
```json
{
  "task_id": "a1b2c3d4-...",
  "status": "QUEUED",
  "created_at": "2026-02-15T10:00:00+00:00"
}
```

### `GET /jobs/{task_id}` — Get Job Status & Outputs

Returns the current task status and pre-signed S3 URLs for any outputs (screenshots, logs, errors). The pre-signed URLs are valid for 1 hour.

**Request:**
```bash
curl "$API_URL/jobs/<TASK_ID>" \
  -H "x-api-key: $API_KEY"
```

**Status lifecycle:** `QUEUED` → `PROVISIONING` → `PROVISIONED` → `RUNNING` → `COMPLETED` / `FAILED`

### `GET /jobs/{task_id}/logs` — Get Runtime Logs

Fetches the CloudWatch runtime logs from the ECS container. Use this to debug failures, inspect agent output, or monitor execution in near real-time.

The endpoint uses the `ecs_task_id` stored in DynamoDB to locate the correct CloudWatch log stream, and uses the task's `created_at` timestamp as the starting point for the log search.

**Request:**
```bash
curl "$API_URL/jobs/<TASK_ID>/logs" \
  -H "x-api-key: $API_KEY"
```

**Query parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| `limit` | `200` | Number of log events to return (max 500) |
| `next_token` | — | Pagination token from a previous response |

**Response:**
```json
{
  "task_id": "a1b2c3d4-...",
  "ecs_task_id": "e5f6g7h8-...",
  "log_group": "/ecs/infra-demo-dev-agent",
  "log_stream": "agent/agent/e5f6g7h8-...",
  "status": "RUNNING",
  "events": [
    {
      "timestamp": 1739610000000,
      "time": "2026-02-15T10:00:00+00:00",
      "message": "Starting agent for task a1b2c3d4-..."
    }
  ],
  "count": 42,
  "next_token": "f/..."
}
```

---

## Secrets Management (SSM Parameter Store)

Sensitive credentials (API keys, service tokens) are stored in **AWS Systems Manager Parameter Store** as `SecureString` parameters. They are encrypted at rest with AWS KMS and never appear in Terraform state as plaintext.

### How It Works

1. Terraform creates placeholder parameters under the path `/<project_name>/...`
2. You update the values in the AWS Console or CLI
3. The ECS task execution role has permission to read these parameters at container startup
4. Values are injected as environment variables into the container runtime — they never touch disk

### Creating / Updating a Secret

```bash
# Create or update a secret
aws ssm put-parameter \
  --name "/infra-demo/agent/api-key" \
  --type "SecureString" \
  --value "your-actual-api-key" \
  --overwrite

# Add a new secret (e.g., a third-party service token)
aws ssm put-parameter \
  --name "/infra-demo/agent/my-service-token" \
  --type "SecureString" \
  --value "token-value"
```

### Injecting Secrets into the Agent Container

To inject a new secret into the container, add it to the ECS task definition in `terraform/ecs.tf` as a `secrets` block:

```hcl
secrets = [
  {
    name      = "MY_SERVICE_TOKEN"
    valueFrom = "arn:aws:ssm:<region>:<account>:parameter/infra-demo/agent/my-service-token"
  }
]
```

The value is resolved at runtime by the ECS execution role and injected as the environment variable `MY_SERVICE_TOKEN`. The container code reads it like any other env var — `os.environ["MY_SERVICE_TOKEN"]`.

> **Security note:** The `lifecycle { ignore_changes = [value] }` block in Terraform ensures that once you set the real value via CLI, Terraform will not overwrite it with the placeholder on subsequent applies.

---

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
- **Credential management**: SSM Parameter Store for secrets, injected at runtime — never stored on disk

## Cost Notes

- **NAT Gateway**: ~$0.045/hr + data transfer
- **Per-job**: Fargate task (1 vCPU, 2 GB) ~$0.04/hr, billed per second
- **Lambda**: Effectively free at low volumes (1M free requests/month)
- **Teardown** with `make destroy` when not in use to stop all costs