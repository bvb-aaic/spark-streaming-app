#!/bin/bash
# Simple script to upload data and trigger processing
# Usage: ./manual-upload-trigger.sh <file-to-upload>

set -e

SOURCE_BUCKET=${SOURCE_BUCKET:-spark-streaming-source}
FILE_PATH=${1:-""}

if [ -z "$FILE_PATH" ]; then
    echo "Usage: $0 <file-to-upload>"
    echo "Example: $0 data.json"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File $FILE_PATH not found"
    exit 1
fi

echo "Uploading $FILE_PATH to s3://$SOURCE_BUCKET/input/..."

# Generate unique filename with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S_%N)
FILENAME=$(basename "$FILE_PATH")
S3_KEY="input/${TIMESTAMP}_${FILENAME}"

# Upload to S3
aws s3 cp "$FILE_PATH" "s3://$SOURCE_BUCKET/$S3_KEY"

echo "✓ File uploaded successfully: s3://$SOURCE_BUCKET/$S3_KEY"
echo ""
echo "Spark Streaming will process this file within 10 seconds (polling interval)."
echo ""
echo "To check output:"
echo "  aws s3 ls s3://spark-streaming-dest/output/ --recursive"

