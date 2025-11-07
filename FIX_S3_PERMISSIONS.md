# Fixing S3 403 Forbidden Error

## Problem
The Spark streaming application is getting a `403 Forbidden` error when trying to access S3 buckets. This indicates a permissions issue with AWS credentials or IAM roles.

## Root Cause
The application is configured to use AWS access keys from a Kubernetes secret, but:
1. The credentials may be invalid, expired, or lack proper permissions
2. The ServiceAccount has an IRSA annotation but the app wasn't using IRSA properly
3. The IAM role attached to the ServiceAccount may not have S3 permissions

## Solution Options

### Option 1: Use IRSA (Recommended - More Secure)

IRSA (IAM Roles for Service Accounts) is the recommended approach for EKS. It uses temporary credentials and doesn't require storing access keys in secrets.

#### Step 1: Set up IRSA with S3 permissions

Run the setup script:
```bash
./setup-irsa-s3-permissions.sh
```

This script will:
- Create an IAM role with S3 permissions for the Spark streaming buckets
- Attach the role to your service account
- Configure the necessary trust policies

#### Step 2: Update Service Account (if using new role)

If you created a new role, update `kubernetes/serviceaccount.yaml`:
```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::897708493501:role/spark-streaming-s3-role
```

#### Step 3: Rebuild and redeploy

```bash
# Rebuild Docker image with updated code
make push

# Delete existing jobs to force recreation
kubectl delete job spark-streaming-job -n spark-streaming

# Redeploy
kubectl apply -f kubernetes/spark-job.yaml
```

### Option 2: Fix Access Keys (Quick Fix)

If you prefer to use access keys, ensure they have the correct permissions:

#### Step 1: Verify bucket exists and is accessible
```bash
aws s3 ls s3://spark-streaming-source/
aws s3 ls s3://spark-streaming-dest/
aws s3 ls s3://spark-streaming-check/
```

#### Step 2: Check IAM permissions for your AWS user/role

The credentials need these S3 permissions:
- `s3:GetObject` - Read from source bucket
- `s3:PutObject` - Write to destination bucket
- `s3:ListBucket` - List bucket contents
- `s3:DeleteObject` - Delete checkpoint files
- `s3:GetBucketLocation` - Get bucket region

#### Step 3: Update secret with valid credentials
```bash
kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=your-valid-access-key \
  --from-literal=AWS_SECRET_ACCESS_KEY=your-valid-secret-key \
  -n spark-streaming \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Note:** The current credentials in the secret appear to be temporary (start with "ASIA") and may have expired.

### Option 3: Add S3 Permissions to Existing Role

If you want to keep using `spark-streaming-ecr-role`, add S3 permissions:

```bash
# Attach the S3 policy to existing role
aws iam put-role-policy \
  --role-name spark-streaming-ecr-role \
  --policy-name SparkStreamingS3Policy \
  --policy-document file://kubernetes/spark-streaming-s3-policy.json
```

## Verification

After applying the fix, verify S3 access:

```bash
# Test from a pod using the service account
kubectl run -it --rm test-s3-access \
  --image=amazon/aws-cli \
  --restart=Never \
  --serviceaccount=spark-streaming-sa \
  -n spark-streaming \
  -- aws s3 ls s3://spark-streaming-source/
```

## What Changed

1. **Spark Application** (`spark_streaming_app.py`):
   - Now supports IRSA as the primary authentication method
   - Falls back to access keys if IRSA is not available
   - Uses `DefaultAWSCredentialsProviderChain` which automatically picks the right provider

2. **Spark Job Config** (`kubernetes/spark-job.yaml`):
   - Removed hardcoded access key configuration
   - Now uses `DefaultAWSCredentialsProviderChain` which will use IRSA if available

3. **New Files**:
   - `kubernetes/spark-streaming-s3-policy.json` - IAM policy for S3 access
   - `setup-irsa-s3-permissions.sh` - Script to set up IRSA with S3 permissions

## Troubleshooting

### Check current service account configuration
```bash
kubectl get serviceaccount spark-streaming-sa -n spark-streaming -o yaml
```

### Check IAM role permissions
```bash
aws iam list-role-policies --role-name spark-streaming-s3-role
aws iam get-role-policy --role-name spark-streaming-s3-role --policy-name SparkStreamingS3Policy
```

### Check if buckets exist
```bash
aws s3 ls | grep spark-streaming
```

### View Spark job logs
```bash
kubectl logs -f job/spark-streaming-job -n spark-streaming
```

