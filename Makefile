.PHONY: help build push clean

# Configuration
AWS_REGION ?= us-east-1
AWS_ACCOUNT_ID ?= 879924793392
ECR_REPO_NAME ?= securonix-spark-build
IMAGE_TAG ?= latest
SOURCE_BUCKET ?= spark-streaming-source
DEST_BUCKET ?= spark-streaming-dest
CHECKPOINT_BUCKET ?= spark-streaming-check

ECR_REPO = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(ECR_REPO_NAME)

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install-deps: ## Install Python dependencies
	pip install -r requirements.txt

build: ## Build Docker image for linux/amd64 (EKS compatible)
	docker build --platform linux/amd64 -t $(ECR_REPO_NAME):$(IMAGE_TAG) .

push: build ## Build and push Docker image to ECR
	@echo "Logging in to ECR..."
	@aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	@echo "Creating ECR repository if not exists..."
	@aws ecr describe-repositories --repository-names $(ECR_REPO_NAME) --region $(AWS_REGION) || \
		aws ecr create-repository --repository-name $(ECR_REPO_NAME) --region $(AWS_REGION)
	@echo "Tagging and pushing image..."
	docker tag $(ECR_REPO_NAME):$(IMAGE_TAG) $(ECR_REPO):$(IMAGE_TAG)
	docker push $(ECR_REPO):$(IMAGE_TAG)
	@echo "Image pushed: $(ECR_REPO):$(IMAGE_TAG)"

create-buckets: ## Create S3 buckets
	@echo "Creating S3 buckets..."
	@aws s3 mb s3://$(SOURCE_BUCKET) || true
	@aws s3 mb s3://$(DEST_BUCKET) || true
	@aws s3 mb s3://$(CHECKPOINT_BUCKET) || true
	@echo "Buckets created successfully"

clean: ## Clean up resources
	@echo "Cleanup complete"

clean-all: clean ## Clean up all resources including S3 buckets
	@echo "WARNING: This will delete all S3 buckets and their contents!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		aws s3 rm s3://$(SOURCE_BUCKET) --recursive || true; \
		aws s3 rb s3://$(SOURCE_BUCKET) || true; \
		aws s3 rm s3://$(DEST_BUCKET) --recursive || true; \
		aws s3 rb s3://$(DEST_BUCKET) || true; \
		aws s3 rm s3://$(CHECKPOINT_BUCKET) --recursive || true; \
		aws s3 rb s3://$(CHECKPOINT_BUCKET) || true; \
		echo "All resources cleaned up"; \
	fi

