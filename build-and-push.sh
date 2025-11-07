#!/bin/bash
# Build and push Docker image to ECR

set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-879924793392}
ECR_REPO_NAME=${ECR_REPO_NAME:-securonix-spark-build}
IMAGE_TAG=${IMAGE_TAG:-latest}

# ECR repository URL
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

echo "Building Docker image for linux/amd64 platform..."
# Build for linux/amd64 to ensure compatibility with EKS nodes
docker build --platform linux/amd64 -t ${ECR_REPO_NAME}:${IMAGE_TAG} .

echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

echo "Checking if ECR repository exists..."
if ! aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} --region ${AWS_REGION} &> /dev/null; then
    echo "Creating ECR repository..."
    aws ecr create-repository --repository-name ${ECR_REPO_NAME} --region ${AWS_REGION}
fi

echo "Tagging image..."
docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}

echo "Pushing image to ECR..."
docker push ${ECR_REPO}:${IMAGE_TAG}

echo "Image pushed successfully: ${ECR_REPO}:${IMAGE_TAG}"

