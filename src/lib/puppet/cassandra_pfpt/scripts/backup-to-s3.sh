#!/bin/bash
# Performs a cluster-aware backup including a full snapshot and any existing
# incremental backup files, then uploads to a simulated S3 bucket.

set -euo pipefail

# --- Configuration ---
S3_BUCKET_NAME="${1:-your-s3-backup-bucket}"
CASSANDRA_DATA_DIR="/var/lib/cassandra/data"
SNAPSHOT_TAG="snapshot_$(date +%Y%m%d%H%M%S)"
HOSTNAME=$(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="${BACKUP_ROOT_DIR}/${HOSTNAME}_${SNAPSHOT_TAG}"
LOG_FILE="/var/log/cassandra/backup.log"
# This script will now also look for and back up incremental backup files.
# The presence of this file indicates that incremental backups were included.
INCREMENTAL_MARKER="incremental_backup_contents.txt"

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
if [ "$(id -u)" -ne 0 ]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

trap cleanup_temp_dir EXIT

log_message "--- Starting Combined Cassandra Backup Process ---"
log_message "S3 Bucket: ${S3_BUCKET_NAME}"
log_message "Snapshot Tag: ${SNAPSHOT_TAG}"

# 1. Create temporary directory structure
mkdir -p "${BACKUP_TEMP_DIR}/snapshot" "${BACKUP_TEMP_DIR}/incremental" || { log_message "ERROR: Failed to create temp backup directories."; exit 1; }

# 2. Take a node-local snapshot
log_message "Taking full snapshot..."
if ! nodetool snapshot -t "${SNAPSHOT_TAG}"; then
  log_message "ERROR: Failed to take Cassandra snapshot. Aborting backup."
  exit 1
fi
log_message "Full snapshot taken successfully."

# 3. Collect snapshot and incremental file paths
# Use find to create lists of files to be archived. This is safer than globbing.
# Collect full snapshot files
find "${CASSANDRA_DATA_DIR}" -type f -path "*/snapshots/${SNAPSHOT_TAG}/*" > "${BACKUP_TEMP_DIR}/snapshot_files.list"

# Collect incremental backup files
find "${CASSANDRA_DATA_DIR}" -type f -path "*/backups/*" > "${BACKUP_TEMP_DIR}/incremental_files.list"

# 4. Archive the files
TARBALL_PATH="${BACKUP_ROOT_DIR}/${HOSTNAME}_${SNAPSHOT_TAG}.tar.gz"
log_message "Archiving data to ${TARBALL_PATH}..."

# Archive the snapshot files. The `-P` flag preserves the full path from root.
if [ -s "${BACKUP_TEMP_DIR}/snapshot_files.list" ]; then
    tar -czf "${TARBALL_PATH}" -P -T "${BACKUP_TEMP_DIR}/snapshot_files.list"
    log_message "Archived full snapshot files."
else
    log_message "WARNING: No snapshot files found. Creating an empty archive for consistency."
    # Create an empty tarball to which we can append other files
    tar -czf "${TARBALL_PATH}" --files-from /dev/null
fi


# Append incremental backup files to the same archive.
if [ -s "${BACKUP_TEMP_DIR}/incremental_files.list" ]; then
    log_message "Archiving incremental backup files..."
    # Use -r (append) to add incremental files to the existing tarball.
    tar -rf "${TARBALL_PATH}" -P -T "${BACKUP_TEMP_DIR}/incremental_files.list"
    touch "${BACKUP_TEMP_DIR}/${INCREMENTAL_MARKER}"
    # Append the marker file to the archive so we know it contains incrementals
    tar -rf "${TARBALL_PATH}" -C "${BACKUP_TEMP_DIR}" "${INCREMENTAL_MARKER}"
    log_message "Appended incremental backup files to the archive."
else
    log_message "No incremental backup files found to archive."
fi

# 5. Archive the schema
log_message "Backing up schema..."
SCHEMA_FILE="${BACKUP_TEMP_DIR}/schema.cql"
# Use timeout to prevent hanging if the node is struggling
timeout 30 cqlsh -e "DESCRIBE SCHEMA;" > "${SCHEMA_FILE}"
if [ $? -ne 0 ]; then
  log_message "WARNING: Failed to dump schema. Backup will continue without it."
else
  # Add schema to the existing tarball
  tar -rf "${TARBALL_PATH}" -C "${BACKUP_TEMP_DIR}" "schema.cql"
  log_message "Schema appended to archive."
fi

# 6. Upload to S3 (mocked)
UPLOAD_PATH="s3://${S3_BUCKET_NAME}/cassandra/${HOSTNAME}/${SNAPSHOT_TAG}.tar.gz"
log_message "Simulating S3 upload to: ${UPLOAD_PATH}"
# In a real environment, the following line would be active:
# if ! aws s3 cp "${TARBALL_PATH}" "${UPLOAD_PATH}"; then
#   log_message "ERROR: Failed to upload backup to S3. Local files will not be cleaned up."
#   exit 1
# fi
log_message "S3 upload simulated successfully."

# 7. Cleanup (only after successful "upload")
log_message "Cleaning up local snapshot and incremental files..."

# Clear the full snapshot we just took
log_message "Clearing snapshot: ${SNAPSHOT_TAG}"
nodetool clearsnapshot -t "${SNAPSHOT_TAG}"

# IMPORTANT: Delete the incremental backup files that were just archived.
# This prevents them from being backed up again and filling the disk.
if [ -s "${BACKUP_TEMP_DIR}/incremental_files.list" ]; then
    log_message "Deleting archived incremental backup files from disk..."
    xargs -a "${BACKUP_TEMP_DIR}/incremental_files.list" rm -f
    log_message "Incremental file cleanup complete."
fi

# Clean up the final tarball from the root backup dir
rm -f "${TARBALL_PATH}"

log_message "--- Cassandra Backup Process Finished Successfully ---"

exit 0