# Troubleshooting Guide

## Pod in BackOff State

If your pod is in `BackOff` state, it means the container is crashing repeatedly. Here's how to diagnose and fix:

### Step 1: Check Pod Logs

```bash
# Get the pod name
kubectl get pods -n spark-streaming

# View logs (replace <pod-name> with actual pod name)
kubectl logs <pod-name> -n spark-streaming --tail=100

# Or view previous crash logs
kubectl logs <pod-name> -n spark-streaming --previous
```

### Step 2: Check Pod Events

```bash
kubectl describe pod <pod-name> -n spark-streaming
```

Look for:
- **Exit codes**: 0 = success, 1 = error, 137 = OOM killed
- **Reason**: What caused the restart
- **Last State**: What happened before crash

### Step 3: Common Issues and Fixes

#### Issue 1: S3A JARs Missing (ClassNotFoundException)

**Symptoms:**
```
ClassNotFoundException: Class org.apache.hadoop.fs.s3a.S3AFileSystem not found
```

**Fix:**
1. Rebuild the Docker image with updated Dockerfile:
   ```bash
   ./build-and-push.sh
   ```

2. Delete and redeploy:
   ```bash
   kubectl delete job spark-streaming-job -n spark-streaming
   ./deploy-to-eks.sh
   ```

#### Issue 2: Memory Issues

**Symptoms:**
```
OutOfMemoryError: Java heap space
Container killed due to memory pressure
Exit code: 137
```

**Fix:**
- Increase memory limits in `kubernetes/spark-job.yaml`
- Reduce `maxFilesPerTrigger` in Spark app
- Remove memory-intensive operations (window functions)

#### Issue 3: S3 Access Issues

**Symptoms:**
```
AccessDeniedException
InvalidAccessKeyId
```

**Fix:**
1. Verify AWS credentials in `kubernetes/secret.yaml`
2. Check IAM permissions for S3 buckets
3. Verify bucket names in `kubernetes/configmap.yaml`

#### Issue 4: Image Pull Issues

**Symptoms:**
```
ImagePullBackOff
no match for platform in manifest
```

**Fix:**
1. Ensure image is built for `linux/amd64`:
   ```bash
   docker build --platform linux/amd64 -t securonix:latest .
   ```

2. Rebuild and push:
   ```bash
   ./build-and-push.sh
   ```

### Step 4: Verify Image Was Rebuilt

If you updated the Dockerfile, make sure the new image was pushed:

```bash
# Check ECR for latest image
aws ecr describe-images --repository-name securonix --region us-east-1

# Check image digest/timestamp
kubectl describe pod <pod-name> -n spark-streaming | grep Image
```

### Step 5: Force Image Pull

If the pod is using a cached image, force it to pull the latest:

1. Update the job to use a new tag or force pull:
   ```yaml
   imagePullPolicy: Always  # Already set in spark-job.yaml
   ```

2. Delete the job so it recreates:
   ```bash
   kubectl delete job spark-streaming-job -n spark-streaming
   kubectl apply -f kubernetes/spark-job.yaml
   ```

### Step 6: Check Resource Limits

```bash
# Check if pod is being killed due to resource limits
kubectl describe pod <pod-name> -n spark-streaming | grep -A 10 "Limits"
```

### Step 7: Check Service Account and IAM

```bash
# Verify service account exists
kubectl get serviceaccount spark-streaming-sa -n spark-streaming

# Check IAM role annotation
kubectl describe serviceaccount spark-streaming-sa -n spark-streaming
```

## Quick Diagnostic Commands

```bash
# Get all pods with status
kubectl get pods -n spark-streaming -o wide

# View recent events
kubectl get events -n spark-streaming --sort-by='.lastTimestamp'

# Check all resources
kubectl get all -n spark-streaming

# View job status
kubectl describe job spark-streaming-job -n spark-streaming
```

## Debugging Workflow

1. **Get pod name**: `kubectl get pods -n spark-streaming`
2. **Check logs**: `kubectl logs <pod-name> -n spark-streaming`
3. **Check previous crash**: `kubectl logs <pod-name> -n spark-streaming --previous`
4. **Describe pod**: `kubectl describe pod <pod-name> -n spark-streaming`
5. **Check events**: `kubectl get events -n spark-streaming --sort-by='.lastTimestamp'`
6. **Fix based on error** (see common issues above)
7. **Rebuild/redeploy if needed**

## Common Exit Codes

- **0**: Success
- **1**: Application error
- **137**: OOM killed (out of memory)
- **143**: SIGTERM (graceful shutdown)

## Next Steps for Your Current Issue

Since the pod is in BackOff:

1. **Check logs first**:
   ```bash
   kubectl logs spark-streaming-job-bl579 -n spark-streaming --tail=100
   ```

2. **If it's still S3A JAR issue**, ensure you:
   - Rebuilt the image with `./build-and-push.sh`
   - Deleted the old job
   - Redeployed

3. **If it's a different error**, share the log output and we can fix it.

