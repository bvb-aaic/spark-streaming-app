#!/bin/bash
# Setup script for EKS cluster and Spark deployment

set -e

CLUSTER_NAME=${CLUSTER_NAME:-spark-streaming-demo-cluster}
REGION=${AWS_REGION:-us-east-1}
# For OOM simulation: smaller nodes (t3.medium) work better for cluster-level OOM testing
# For production: use larger nodes (m5.xlarge or m5.2xlarge)
NODE_TYPE=${NODE_TYPE:-t3.medium}
NODES=${NODES:-2}
NODES_MIN=${NODES_MIN:-2}
NODES_MAX=${NODES_MAX:-3}

echo "=========================================="
echo "Setting up EKS cluster for Spark Streaming"
echo "=========================================="
echo "Cluster Name: ${CLUSTER_NAME}"
echo "Region: ${REGION}"
echo "Node Type: ${NODE_TYPE}"
echo "Nodes: ${NODES} (min: ${NODES_MIN}, max: ${NODES_MAX})"
echo "=========================================="

# Check if eksctl is installed
if ! command -v eksctl &> /dev/null; then
    echo "Error: eksctl is not installed."
    echo "Install it from: https://github.com/weaveworks/eksctl"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed."
    echo "Install it from: https://aws.amazon.com/cli/"
    exit 1
fi



# Check if cluster exists
if eksctl get cluster --name ${CLUSTER_NAME} --region ${REGION} &> /dev/null; then
    echo "Cluster ${CLUSTER_NAME} already exists"
    echo "Updating kubeconfig..."
    aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}
else
    echo "Creating EKS cluster..."
    eksctl create cluster \
        --name ${CLUSTER_NAME} \
        --region ${REGION} \
        --node-type ${NODE_TYPE} \
        --nodes ${NODES} \
        --nodes-min ${NODES_MIN} \
        --nodes-max ${NODES_MAX} \
        --managed \
        --with-oidc \
        --ssh-access=false \
        --full-ecr-access
fi

echo ""
echo "=========================================="
echo "Cluster setup complete!"
echo "=========================================="
echo ""
echo "To deploy the Spark application, run:"
echo "  ./deploy-to-eks.sh"
echo ""
echo "To check cluster status:"
echo "  kubectl get nodes"
echo ""

