#!/bin/bash
set -e

# Kafka Storage Initialization Script for KRaft Mode
# This script prepares the Kafka data directory and formats storage if needed

DATA_DIR="/var/lib/kafka/data"

echo "===== Kafka Storage Initialization ====="

# Remove lost+found directory if it exists (ext4 filesystem artifact)
if [ -d "$DATA_DIR/lost+found" ]; then
  echo "Removing lost+found directory from $DATA_DIR..."
  rm -rf "$DATA_DIR/lost+found"
  echo "✓ Removed lost+found directory"
fi

# Check if metadata already exists (volume already formatted)
if [ -f "$DATA_DIR/meta.properties" ]; then
  echo "✓ Kafka storage already formatted, skipping format step"
  echo "Existing metadata:"
  cat "$DATA_DIR/meta.properties"
else
  echo "Formatting Kafka storage for KRaft mode..."
  echo "Cluster ID: ${CLUSTER_ID}"
  
  kafka-storage format \
    --config /etc/kafka/kafka.properties \
    --cluster-id "${CLUSTER_ID}" \
    --ignore-formatted
  
  echo "✓ Storage format complete!"
fi

echo "===== Initialization Complete ====="
