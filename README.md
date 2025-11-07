# Apache Spark Streaming with S3 Integration

This project implements an Apache Spark Streaming application that processes data from one S3 bucket and writes the processed results to another S3 bucket.

## Architecture

```
         ┌─────────────────────┐
         │   S3 Source Bucket  │
         │   (Input Data)      │
         └─────────────────────┘
                     │
                     ▼
         ┌─────────────────────┐
         │  Spark Streaming     │
         │  (Processing)        │
         └─────────────────────┘
                     │
                     ▼
         ┌─────────────────────┐
         │  S3 Dest Bucket     │
         │  (Output Data)      │
         └─────────────────────┘
```

## Components

1. **Spark Streaming Application** (`spark_streaming_app.py`)
   - Reads JSON data from S3 source bucket
   - Processes data with transformations
   - Writes processed data to S3 destination bucket
   - Uses checkpointing for fault tolerance

2. **Docker Configuration**
   - Dockerfile for Spark application
   - Build and push scripts for ECR

## Prerequisites

- AWS CLI configured with appropriate credentials
- Docker installed
- Python 3.8+ with pip
- kubectl installed (for EKS deployment)
- eksctl installed (for EKS cluster creation)
- Access to create ECR repositories, S3 buckets, and EKS clusters

## Setup Instructions

### 1. Create S3 Buckets

Create three S3 buckets:
- Source bucket: `spark-streaming-source` (or your preferred name)
- Destination bucket: `spark-streaming-dest` (or your preferred name)
- Checkpoint bucket: `spark-streaming-check` (or your preferred name)

```bash
aws s3 mb s3://spark-streaming-source
aws s3 mb s3://spark-streaming-dest
aws s3 mb s3://spark-streaming-check
```

Or use the Makefile:
```bash
make create-buckets
```

### 2. Build and Push Docker Image

The ECR repository is already configured in `build-and-push.sh`:
- ECR Repository: `879924793392.dkr.ecr.us-east-1.amazonaws.com/securonix-spark-build`

```bash
chmod +x build-and-push.sh
./build-and-push.sh
```

Or use the Makefile:
```bash
make push
```

### 3. Configure AWS Credentials

Set environment variables for AWS access:

```bash
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_REGION=us-east-1
```

### 4. Run Spark Streaming Application

The Spark application can be run using Docker or directly with spark-submit:

**Using Docker:**
```bash
docker run -it \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  -e AWS_REGION=us-east-1 \
  -e SOURCE_BUCKET=s3a://spark-streaming-source/input/ \
  -e DEST_BUCKET=s3a://spark-streaming-dest/output/ \
  -e CHECKPOINT_LOCATION=s3a://spark-streaming-check/checkpoint/ \
  879924793392.dkr.ecr.us-east-1.amazonaws.com/securonix-spark-build:latest
```

**Using spark-submit directly:**
```bash
spark-submit \
  --master local[*] \
  --conf spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem \
  --conf spark.hadoop.fs.s3a.access.key=$AWS_ACCESS_KEY_ID \
  --conf spark.hadoop.fs.s3a.secret.key=$AWS_SECRET_ACCESS_KEY \
  --conf spark.hadoop.fs.s3a.path.style.access=true \
  --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
  spark_streaming_app.py
```

### 4b. Deploy to EKS (Amazon Elastic Kubernetes Service)

**Step 1: Create EKS Cluster**

```bash
chmod +x setup-eks.sh
./setup-eks.sh
```

This will create an EKS cluster with:
- Cluster name: `spark-streaming-demo-cluster` (configurable via `CLUSTER_NAME` env var)
- Region: `us-east-1` (configurable via `AWS_REGION` env var)
- Node type: `t3.medium` (configurable via `NODE_TYPE` env var)
- Initial nodes: 2 (configurable via `NODES` env var)

**Step 2: Update Kubernetes Configuration**

Before deploying, update the Kubernetes manifests with your configuration:

1. **Update ConfigMap** (`kubernetes/configmap.yaml`):
   - Update S3 bucket paths if different from defaults

2. **Update Secret** (`kubernetes/secret.yaml`):
   - Replace `YOUR_AWS_ACCESS_KEY_ID` with your actual AWS access key
   - Replace `YOUR_AWS_SECRET_ACCESS_KEY` with your actual AWS secret key

3. **Update Service Account** (`kubernetes/serviceaccount.yaml`):
   - If using IAM Roles for Service Accounts (IRSA), update the role ARN
   - Otherwise, you can remove the annotation if using secrets

**Step 3: Deploy to EKS**

```bash
chmod +x deploy-to-eks.sh
./deploy-to-eks.sh
```

