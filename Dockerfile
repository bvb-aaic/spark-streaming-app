# Dockerfile for Spark Streaming Application
FROM apache/spark:3.5.0-python3

# Set working directory and ensure proper permissions
USER root
RUN mkdir -p /app && chown -R spark:spark /app
WORKDIR /app

# Install required Python packages (as root, available to all users)
RUN pip install --no-cache-dir boto3

# Download and install Hadoop S3A JARs for S3 access
# These are required for Spark to access S3 via s3a:// protocol
RUN apt-get update && apt-get install -y wget stress-ng && \
    wget -q https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar -O /opt/spark/jars/hadoop-aws-3.3.4.jar && \
    wget -q https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.262/aws-java-sdk-bundle-1.12.262.jar -O /opt/spark/jars/aws-java-sdk-bundle-1.12.262.jar && \
    apt-get remove -y wget && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy Spark application
COPY spark_streaming_app.py /app/
COPY requirements.txt /app/

# Install additional requirements if any
RUN pip install --no-cache-dir -r /app/requirements.txt

# Fix ownership and switch to spark user for runtime
RUN chown -R spark:spark /app && \
    chown -R spark:spark /opt/spark/jars
USER spark

# Set environment variables
ENV PYSPARK_PYTHON=python3
ENV PYSPARK_DRIVER_PYTHON=python3

# Set entrypoint
ENTRYPOINT ["/opt/spark/bin/spark-submit"]

# Default command
CMD ["/app/spark_streaming_app.py"]

