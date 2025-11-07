# OOM Testing Guide - After Memory Fixes

## Current Configuration Status

After fixing the startup issue, we now have:
- **Container Memory**: 1Gi (1024Mi)
- **Driver Memory**: 512m
- **Memory-intensive settings**: Still enabled

## Can We Still Trigger OOM? **YES!**

### Memory-Intensive Features Still Active

1. **Window Function** (`spark_streaming_app.py`)
   - Processes entire dataset in memory
   - Very memory-intensive for large datasets

2. **Low Parallelism**
   - `spark.sql.shuffle.partitions=1`
   - `spark.default.parallelism=1`
   - Forces all data into single partition (memory intensive)

3. **Adaptive Execution Disabled**
   - `spark.sql.adaptive.enabled=false`
   - Can't optimize memory usage automatically

4. **High Files Per Trigger**
   - Default: 50 files processed at once
   - Can be increased via `MAX_FILES_PER_TRIGGER` env var

## How to Trigger OOM Now

### Method 1: Upload Large Files (Recommended)
Upload large JSON files to trigger OOM:

```bash
# Create a large test file (e.g., 50MB+)
python3 << EOF
import json
data = [{
    'id': f'id_{i}',
    'name': f'name_{i}',
    'value': i,
    'timestamp': '2024-01-01T00:00:00Z'
} for i in range(500000)]  # 500k records
with open('large-file.json', 'w') as f:
    json.dump(data, f)
EOF

# Upload multiple large files
aws s3 cp large-file.json s3://spark-streaming-source/input/file-1.json
aws s3 cp large-file.json s3://spark-streaming-source/input/file-2.json
# Upload 10-20 large files
```

### Method 2: Upload Many Files
Upload many files that collectively exceed memory:

```bash
# Upload 100+ files
for i in {1..100}; do
  aws s3 cp test-file.json s3://spark-streaming-source/input/file-$i.json
done
```

### Method 3: Increase Files Per Trigger
Update the job to process even more files:

```yaml
# In kubernetes/spark-job.yaml, add:
env:
- name: MAX_FILES_PER_TRIGGER
  value: "100"  # Process 100 files at once
```

Then redeploy:
```bash
kubectl delete job spark-streaming-job -n spark-streaming
kubectl apply -f kubernetes/spark-job.yaml
```

### Method 4: Reduce Memory Limits (For Testing)
If you want more aggressive OOM testing, reduce memory:

```yaml
resources:
  limits:
    memory: "768Mi"  # Reduce from 1Gi
  requests:
    memory: "768Mi"
command:
- --driver-memory
- 400m  # Reduce from 512m (but keep above 450MB minimum)
```

**Note**: Don't go below 450MB driver memory or Spark won't start.

## Expected OOM Behavior

With current settings (1Gi container, 512m driver), you can trigger OOM by:

1. **Uploading 10-20 large files** (50MB+ each) simultaneously
2. **Uploading 100+ medium files** (10MB each) at once
3. **Window function processing** will load entire dataset in memory

### Monitoring OOM

```bash
# Watch pod status
watch -n 2 kubectl get pods -n spark-streaming

# Check for OOM
kubectl describe pod <pod-name> -n spark-streaming | grep -i "oom\|memory"

# View logs
kubectl logs -f job/spark-streaming-job -n spark-streaming
```

**OOM Indicators:**
- Pod status: `OOMKilled`
- Exit code: `137`
- Error: `java.lang.OutOfMemoryError: Java heap space`
- Container killed due to memory pressure

## Memory Usage Breakdown

With current settings:
- **Container**: 1Gi total
- **Driver Heap**: 512m
- **JVM Overhead**: ~100-150m
- **OS/System**: ~100m
- **Available for processing**: ~250-300m

The **window function** will try to load entire dataset in memory, which can easily exceed 250-300m with large files.

## Comparison: Before vs After

| Aspect | Before (OOM Setup) | After (Fixed) | OOM Still Possible? |
|--------|-------------------|---------------|---------------------|
| Container Memory | 512Mi | 1Gi | ✅ Yes, with larger files |
| Driver Memory | 256m | 512m | ✅ Yes, with larger files |
| Window Function | ✅ Active | ✅ Active | ✅ Still memory-intensive |
| Low Parallelism | ✅ Active | ✅ Active | ✅ Still forces single partition |
| Files Per Trigger | 50 | 50 (configurable) | ✅ Can increase to 100+ |

## Recommendations

### For OOM Testing:
1. **Keep current settings** (1Gi container, 512m driver)
2. **Upload large files** (50MB+ each, 10-20 files)
3. **Or increase MAX_FILES_PER_TRIGGER** to 100+
4. **Window function** will still cause OOM with large datasets

### For Production:
1. **Increase memory** to 2-4Gi
2. **Enable adaptive execution** (`spark.sql.adaptive.enabled=true`)
3. **Increase parallelism** (`spark.sql.shuffle.partitions=200`)
4. **Remove or optimize window function**
5. **Reduce files per trigger** to 10-20

## Quick OOM Test Script

```bash
#!/bin/bash
# Quick OOM test - uploads multiple large files

SOURCE_BUCKET="spark-streaming-source"

echo "Creating large test files..."
for i in {1..20}; do
  python3 << EOF
import json
data = [{'id': f'id_{j}', 'name': f'name_{j}', 'value': j, 'timestamp': '2024-01-01T00:00:00Z'} for j in range(200000)]
with open(f'large-file-$i.json', 'w') as f:
    json.dump(data, f)
EOF
  echo "Uploading large-file-$i.json..."
  aws s3 cp large-file-$i.json s3://$SOURCE_BUCKET/input/
done

echo "Files uploaded. Monitor pod for OOM:"
echo "kubectl get pods -n spark-streaming -w"
```

## Conclusion

**YES, OOM can still be simulated!** The memory-intensive configurations (window function, low parallelism) are still active. You'll just need to upload larger files or more files to trigger it with the increased memory limits.

