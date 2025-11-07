#!/bin/bash
# Deploy Spark Streaming application to EKS cluster

set -e

CLUSTER_NAME=${CLUSTER_NAME:-spark-streaming-demo-cluster}
REGION=${AWS_REGION:-us-east-1}
NAMESPACE="spark-streaming"

echo "=========================================="
echo "Deploying Spark Streaming to EKS"
echo "Cluster: ${CLUSTER_NAME}"
echo "Region: ${REGION}"
echo "=========================================="

# Step 1: Configure kubectl
echo ""
echo "Step 1: Configuring kubectl..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}

# Step 2: Verify cluster access
echo ""
echo "Step 2: Verifying cluster access..."
kubectl get nodes

# Step 3: Apply Kubernetes manifests
echo ""
echo "Step 3: Applying Kubernetes manifests..."

# Create namespace
kubectl apply -f kubernetes/namespace.yaml

# Create service account
kubectl apply -f kubernetes/serviceaccount.yaml

# Create configmap
kubectl apply -f kubernetes/configmap.yaml

# Check if secret needs to be updated
if kubectl get secret aws-credentials -n ${NAMESPACE} &> /dev/null; then
    echo "Secret already exists. To update it, run:"
    echo "  kubectl delete secret aws-credentials -n ${NAMESPACE}"
    echo "  kubectl apply -f kubernetes/secret.yaml"
else
    echo "Creating AWS credentials secret..."
    echo "WARNING: Make sure to update kubernetes/secret.yaml with your actual AWS credentials!"
    read -p "Have you updated kubernetes/secret.yaml with your AWS credentials? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl apply -f kubernetes/secret.yaml
    else
        echo "Please update kubernetes/secret.yaml and run this script again."
        exit 1
    fi
fi

# Delete existing job if it exists (Jobs have immutable spec.template)
if kubectl get job spark-streaming-job -n ${NAMESPACE} &> /dev/null; then
    echo "Existing Job found. Deleting it (Jobs have immutable spec.template)..."
    kubectl delete job spark-streaming-job -n ${NAMESPACE} --wait=true --timeout=60s || true
    echo "Waiting a few seconds for cleanup..."
    sleep 5
fi

# Create Spark job
kubectl apply -f kubernetes/spark-job.yaml

# Step 4: Wait for deployment
echo ""
echo "Step 4: Waiting for job to start..."
echo "This may take a few minutes..."
kubectl wait --for=condition=ready pod -l app=spark-streaming -n ${NAMESPACE} --timeout=600s || echo "Timeout waiting for pods, but job may still be starting"

# Step 5: Show status
echo ""
echo "=========================================="
echo "Deployment Status"
echo "=========================================="
kubectl get pods -n ${NAMESPACE}
kubectl get jobs -n ${NAMESPACE}
kubectl get configmap -n ${NAMESPACE}
kubectl get secret -n ${NAMESPACE}

echo ""
echo "=========================================="
echo "Useful Commands"
echo "=========================================="
echo "View pods:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo ""
echo "View job logs:"
echo "  kubectl logs -f job/spark-streaming-job -n ${NAMESPACE}"
echo ""
echo "View pod logs (replace <pod-name> with actual pod name):"
echo "  kubectl logs -f <pod-name> -n ${NAMESPACE}"
echo ""
echo "Describe pod (for troubleshooting):"
echo "  kubectl describe pod <pod-name> -n ${NAMESPACE}"
echo ""
echo "Delete job:"
echo "  kubectl delete job spark-streaming-job -n ${NAMESPACE}"
echo ""
echo "=========================================="
echo "Deployment complete!"
echo "=========================================="

