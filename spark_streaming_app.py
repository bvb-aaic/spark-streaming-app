"""
Apache Spark Streaming Application
Reads data from S3 source bucket, processes it, and writes to S3 destination bucket
"""

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, lit
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, TimestampType
from pyspark.sql.streaming import StreamingQueryListener
from pyspark import SparkContext
import os
import sys
import logging
from datetime import datetime
import psutil
import threading
import time

# Configure logging to both console and file
log_file = os.getenv("LOG_FILE", "/tmp/spark_streaming.log")
# Get the current filename for logging
SCRIPT_NAME = "spark_streaming_app.py"
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(filename)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class CustomStreamingQueryListener(StreamingQueryListener):
    """Custom listener to log streaming query progress and file processing details"""
    
    def onQueryStarted(self, event):
        logger.info(f"QUERY_STARTED | file={SCRIPT_NAME} | query_id={event.id} | run_id={event.runId} | name={event.name}")
    
    def onQueryProgress(self, event):
        """Log progress including file processing details"""
        progress = event.progress
        source_info = []
        if progress.sources:
            for source in progress.sources:
                source_info.append(f"desc={source.description} | start_offset={source.startOffset} | end_offset={source.endOffset} | input_rows={source.numInputRows} | input_rate={source.inputRowsPerSecond:.2f}")
        
        sink_info = f"sink={progress.sink.description}" if progress.sink else "sink=None"
        memory_info = get_memory_info_string()
        logger.info(f"QUERY_PROGRESS | file={SCRIPT_NAME} | batch_id={progress.batchId} | input_rate={progress.inputRowsPerSecond:.2f} rows/sec | process_rate={progress.processedRowsPerSecond:.2f} rows/sec | {sink_info} | {' | '.join(source_info)} | {memory_info}")
    
    def onQueryIdle(self, event):
        """Called when the query is idle (no new data to process)"""
        logger.info(f"QUERY_IDLE | file={SCRIPT_NAME} | query_id={event.id} | {get_memory_info_string()}")
    
    def onQueryTerminated(self, event):
        exception_str = f"exception={event.exception}" if event.exception else "status=normal"
        logger.info(f"QUERY_TERMINATED | file={SCRIPT_NAME} | query_id={event.id} | {exception_str}")

def get_memory_info_string():
    """Get memory usage as a single line string"""
    try:
        process = psutil.Process(os.getpid())
        memory_info = process.memory_info()
        memory_percent = process.memory_percent()
        rss_mb = memory_info.rss / (1024 * 1024)
        vms_mb = memory_info.vms / (1024 * 1024)
        system_memory = psutil.virtual_memory()
        return f"memory_rss={rss_mb:.2f}MB | memory_vms={vms_mb:.2f}MB | memory_pct={memory_percent:.2f}% | sys_total={system_memory.total / (1024**3):.2f}GB | sys_available={system_memory.available / (1024**3):.2f}GB | sys_used_pct={system_memory.percent:.2f}%"
    except Exception as e:
        return f"memory_error={str(e)}"

def log_memory_usage():
    """Log current memory usage"""
    logger.info(f"MEMORY_USAGE | file={SCRIPT_NAME} | {get_memory_info_string()}")