This script will:
- Configure kubectl to connect to your EKS cluster
- Create the namespace and service account
- Apply ConfigMap and Secret
- Deploy the Spark streaming job

**Step 4: Monitor the Deployment**

```bash
# Check pod status
kubectl get pods -n spark-streaming

# View job logs
kubectl logs -f job/spark-streaming-job -n spark-streaming

# View specific pod logs
kubectl logs -f <pod-name> -n spark-streaming

# Check job status
kubectl get jobs -n spark-streaming

# Describe pod for troubleshooting
kubectl describe pod <pod-name> -n spark-streaming
```

**Update the Job**

Since Kubernetes Jobs have immutable `spec.template`, to update the job:
```bash
# Delete the existing job
kubectl delete job spark-streaming-job -n spark-streaming

# Redeploy
./deploy-to-eks.sh
```

### 5. Upload Data to S3

Data can be uploaded to the source S3 bucket manually or from other sources:

**Manual upload using AWS CLI:**
```bash
aws s3 cp your-data.json s3://spark-streaming-source/input/
```

**Using the provided script:**
```bash
chmod +x manual-upload-trigger.sh
./manual-upload-trigger.sh your-data.json
```

**From other sources:**
- Configure S3 event notifications to trigger data uploads
- Use AWS SDKs or APIs to upload data programmatically
- Set up data pipelines to write to the source bucket

## Monitoring

### Check S3 Output
```bash
aws s3 ls s3://spark-streaming-dest/output/ --recursive
```

### Monitor Application Logs

**If running in Docker:**
```bash
docker logs <container-id>
```

**If running in EKS:**
```bash
# View job logs
kubectl logs -f job/spark-streaming-job -n spark-streaming

# View pod logs
kubectl logs -f <pod-name> -n spark-streaming

# View all pods in namespace
kubectl get pods -n spark-streaming
```

## Configuration

### Environment Variables

- `SOURCE_BUCKET`: S3 path for source data (e.g., `s3a://spark-streaming-source/input/`)
- `DEST_BUCKET`: S3 path for destination (e.g., `s3a://spark-streaming-dest/output/`)
- `CHECKPOINT_LOCATION`: S3 path for checkpointing (e.g., `s3a://spark-streaming-check/checkpoint/`)
- `AWS_ACCESS_KEY_ID`: AWS access key
- `AWS_SECRET_ACCESS_KEY`: AWS secret key
- `AWS_REGION`: AWS region

### Spark Configuration

Key Spark configurations can be set when running spark-submit:
- `spark.executor.memory`: Memory per executor
- `spark.executor.cores`: CPU cores per executor
- `spark.driver.memory`: Driver memory
- `spark.sql.adaptive.enabled=true`: Enable adaptive query execution

## Troubleshooting

### S3 Access Issues
- Verify AWS credentials are correct
- Check IAM permissions for S3 buckets
- Verify bucket names and paths are correct

### Spark Job Failing
- Check application logs for errors
- Verify checkpoint location is accessible
- Check resource limits (CPU/memory)

### Network Issues
- Verify network connectivity to S3
- Check security groups and network policies if running in a VPC

## Scaling

To scale the Spark application:

1. **Increase Resources:**
   - Adjust executor memory and cores in spark-submit configuration
   - Ensure the host has sufficient capacity

2. **Distributed Mode:**
   - Configure Spark to run in cluster mode with multiple nodes
   - Use a Spark cluster manager (Standalone, YARN, or Mesos)

## Cleanup

**If deployed to EKS:**
```bash
# Delete the Spark job
kubectl delete job spark-streaming-job -n spark-streaming

# Delete namespace (this will delete all resources in the namespace)
kubectl delete namespace spark-streaming

# Delete EKS cluster (optional, if you want to remove the entire cluster)
eksctl delete cluster --name spark-streaming-demo-cluster --region us-east-1
```

**Delete S3 buckets:**
```bash
# Delete S3 buckets (be careful!)
aws s3 rm s3://spark-streaming-source --recursive
aws s3 rb s3://spark-streaming-source
aws s3 rm s3://spark-streaming-dest --recursive
aws s3 rb s3://spark-streaming-dest
aws s3 rm s3://spark-streaming-check --recursive
aws s3 rb s3://spark-streaming-check
```

Or use the Makefile:
```bash
make clean-all
```

## Security Best Practices

1. **Use IAM roles** instead of hardcoded credentials when possible
2. **Enable encryption** for S3 buckets
3. **Use VPC endpoints** for S3 access when running in AWS
4. **Implement least privilege** IAM policies
5. **Enable logging** and monitoring with CloudWatch
6. **Use secrets management** (AWS Secrets Manager, etc.)

## License

MIT License
