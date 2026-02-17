# ============================================================================
# Ephemeral Environment Provisioning System — Makefile
# ============================================================================

AWS_REGION     ?= us-east-1
AWS_PROFILE    ?= sg-demo
PROJECT_NAME   ?= infra-demo
ENVIRONMENT    ?= dev
TF_DIR         := terraform
AGENT_DIR      := agent
FRONTEND_DIR   := frontend

# Derived values (populated after terraform apply)
ECR_URL        = $(shell cd $(TF_DIR) && terraform output -raw ecr_repository_url 2>/dev/null)
AMPLIFY_APP_ID = $(shell cd $(TF_DIR) && terraform output -raw frontend_url 2>/dev/null | sed 's/.*\.\(d[a-z0-9]*\)\.amplifyapp.*/\1/')

# ============================================================================
# Top-level targets
# ============================================================================

.PHONY: all deploy destroy clean help

## Deploy everything: terraform, Docker image, and frontend
all: deploy
deploy: tf-init tf-apply docker-push frontend-deploy
	@echo ""
	@echo "============================================"
	@echo " ✅  Deployment complete!"
	@echo "============================================"
	@echo " API URL:        $$(cd $(TF_DIR) && terraform output -raw api_gateway_url)"
	@echo " ECR Repo:       $$(cd $(TF_DIR) && terraform output -raw ecr_repository_url)"
	@echo " S3 Bucket:      $$(cd $(TF_DIR) && terraform output -raw s3_bucket_name)"
	@echo " Cognito Pool:   $$(cd $(TF_DIR) && terraform output -raw cognito_user_pool_id)"
	@echo " Cognito Client: $$(cd $(TF_DIR) && terraform output -raw cognito_client_id)"
	@echo " Frontend:       $$(cd $(TF_DIR) && terraform output -raw frontend_url)"
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
	docker build -t $(PROJECT_NAME)-agent:latest $(AGENT_DIR) --platform linux/amd64

docker-login:
	@echo "→ Logging in to ECR..."
	aws ecr get-login-password --region $(AWS_REGION) --profile $(AWS_PROFILE) | \
		docker login --username AWS --password-stdin $(ECR_URL)

docker-push: docker-build docker-login
	@echo "→ Tagging and pushing image to ECR..."
	docker tag $(PROJECT_NAME)-agent:latest $(ECR_URL):latest
	docker push $(ECR_URL):latest

# ============================================================================
# Frontend — Build & Deploy to Amplify
# ============================================================================

.PHONY: frontend-build frontend-deploy

frontend-build:
	@echo "→ Building frontend..."
	cd $(FRONTEND_DIR) && \
		VITE_API_URL=$$(cd ../$(TF_DIR) && terraform output -raw api_gateway_url) \
		VITE_COGNITO_POOL_ID=$$(cd ../$(TF_DIR) && terraform output -raw cognito_user_pool_id) \
		VITE_COGNITO_CLIENT_ID=$$(cd ../$(TF_DIR) && terraform output -raw cognito_client_id) \
		VITE_AWS_REGION=$(AWS_REGION) \
		npm run build

frontend-deploy: frontend-build
	@echo "→ Deploying frontend to Amplify..."
	@AMPLIFY_APP_ID=$$(cd $(TF_DIR) && terraform output -raw frontend_url | grep -o 'd[a-z0-9]*\.amplifyapp' | cut -d. -f1); \
	DEPLOY=$$(aws amplify create-deployment --app-id $$AMPLIFY_APP_ID --branch-name main --region $(AWS_REGION) --profile $(AWS_PROFILE) --query '[jobId,zipUploadUrl]' --output text); \
	JOB_ID=$$(echo $$DEPLOY | cut -d' ' -f1); \
	UPLOAD_URL=$$(echo $$DEPLOY | cut -d' ' -f2); \
	cd $(FRONTEND_DIR)/dist && zip -r /tmp/frontend-deploy.zip .; \
	curl -T /tmp/frontend-deploy.zip "$$UPLOAD_URL"; \
	aws amplify start-deployment --app-id $$AMPLIFY_APP_ID --branch-name main --job-id $$JOB_ID --region $(AWS_REGION) --profile $(AWS_PROFILE); \
	rm -f /tmp/frontend-deploy.zip; \
	echo "→ Frontend deployed!"

# ============================================================================
# Clean
# ============================================================================

clean:
	@echo "→ Cleaning build artifacts..."
	rm -rf $(TF_DIR)/.build
	rm -rf $(TF_DIR)/.terraform
	rm -f $(TF_DIR)/.terraform.lock.hcl
	rm -f $(TF_DIR)/terraform.tfstate*
	rm -rf $(FRONTEND_DIR)/dist
	rm -rf $(FRONTEND_DIR)/node_modules

# ============================================================================
# Help
# ============================================================================

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  deploy           Build and deploy everything (infra + Docker + frontend)"
	@echo "  destroy          Destroy all AWS resources and clean local artifacts"
	@echo "  tf-init          Initialize Terraform"
	@echo "  tf-plan          Run Terraform plan (dry-run)"
	@echo "  tf-apply         Apply Terraform infrastructure"
	@echo "  tf-destroy       Destroy Terraform infrastructure"
	@echo "  docker-build     Build the agent Docker image locally"
	@echo "  docker-push      Build, login to ECR, and push the image"
	@echo "  frontend-build   Build the React frontend"
	@echo "  frontend-deploy  Build and deploy frontend to Amplify"
	@echo "  clean            Remove local build artifacts and Terraform state"
	@echo "  help             Show this help message"