def list_s3_files_with_sizes(spark, s3_path):
    """List all files in S3 path with their sizes (recursively)"""
    try:
        logger.info(f"S3_LISTING_START | file={SCRIPT_NAME} | path={s3_path}")
        
        # Use Hadoop filesystem to list files recursively
        hadoop_conf = spark.sparkContext._jsc.hadoopConfiguration()
        fs = spark.sparkContext._jvm.org.apache.hadoop.fs.FileSystem.get(
            spark.sparkContext._jvm.java.net.URI(s3_path),
            hadoop_conf
        )
        
        # Get the path
        path_obj = spark.sparkContext._jvm.org.apache.hadoop.fs.Path(s3_path)
        
        # List all files recursively
        if fs.exists(path_obj):
            total_size = 0
            file_count = 0
            
            # Recursively list all files
            def list_files_recursive(path):
                nonlocal total_size, file_count
                try:
                    statuses = fs.listStatus(path)
                    for status in statuses:
                        if status.isFile():
                            file_path = status.getPath().toString()
                            file_size = status.getLen()
                            total_size += file_size
                            file_count += 1
                            size_mb = file_size / (1024 * 1024)
                            logger.info(f"S3_FILE | file={SCRIPT_NAME} | file_num={file_count} | path={file_path} | size_mb={size_mb:.2f} | size_bytes={file_size:,}")
                        elif status.isDirectory():
                            # Recursively list files in subdirectory
                            list_files_recursive(status.getPath())
                except Exception as e:
                    logger.warning(f"S3_LISTING_ERROR | file={SCRIPT_NAME} | path={path} | error={str(e)}")
            
            list_files_recursive(path_obj)
            
            if total_size > 0:
                logger.info(f"S3_LISTING_SUMMARY | file={SCRIPT_NAME} | total_files={file_count} | total_size_mb={total_size / (1024**2):.2f} | total_size_gb={total_size / (1024**3):.2f}")
            else:
                logger.info(f"S3_LISTING_SUMMARY | file={SCRIPT_NAME} | total_files=0 | message=No files found")
        else:
            logger.warning(f"S3_PATH_NOT_EXISTS | file={SCRIPT_NAME} | path={s3_path}")
            
    except Exception as e:
        logger.error(f"S3_LISTING_ERROR | file={SCRIPT_NAME} | path={s3_path} | error={str(e)}", exc_info=True)

def monitor_memory_periodically(interval=5):
    """Monitor memory usage periodically in a separate thread"""
    def monitor():
        while True:
            time.sleep(interval)
            log_memory_usage()
    
    thread = threading.Thread(target=monitor, daemon=True)
    thread.start()
    return thread

