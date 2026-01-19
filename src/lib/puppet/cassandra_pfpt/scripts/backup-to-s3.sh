#!/bin/bash
# Performs a snapshot and mocks S3 upload.

set -euo pipefail

# --- Configuration ---
# The S3 bucket name is passed as the first argument to the script.
S3_BUCKET_NAME="${1:-your-s3-backup-bucket}" # Default if no arg is provided
CASSANDRA_DATA_DIR="/var/lib/cassandra/data"
SNAPSHOT_TAG="backup_$(date +%Y%m%d%H%M%S)"
HOSTNAME=$(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="${BACKUP_ROOT_DIR}/${SNAPSHOT_TAG}"
LOG_FILE="/var/log/cassandra/backup.log"
SNAPSHOT_CLEANUP_THRESHOLD=3 # Number of recent snapshots to keep

# --- Logging ---
log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# --- Cleanup Functions ---
cleanup_temp_dir() {
  if [ -d "${BACKUP_TEMP_DIR}" ]; then
    log_message "Cleaning up temporary directory: ${BACKUP_TEMP_DIR}"
    rm -rf "${BACKUP_TEMP_DIR}"
  fi
}

# --- Main Logic ---
# Ensure we run as root, as nodetool might be restricted.
if [ "$(id -u)" -ne 0 ]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

# Trap to ensure cleanup happens on script exit or interruption.
trap cleanup_temp_dir EXIT

log_message "--- Starting Cassandra Backup Process ---"
log_message "S3 Bucket: ${S3_BUCKET_NAME}"
log_message "Snapshot Tag: ${SNAPSHOT_TAG}"

# 1. Take a node-local snapshot
log_message "Taking Cassandra snapshot..."
if ! nodetool snapshot -t "${SNAPSHOT_TAG}"; then
  log_message "ERROR: Failed to take Cassandra snapshot."
  exit 1
fi
log_message "Snapshot taken successfully."

# 2. Prepare temporary directory for tarball
mkdir -p "${BACKUP_TEMP_DIR}" || { log_message "ERROR: Failed to create temp backup directory."; exit 1; }

# 3. Archive the snapshot data and schema
TARBALL_PATH="${BACKUP_TEMP_DIR}/${HOSTNAME}_${SNAPSHOT_TAG}.tar.gz"
log_message "Archiving snapshot data to ${TARBALL_PATH}..."

# Find all snapshot directories for the current tag and tar them
# The structure is /path/to/data/<keyspace>/<table>/snapshots/<tag>
SNAPSHOT_DIRS=$(find "${CASSANDRA_DATA_DIR}" -type d -name "${SNAPSHOT_TAG}")

if [ -z "${SNAPSHOT_DIRS}" ]; then
  log_message "WARNING: No snapshot directories found. Nothing to back up."
else
  # Using tar's -T option to read file list from stdin for safety with many files
  echo "${SNAPSHOT_DIRS}" | tar -czvf "${TARBALL_PATH}" --no-recursion -T -
  if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to create tar.gz archive of snapshot data."
    exit 1
  fi
fi

# Also back up the schema for this node
log_message "Backing up schema..."
SCHEMA_FILE="${BACKUP_TEMP_DIR}/schema_${HOSTNAME}.cql"
cqlsh -e "DESCRIBE SCHEMA;" > "${SCHEMA_FILE}"
if [ $? -ne 0 ]; then
  log_message "WARNING: Failed to dump schema. Backup will continue without it."
else
  # Add schema to the existing tarball
  tar -rzvf "${TARBALL_PATH}" -C "${BACKUP_TEMP_DIR}" "schema_${HOSTNAME}.cql"
fi

log_message "Snapshot data and schema archived successfully."

# 4. Upload to S3 (mocked for this environment)
UPLOAD_PATH="s3://${S3_BUCKET_NAME}/cassandra/${HOSTNAME}/${SNAPSHOT_TAG}/${HOSTNAME}_${SNAPSHOT_TAG}.tar.gz"
log_message "Simulating S3 upload to: ${UPLOAD_PATH}"
log_message "Mock command: aws s3 cp ${TARBALL_PATH} ${UPLOAD_PATH}"
# In a real environment, you would uncomment the following lines:
# if ! aws s3 cp "${TARBALL_PATH}" "${UPLOAD_PATH}"; then
#   log_message "ERROR: Failed to upload backup to S3."
#   exit 1
# fi
log_message "S3 upload simulated successfully."

# 5. Clean up local snapshots
log_message "Cleaning up old snapshots, keeping the latest ${SNAPSHOT_CLEANUP_THRESHOLD}..."
# This is a safer way to clean up than just clearing the latest tag.
# It finds all backup snapshots and removes all but the N most recent ones.
find "${CASSANDRA_DATA_DIR}" -type d -name 'snapshots' | while read -r snapshot_dir; do
  cd "${snapshot_dir}" || continue
  # List backup snapshots, sort by time, skip the newest N, and pipe to nodetool to clear
  ls -t backup_* 2>/dev/null | tail -n +$((SNAPSHOT_CLEANUP_THRESHOLD + 1)) | xargs -r nodetool clearsnapshot -t
  cd - >/dev/null
done
log_message "Snapshot cleanup complete."

log_message "--- Cassandra Backup Process Finished Successfully ---"

exit 0
