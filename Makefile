# ============================================================================
# Ephemeral Environment Provisioning System — Makefile
# ============================================================================

AWS_REGION     ?= us-east-1
AWS_PROFILE    ?= sg-demo
PROJECT_NAME   ?= infra-demo
ENVIRONMENT    ?= dev
TF_DIR         := terraform
AGENT_DIR      := agent

# Derived values (populated after terraform apply)
ECR_URL        = $(shell cd $(TF_DIR) && terraform output -raw ecr_repository_url 2>/dev/null)

# ============================================================================
# Top-level targets
# ============================================================================

.PHONY: all deploy destroy clean help

## Deploy everything: init terraform, apply infra, build & push Docker image
all: deploy
deploy: tf-init tf-apply docker-push
	@echo ""
	@echo "============================================"
	@echo " ✅  Deployment complete!"
	@echo "============================================"
	@echo " API URL:  $$(cd $(TF_DIR) && terraform output -raw api_gateway_url)"
	@echo " API Key:  $$(cd $(TF_DIR) && terraform output -raw api_key)"
	@echo " ECR Repo: $$(cd $(TF_DIR) && terraform output -raw ecr_repository_url)"
	@echo " S3 Bucket: $$(cd $(TF_DIR) && terraform output -raw s3_bucket_name)"
	@echo "============================================"

## Destroy all AWS resources and clean local build artifacts
destroy: tf-destroy clean
	@echo ""
	@echo "============================================"
	@echo " 🗑️  All resources destroyed and cleaned."
	@echo "============================================"

# ============================================================================
# Terraform
# ============================================================================

.PHONY: tf-init tf-plan tf-apply tf-destroy

tf-init:
	@echo "→ Initializing Terraform..."
	cd $(TF_DIR) && terraform init

tf-plan: tf-init
	@echo "→ Running Terraform plan..."
	cd $(TF_DIR) && terraform plan

tf-apply: tf-init
	@echo "→ Applying Terraform infrastructure..."
	cd $(TF_DIR) && terraform apply -auto-approve

tf-destroy:
	@echo "→ Destroying Terraform infrastructure..."
	cd $(TF_DIR) && terraform destroy -auto-approve

# ============================================================================
# Docker — Build & Push Agent Image
# ============================================================================

.PHONY: docker-build docker-login docker-push

docker-build:
	@echo "→ Building agent Docker image..."
	docker build -t $(PROJECT_NAME)-agent:latest $(AGENT_DIR)

docker-login:
	@echo "→ Logging in to ECR..."
	aws ecr get-login-password --region $(AWS_REGION) --profile $(AWS_PROFILE) | \
		docker login --username AWS --password-stdin $(ECR_URL)

docker-push: docker-build docker-login
	@echo "→ Tagging and pushing image to ECR..."
	docker tag $(PROJECT_NAME)-agent:latest $(ECR_URL):latest
	docker push $(ECR_URL):latest

# ============================================================================
# Clean
# ============================================================================

clean:
	@echo "→ Cleaning build artifacts..."
	rm -rf $(TF_DIR)/.build
	rm -rf $(TF_DIR)/.terraform
	rm -f $(TF_DIR)/.terraform.lock.hcl
	rm -f $(TF_DIR)/terraform.tfstate*

# ============================================================================
# Help
# ============================================================================

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  deploy       Build images, push to ECR, create all AWS infrastructure"
	@echo "  destroy      Destroy all AWS resources and clean local artifacts"
	@echo "  tf-init      Initialize Terraform"
	@echo "  tf-plan      Run Terraform plan (dry-run)"
	@echo "  tf-apply     Apply Terraform infrastructure"
	@echo "  tf-destroy   Destroy Terraform infrastructure"
	@echo "  docker-build Build the agent Docker image locally"
	@echo "  docker-push  Build, login to ECR, and push the image"
	@echo "  clean        Remove local build artifacts and Terraform state"
	@echo "  help         Show this help message"