def create_spark_session():
    """Create and configure Spark session with S3 support"""
    aws_access_key = os.getenv("AWS_ACCESS_KEY_ID")
    aws_secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")
    
    builder = SparkSession.builder \
        .appName("S3StreamingProcessor") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
        .config("spark.hadoop.fs.s3a.path.style.access", "true") \
        .config("spark.sql.streaming.schemaInference", "true")
    
    # Configure S3 endpoint if provided
    s3_endpoint = os.getenv("AWS_S3_ENDPOINT", "")
    if s3_endpoint:
        builder = builder.config("spark.hadoop.fs.s3a.endpoint", s3_endpoint)
    
    # Configure AWS region
    aws_region = os.getenv("AWS_REGION", "us-east-1")
    builder = builder.config("spark.hadoop.fs.s3a.region", aws_region)
    
    # Set credentials provider based on available authentication method
    if aws_access_key and aws_secret_key:
        # Use access keys directly
        logger.info(f"AWS_AUTH | file={SCRIPT_NAME} | method=access_keys | provider=SimpleAWSCredentialsProvider")
        builder = builder \
            .config("spark.hadoop.fs.s3a.access.key", aws_access_key) \
            .config("spark.hadoop.fs.s3a.secret.key", aws_secret_key) \
            .config("spark.hadoop.fs.s3a.aws.credentials.provider",
                    "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
    else:
        # No credentials provided - try instance profile
        logger.info(f"AWS_AUTH | file={SCRIPT_NAME} | method=instance_profile | provider=InstanceProfileCredentialsProvider")
        builder = builder.config("spark.hadoop.fs.s3a.aws.credentials.provider",
                                "com.amazonaws.auth.InstanceProfileCredentialsProvider")
    
    spark = builder.getOrCreate()
    spark.sparkContext.setLogLevel("INFO")
    return spark

def process_streaming_data(spark, source_bucket, dest_bucket, checkpoint_location):
    """
    Process streaming data from source S3 bucket and write to destination bucket
    
    Args:
        spark: SparkSession
        source_bucket: S3 path for source data (e.g., s3a://source-bucket/input/)
        dest_bucket: S3 path for destination (e.g., s3a://dest-bucket/output/)
        checkpoint_location: S3 path for checkpointing (e.g., s3a://checkpoint-bucket/checkpoint/)
    """
    
    # Define schema for the input data
    schema = StructType([
        StructField("id", StringType(), True),
        StructField("name", StringType(), True),
        StructField("value", IntegerType(), True),
        StructField("timestamp", TimestampType(), True)
    ])
    
    logger.info(f"STREAMING_CONFIG | file={SCRIPT_NAME} | source={source_bucket} | dest={dest_bucket} | checkpoint={checkpoint_location} | log_file={log_file}")
    
    # List all files in source bucket with sizes before processing
    list_s3_files_with_sizes(spark, source_bucket)
    
    # Log initial memory usage
    log_memory_usage()
    
    # Read streaming data from S3
    # OOM Configuration: Set maxFilesPerTrigger to very high value to process ALL files at once
    # This will cause OOM when processing large files
    max_files = int(os.getenv("MAX_FILES_PER_TRIGGER", "20000"))  # Very high default to process all files
    logger.info(f"OOM_CONFIG | file={SCRIPT_NAME} | max_files_per_trigger={max_files} | warning=Processing ALL files at once - OOM risk!")
    
    # Add streaming query listener to track progress
    listener = CustomStreamingQueryListener()
    spark.streams.addListener(listener)
    
    # Start memory monitoring thread
    logger.info(f"MEMORY_MONITOR_START | file={SCRIPT_NAME} | interval=5s")
    monitor_memory_periodically(interval=5)
    
    df = spark.readStream \
        .format("json") \
        .option("path", source_bucket) \
        .option("maxFilesPerTrigger", str(max_files)) \
        .schema(schema) \
        .load()
    
    logger.info(f"STREAMING_DF_CREATED | file={SCRIPT_NAME} | status=ready_to_process")
    
    # Process the data - add processing timestamp and perform transformations
    # Note: Multiple transformations without caching can cause memory pressure
    processed_df = df \
        .withColumn("processed_at", current_timestamp()) \
        .withColumn("processing_status", lit("processed")) \
        .withColumn("year", col("timestamp").cast("string").substr(1, 4)) \
        .withColumn("month", col("timestamp").cast("string").substr(6, 2)) \
        .withColumn("day", col("timestamp").cast("string").substr(9, 2))
    
    # Note: Window functions like ROW_NUMBER() are not supported in Structured Streaming
    # For streaming, we use time-based aggregations or simple transformations only
    
    # Write processed data to S3 in append mode
    logger.info(f"STREAMING_QUERY_START | file={SCRIPT_NAME} | mode=append | partition_by=year,month,day | trigger_interval=10s | warning=Processing ALL files at once - OOM risk")
    
    query = processed_df.writeStream \
        .format("json") \
        .outputMode("append") \
        .option("path", dest_bucket) \
        .option("checkpointLocation", checkpoint_location) \
        .partitionBy("year", "month", "day") \
        .trigger(processingTime="10 seconds") \
        .start()
    
    logger.info(f"STREAMING_QUERY_RUNNING | file={SCRIPT_NAME} | query_id={query.id} | status=waiting_for_termination | memory_log_interval=5s")
    
    # Log memory before processing
    log_memory_usage()
    
    # Wait for the streaming query to terminate
    try:
        query.awaitTermination()
    except Exception as e:
        logger.error(f"STREAMING_QUERY_FAILED | file={SCRIPT_NAME} | query_id={query.id} | error={str(e)} | {get_memory_info_string()}", exc_info=True)
        raise

def main():
    """Main entry point"""
    # Get S3 bucket paths from environment variables
    source_bucket = os.getenv("SOURCE_BUCKET", "s3a://spark-stream-source/input/")
    dest_bucket = os.getenv("DEST_BUCKET", "s3a://spark-stream-dest/output/")
    checkpoint_location = os.getenv("CHECKPOINT_LOCATION", "s3a://spark-stream-check/checkpoint/")
    
    logger.info(f"APP_START | file={SCRIPT_NAME} | source={source_bucket} | dest={dest_bucket} | checkpoint={checkpoint_location}")
    
    # Create Spark session
    spark = create_spark_session()
    
    try:
        # Start processing streaming data
        process_streaming_data(spark, source_bucket, dest_bucket, checkpoint_location)
    except Exception as e:
        logger.error(f"APP_ERROR | file={SCRIPT_NAME} | error={str(e)} | {get_memory_info_string()}", exc_info=True)
        raise
    finally:
        spark.stop()
        logger.info(f"SPARK_SESSION_STOPPED | file={SCRIPT_NAME}")

if __name__ == "__main__":
    main()

