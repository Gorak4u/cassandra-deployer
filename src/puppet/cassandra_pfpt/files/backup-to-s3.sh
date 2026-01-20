#!/bin/bash
# Performs a snapshot and mocks S3 upload.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- Configuration ---
BUCKET_NAME="your-s3-backup-bucket"
CASSANDRA_DATA_DIR="/var/lib/cassandra/data" # Ensure this is correct
CASSANDRA_COMMITLOG_DIR="/var/lib/cassandra/commitlog" # Optional, usually not backed up with data
SNAPSHOT_TAG="backup_$(date +%Y%m%d%H%M%S)"
HOSTNAME=$(hostname -s)
BACKUP_TEMP_DIR="/tmp/cassandra_backup_$SNAPSHOT_TAG"

# --- Functions ---
cleanup_temp() {
  log_message "Cleaning up temporary directory: $BACKUP_TEMP_DIR"
  rm -rf "$BACKUP_TEMP_DIR"
}

# --- Main Logic ---
log_message "Starting Cassandra backup to S3 process..."

# 1. Take a snapshot
log_message "Taking Cassandra snapshot with tag: $SNAPSHOT_TAG..."
nodetool snapshot -t "$SNAPSHOT_TAG"
if [ $? -ne 0 ]; then
  log_message "ERROR: Failed to take Cassandra snapshot."
  exit 1
fi
log_message "Snapshot taken successfully."

# Find snapshot directory. This path might vary.
# Example: /var/lib/cassandra/data/keyspace/table/snapshots/TAG
SNAPSHOT_ROOT_DIR="${CASSANDRA_DATA_DIR}"

# Prepare temporary directory for tarball
mkdir -p "$BACKUP_TEMP_DIR" || { log_message "ERROR: Failed to create temp backup directory."; exit 1; }

log_message "Creating tar.gz archive of snapshot data from $SNAPSHOT_ROOT_DIR to $BACKUP_TEMP_DIR/${HOSTNAME}_cassandra_snapshot_${SNAPSHOT_TAG}.tar.gz ..."
# Find all snapshot directories for the current tag and tar them
find "$SNAPSHOT_ROOT_DIR" -type d -name "$SNAPSHOT_TAG" -exec tar -czvf "${BACKUP_TEMP_DIR}/${HOSTNAME}_cassandra_snapshot_${SNAPSHOT_TAG}.tar.gz" -C {} . \; 
if [ $? -ne 0 ]; then
  log_message "ERROR: Failed to create tar.gz archive of snapshot data."
  cleanup_temp
  exit 1
fi
log_message "Snapshot data archived successfully."

# 3. Upload to S3 (mocked command)
UPLOAD_PATH="s3://${BUCKET_NAME}/cassandra/${HOSTNAME}/${SNAPSHOT_TAG}/${HOSTNAME}_cassandra_snapshot_${SNAPSHOT_TAG}.tar.gz"
log_message "Mocking S3 upload command:"
echo "aws s3 cp ${BACKUP_TEMP_DIR}/${HOSTNAME}_cassandra_snapshot_${SNAPSHOT_TAG}.tar.gz $UPLOAD_PATH"
# In a real scenario, you'd run:
# aws s3 cp "${BACKUP_TEMP_DIR}/${HOSTNAME}_cassandra_snapshot_${SNAPSHOT_TAG}.tar.gz" "$UPLOAD_PATH"
# if [ $? -ne 0 ]; then
#   log_message "ERROR: Failed to upload backup to S3."
#   cleanup_temp
#   exit 1
# # fi
log_message "S3 upload mocked successfully. In a real scenario, this would be uploaded."

# 4. Clear snapshots (optional, do AFTER successful upload)
# log_message "Clearing snapshots with tag: $SNAPSHOT_TAG..."
# nodetool clearsnapshot -t "$SNAPSHOT_TAG"
# if [ $? -ne 0 ]; then
# #   log_message "WARNING: Failed to clear snapshot $SNAPSHOT_TAG."
# fi

cleanup_temp
log_message "Cassandra backup to S3 process completed."
exit 0