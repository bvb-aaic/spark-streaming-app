# Out of Memory (OOM) Simulation Setup

This document explains how the OOM (Out of Memory) simulation is configured and how to trigger it.

## Current Configuration (OOM-Prone Setup)

### 1. **Kubernetes Memory Limits** (`kubernetes/spark-job.yaml`)
- **Memory Limit**: `512Mi` (very low)
- **Memory Request**: `512Mi`
- **Driver Memory**: `256m` (set in Spark config)

This is intentionally set very low to cause OOM when processing large files.

### 2. **Spark Configuration** (Memory-Intensive Settings)
- **Driver Memory**: `256m` (extremely low)
- **Adaptive Query Execution**: **Disabled** (less efficient memory usage)
- **Shuffle Partitions**: `1` (forces all data into single partition - memory intensive)
- **Default Parallelism**: `1` (no parallelization - processes everything in memory)

### 3. **Spark Application** (`spark_streaming_app.py`)
- **maxFilesPerTrigger**: `50` (processes 50 files at once by default)
- **Window Function**: Added row_number() window function that processes all data in memory
- **No Caching**: Transformations are not cached, causing repeated memory allocation

## How to Trigger OOM

### Method 1: Upload Large Files
Upload large JSON files to the S3 source bucket:
```bash
# Create a large test file (e.g., 100MB)
# Upload multiple large files
aws s3 cp large-file-1.json s3://spark-streaming-source/input/
aws s3 cp large-file-2.json s3://spark-streaming-source/input/
# ... upload more files
```

### Method 2: Increase Files Per Trigger
Set environment variable to process even more files:
```bash
# Update kubernetes/spark-job.yaml to add:
- name: MAX_FILES_PER_TRIGGER
  value: "100"  # Process 100 files at once
```

### Method 3: Upload Many Small Files
Upload many small files that collectively exceed memory:
```bash
# Upload 100+ files
for i in {1..100}; do
  aws s3 cp small-file.json s3://spark-streaming-source/input/file-$i.json
done
```

## Expected OOM Behavior

When OOM occurs, you'll see:

1. **Kubernetes Pod Status**: `OOMKilled` or `CrashLoopBackOff`
2. **Pod Logs**: Error messages like:
   - `java.lang.OutOfMemoryError: Java heap space`
   - `Container killed due to memory pressure`
   - `Exit code 137` (indicates OOM kill)

3. **Check Pod Status**:
```bash
kubectl get pods -n spark-streaming
# Look for: OOMKilled status

kubectl describe pod <pod-name> -n spark-streaming
# Look for: "Last State: Terminated, Reason: OOMKilled"
```

4. **Check Pod Logs**:
```bash
kubectl logs <pod-name> -n spark-streaming
# Look for OutOfMemoryError or memory-related errors
```

## Why OOM Occurs

1. **Low Memory Limits**: 512Mi total memory with only 256m for Spark driver
2. **Single Partition**: All data processed in one partition (no parallelization)
3. **Window Function**: Row number window function loads entire dataset in memory
4. **Multiple Files**: Processing 50+ files simultaneously
5. **No Adaptive Execution**: Can't optimize memory usage automatically

## Solutions to Fix OOM (Production Configuration)

### Option 1: Increase Memory Limits
```yaml
resources:
  limits:
    memory: "4Gi"  # Increase from 512Mi
  requests:
    memory: "2Gi"
```

### Option 2: Increase Spark Driver Memory
```yaml
- --driver-memory
- 2g  # Increase from 256m
```

### Option 3: Enable Adaptive Query Execution
```yaml
- --conf
- spark.sql.adaptive.enabled=true
- --conf
- spark.sql.adaptive.coalescePartitions.enabled=true
```

### Option 4: Increase Parallelism
```yaml
- --conf
- spark.sql.shuffle.partitions=200
- --conf
- spark.default.parallelism=200
```

### Option 5: Reduce Files Per Trigger
```python
max_files = int(os.getenv("MAX_FILES_PER_TRIGGER", "10"))  # Reduce from 50
```

### Option 6: Remove Window Function
Remove the window function from `spark_streaming_app.py` that causes memory pressure.

## Monitoring Memory Usage

### Check Pod Memory Usage
```bash
kubectl top pod -n spark-streaming
```

### Check Resource Requests/Limits
```bash
kubectl describe pod <pod-name> -n spark-streaming | grep -A 5 "Limits"
```

### Check Spark UI (if accessible)
The Spark UI shows memory usage per stage and executor.

## Testing OOM Simulation

1. **Deploy with current OOM-prone configuration**:
```bash
./deploy-to-eks.sh
```

2. **Upload test files**:
```bash
# Create and upload large files
for i in {1..20}; do
  # Create a 10MB JSON file
  python3 -c "import json; data = [{'id': f'id_{j}', 'name': f'name_{j}', 'value': j, 'timestamp': '2024-01-01T00:00:00Z'} for j in range(10000)]; json.dump(data, open(f'large-file-{i}.json', 'w'))"
  aws s3 cp large-file-$i.json s3://spark-streaming-source/input/
done
```

3. **Monitor the pod**:
```bash
watch -n 2 kubectl get pods -n spark-streaming
```

4. **Check for OOM**:
```bash
kubectl describe pod <pod-name> -n spark-streaming | grep -i "oom\|memory\|killed"
```

## Notes

- **Current setup is intentionally configured to cause OOM** for testing purposes
- **For production**, use the "Solutions to Fix OOM" section above
- **Window functions** are particularly memory-intensive with large datasets
- **Streaming mode** with low memory can be challenging - consider batch processing for large files

