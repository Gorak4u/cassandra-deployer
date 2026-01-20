
export const backupScripts = {
      'full-backup-to-s3.sh': `#!/bin/bash
# Performs a full snapshot backup and uploads it to a simulated S3 bucket.

set -euo pipefail

# --- Configuration from JSON file ---
CONFIG_FILE="/etc/backup/config.json"

# --- Logging ---
# This function will be defined after LOG_FILE is sourced from config
log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# Check for config file and jq
if ! command -v jq &> /dev/null; then
  # Cannot use log_message here as LOG_FILE is not yet defined
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: jq is not installed. Please install jq to continue."
  exit 1
fi
if [ ! -f "\$CONFIG_FILE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Backup configuration file not found at \$CONFIG_FILE"
  exit 1
fi

# Source configuration from JSON
S3_BUCKET_NAME=\$(jq -r '.s3_bucket_name' "\$CONFIG_FILE")
BACKUP_BACKEND=\$(jq -r '.backup_backend // "s3"' "\$CONFIG_FILE")
CASSANDRA_DATA_DIR=\$(jq -r '.cassandra_data_dir' "\$CONFIG_FILE")
LOG_FILE=\$(jq -r '.full_backup_log_file' "\$CONFIG_FILE")
LISTEN_ADDRESS=\$(jq -r '.listen_address' "\$CONFIG_FILE")
KEEP_DAYS=\$(jq -r '.clearsnapshot_keep_days // 0' "\$CONFIG_FILE")

# Validate sourced config
if [ -z "\$S3_BUCKET_NAME" ] || [ -z "\$CASSANDRA_DATA_DIR" ] || [ -z "\$LOG_FILE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from \$CONFIG_FILE"
  exit 1
fi

# --- Static Configuration ---
SNAPSHOT_TAG="full_snapshot_\$(date +%Y%m%d%H%M%S)"
HOSTNAME=\$(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="\$BACKUP_ROOT_DIR/\\\${HOSTNAME}_\$SNAPSHOT_TAG"

# --- Cleanup Snapshot Function ---
cleanup_old_snapshots() {
    if ! [[ "\$KEEP_DAYS" =~ ^[0-9]+$ ]] || [ "\$KEEP_DAYS" -le 0 ]; then
        log_message "INFO: Snapshot retention is not configured to a positive number (\$KEEP_DAYS). Skipping old snapshot cleanup."
        return
    fi

    log_message "--- Starting Old Snapshot Cleanup ---"
    log_message "Retention period: \$KEEP_DAYS days"
    local cutoff_date
    cutoff_date=\$(date -d "-\$KEEP_DAYS days" +%Y%m%d)

    nodetool listsnapshots | while read -r snapshot_line; do
      if [[ "\$snapshot_line" =~ ^(full_snapshot_|adhoc_snapshot_|snapshot_) ]]; then
        local tag
        tag=\$(echo "\$snapshot_line" | awk '{print \$1}')
        # Extract date from tag like 'full_snapshot_YYYYMMDDHHMMSS'
        local snapshot_date
        snapshot_date=\$(echo "\$tag" | sed -n 's/^.*_\\([0-9]\\{8\\}\\)[0-9]\\{6\\}\$/\\1/p')

        if [ -n "\$snapshot_date" ]; then
          if [ "\$snapshot_date" -lt "\$cutoff_date" ]; then
            log_message "Deleting old snapshot: \$tag (date: \$snapshot_date is older than cutoff: \$cutoff_date)"
            if ! nodetool clearsnapshot -t "\$tag"; then
              log_message "ERROR: Failed to delete snapshot \$tag"
            fi
          fi
        fi
      fi
    done
    log_message "--- Snapshot Cleanup Finished ---"
}


# --- Cleanup Functions ---
cleanup_temp_dir() {
  if [ -d "\$BACKUP_TEMP_DIR" ]; then
    log_message "Cleaning up temporary directory: \$BACKUP_TEMP_DIR"
    rm -rf "\$BACKUP_TEMP_DIR"
  fi
}

# --- Main Logic ---
if [ "\$(id -u)" -ne 0 ]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

trap cleanup_temp_dir EXIT

# Check for global backup disable flag
if [ -f "/var/lib/backup-disabled" ]; then
    log_message "INFO: Backup is disabled via /var/lib/backup-disabled. Aborting."
    exit 0
fi

# Run cleanup of old snapshots BEFORE taking a new one
cleanup_old_snapshots

log_message "--- Starting Full Cassandra Snapshot Backup Process ---"
log_message "S3 Bucket: \$S3_BUCKET_NAME"
log_message "Snapshot Tag: \$SNAPSHOT_TAG"

# 1. Create temporary directory structure
mkdir -p "\$BACKUP_TEMP_DIR" || { log_message "ERROR: Failed to create temp backup directories."; exit 1; }

# 2. Create Backup Manifest
MANIFEST_FILE="\$BACKUP_TEMP_DIR/backup_manifest.json"
log_message "Creating backup manifest at \$MANIFEST_FILE..."

CLUSTER_NAME=\$(nodetool describecluster | grep 'Name:' | awk '{print \$2}')

if [ -n "\$LISTEN_ADDRESS" ]; then
    NODE_IP="\$LISTEN_ADDRESS"
else
    NODE_IP="\$(hostname -i)"
fi

NODE_STATUS_LINE=\$(nodetool status | grep "\\b\$NODE_IP\\b")
NODE_DC=\$(echo "\$NODE_STATUS_LINE" | awk '{print \$5}')
NODE_RACK=\$(echo "\$NODE_STATUS_LINE" | awk '{print \$6}')
NODE_TOKENS=\$(nodetool ring | grep "\\b\$NODE_IP\\b" | awk '{print \$NF}' | tr '\\n' ',' | sed 's/,\$//')

jq -n \\
  --arg cluster_name "\$CLUSTER_NAME" \\
  --arg backup_id "\$SNAPSHOT_TAG" \\
  --arg backup_type "full" \\
  --arg timestamp "\$(date --iso-8601=seconds)" \\
  --arg node_ip "\$NODE_IP" \\
  --arg node_dc "\$NODE_DC" \\
  --arg node_rack "\$NODE_RACK" \\
  --arg tokens "\$NODE_TOKENS" \\
  '{
    "cluster_name": \$cluster_name,
    "backup_id": \$backup_id,
    "backup_type": \$backup_type,
    "timestamp_utc": \$timestamp,
    "source_node": {
      "ip_address": \$node_ip,
      "datacenter": \$node_dc,
      "rack": \$node_rack,
      "tokens": (\$tokens | split(","))
    }
  }' > "\$MANIFEST_FILE"

log_message "Manifest created successfully."


# 3. Take a node-local snapshot
log_message "Taking full snapshot with tag: \$SNAPSHOT_TAG..."
if ! nodetool snapshot -t "\$SNAPSHOT_TAG"; then
  log_message "ERROR: Failed to take Cassandra snapshot. Aborting backup."
  exit 1
fi
log_message "Full snapshot taken successfully."

# 4. Collect snapshot file paths
find "\$CASSANDRA_DATA_DIR" -type f -path "*/snapshots/\$SNAPSHOT_TAG/*" > "\$BACKUP_TEMP_DIR/snapshot_files.list"

# 5. Archive the files
TARBALL_PATH_UNCOMPRESSED="\$BACKUP_ROOT_DIR/\\\${HOSTNAME}_\$SNAPSHOT_TAG.tar"
TARBALL_PATH="\$TARBALL_PATH_UNCOMPRESSED.gz"
log_message "Archiving snapshot data to \$TARBALL_PATH..."

if [ ! -s "\$BACKUP_TEMP_DIR/snapshot_files.list" ]; then
    log_message "WARNING: No snapshot files found. The cluster may be empty. Aborting backup."
    nodetool clearsnapshot -t "\$SNAPSHOT_TAG"
    exit 0
fi

tar -cf "\$TARBALL_PATH_UNCOMPRESSED" -P -T "\$BACKUP_TEMP_DIR/snapshot_files.list"
tar -rf "\$TARBALL_PATH_UNCOMPRESSED" -C "\$BACKUP_TEMP_DIR" "backup_manifest.json"
log_message "Backup manifest appended to archive."

# 6. Archive the schema
log_message "Backing up schema..."
SCHEMA_FILE="\$BACKUP_TEMP_DIR/schema.cql"
timeout 30 cqlsh -e "DESCRIBE SCHEMA;" > "\$SCHEMA_FILE"
if [ \$? -ne 0 ]; then
  log_message "WARNING: Failed to dump schema. Backup will continue without it."
else
  # Add schema to the existing tarball
  tar -rf "\$TARBALL_PATH_UNCOMPRESSED" -C "\$BACKUP_TEMP_DIR" "schema.cql"
  log_message "Schema appended to archive."
fi

# 7. Compress the archive
log_message "Compressing the archive..."
gzip "\$TARBALL_PATH_UNCOMPRESSED"
log_message "Archive compressed successfully."


# 8. Upload to S3 and Cleanup
if [ -f "/var/lib/upload-disabled" ]; then
    log_message "INFO: S3 upload is disabled via /var/lib/upload-disabled."
    log_message "Backup archive is available at: \$TARBALL_PATH"
    log_message "Snapshot is available with tag: \$SNAPSHOT_TAG"
    log_message "Skipping S3 upload and local cleanup."
else
    if [ "\$BACKUP_BACKEND" == "s3" ]; then
        BACKUP_DATE=\$(date +%Y-%m-%d)
        UPLOAD_PATH="s3://\$S3_BUCKET_NAME/cassandra/\$HOSTNAME/\$BACKUP_DATE/full/\$SNAPSHOT_TAG.tar.gz"
        log_message "Simulating S3 upload to: \$UPLOAD_PATH"
        # In a real environment, the following line would be active:
        # if ! aws s3 cp "\$TARBALL_PATH" "\$UPLOAD_PATH"; then
        #   log_message "ERROR: Failed to upload backup to S3. Local files will not be cleaned up."
        #   exit 1
        # fi
        log_message "S3 upload simulated successfully."

        # 9. Cleanup (only after successful upload)
        log_message "Cleaning up local archive file..."
        rm -f "\$TARBALL_PATH"
    else
        log_message "INFO: Backup backend is set to '\$BACKUP_BACKEND', not 's3'. Skipping upload."
        log_message "Backup archive is available at: \$TARBALL_PATH"
        log_message "Snapshot is available with tag: \$SNAPSHOT_TAG"
        log_message "Local files will NOT be cleaned up."
    fi
fi

log_message "--- Full Cassandra Snapshot Backup Process Finished Successfully ---"

exit 0
`,
      'incremental-backup-to-s3.sh': `#!/bin/bash
# Archives and uploads existing incremental backup files to a simulated S3 bucket.

set -euo pipefail

# --- Configuration from JSON file ---
CONFIG_FILE="/etc/backup/config.json"

# --- Logging ---
# This function will be defined after LOG_FILE is sourced from config
log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# Check for config file and jq
if ! command -v jq &> /dev/null; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: jq is not installed. Please install jq to continue."
  exit 1
fi

if [ ! -f "\$CONFIG_FILE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Backup configuration file not found at \$CONFIG_FILE"
  exit 1
fi

# Source configuration from JSON
S3_BUCKET_NAME=\$(jq -r '.s3_bucket_name' "\$CONFIG_FILE")
BACKUP_BACKEND=\$(jq -r '.backup_backend // "s3"' "\$CONFIG_FILE")
CASSANDRA_DATA_DIR=\$(jq -r '.cassandra_data_dir' "\$CONFIG_FILE")
LOG_FILE=\$(jq -r '.incremental_backup_log_file' "\$CONFIG_FILE")
LISTEN_ADDRESS=\$(jq -r '.listen_address' "\$CONFIG_FILE")


# Validate sourced config
if [ -z "\$S3_BUCKET_NAME" ] || [ -z "\$CASSANDRA_DATA_DIR" ] || [ -z "\$LOG_FILE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: One or more required configuration values are missing from \$CONFIG_FILE"
  exit 1
fi


# --- Static Configuration ---
BACKUP_TAG="incremental_\$(date +%Y%m%d%H%M%S)"
HOSTNAME=\$(hostname -s)
BACKUP_ROOT_DIR="/tmp/cassandra_backups"
BACKUP_TEMP_DIR="\$BACKUP_ROOT_DIR/\\\${HOSTNAME}_\$BACKUP_TAG"

# --- Cleanup Functions ---
cleanup_temp_dir() {
  if [ -d "\$BACKUP_TEMP_DIR" ]; then
    log_message "Cleaning up temporary directory: \$BACKUP_TEMP_DIR"
    rm -rf "\$BACKUP_TEMP_DIR"
  fi
}

# --- Main Logic ---
if [ "\$(id -u)" -ne 0 ]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

trap cleanup_temp_dir EXIT

# Check for global backup disable flag
if [ -f "/var/lib/backup-disabled" ]; then
    log_message "INFO: Backup is disabled via /var/lib/backup-disabled. Aborting."
    exit 0
fi

log_message "--- Starting Incremental Cassandra Backup Process ---"
log_message "S3 Bucket: \$S3_BUCKET_NAME"
log_message "Backup Tag: \$BACKUP_TAG"

# 1. Create temporary directory structure
mkdir -p "\$BACKUP_TEMP_DIR" || { log_message "ERROR: Failed to create temp backup directory."; exit 1; }


# 2. Collect incremental backup file paths
find "\$CASSANDRA_DATA_DIR" -type f -path "*/backups/*" > "\$BACKUP_TEMP_DIR/incremental_files.list"

# 3. Check if there are files to back up
if [ ! -s "\$BACKUP_TEMP_DIR/incremental_files.list" ]; then
    log_message "No new incremental backup files found. Nothing to do."
    exit 0
fi

# 4. Create Backup Manifest
MANIFEST_FILE="\$BACKUP_TEMP_DIR/backup_manifest.json"
log_message "Creating backup manifest at \$MANIFEST_FILE..."

CLUSTER_NAME=\$(nodetool describecluster | grep 'Name:' | awk '{print \$2}')

if [ -n "\$LISTEN_ADDRESS" ]; then
    NODE_IP="\$LISTEN_ADDRESS"
else
    NODE_IP="\$(hostname -i)"
fi

NODE_STATUS_LINE=\$(nodetool status | grep "\\b\$NODE_IP\\b")
NODE_DC=\$(echo "\$NODE_STATUS_LINE" | awk '{print \$5}')
NODE_RACK=\$(echo "\$NODE_STATUS_LINE" | awk '{print \$6}')
NODE_TOKENS=\$(nodetool ring | grep "\\b\$NODE_IP\\b" | awk '{print \$NF}' | tr '\\n' ',' | sed 's/,\$//')

jq -n \\
  --arg cluster_name "\$CLUSTER_NAME" \\
  --arg backup_id "\$BACKUP_TAG" \\
  --arg backup_type "incremental" \\
  --arg timestamp "\$(date --iso-8601=seconds)" \\
  --arg node_ip "\$NODE_IP" \\
  --arg node_dc "\$NODE_DC" \\
  --arg node_rack "\$NODE_RACK" \\
  --arg tokens "\$NODE_TOKENS" \\
  '{
    "cluster_name": \$cluster_name,
    "backup_id": \$backup_id,
    "backup_type": \$backup_type,
    "timestamp_utc": \$timestamp,
    "source_node": {
      "ip_address": \$node_ip,
      "datacenter": \$node_dc,
      "rack": \$node_rack,
      "tokens": (\$tokens | split(","))
    }
  }' > "\$MANIFEST_FILE"

log_message "Manifest created successfully."


# 5. Archive the files
TARBALL_PATH_UNCOMPRESSED="\$BACKUP_ROOT_DIR/\\\${HOSTNAME}_\$BACKUP_TAG.tar"
TARBALL_PATH="\$TARBALL_PATH_UNCOMPRESSED.gz"
log_message "Archiving incremental data to \$TARBALL_PATH..."

tar -cf "\$TARBALL_PATH_UNCOMPRESSED" -P -T "\$BACKUP_TEMP_DIR/incremental_files.list"
tar -rf "\$TARBALL_PATH_UNCOMPRESSED" -C "\$BACKUP_TEMP_DIR" "backup_manifest.json"
log_message "Backup manifest appended to archive."

# 6. Compress the archive
log_message "Compressing the archive..."
gzip "\$TARBALL_PATH_UNCOMPRESSED"
log_message "Archive compressed successfully."


# 7. Upload to S3 and Cleanup
if [ -f "/var/lib/upload-disabled" ]; then
    log_message "INFO: S3 upload is disabled via /var/lib/upload-disabled."
    log_message "Backup archive is available at: \$TARBALL_PATH"
    log_message "Incremental backup files have NOT been cleaned up and will be included in the next run."
else
    if [ "\$BACKUP_BACKEND" == "s3" ]; then
        BACKUP_DATE=\$(date +%Y-%m-%d)
        UPLOAD_PATH="s3://\$S3_BUCKET_NAME/cassandra/\$HOSTNAME/\$BACKUP_DATE/incremental/\$BACKUP_TAG.tar.gz"
        log_message "Simulating S3 upload to: \$UPLOAD_PATH"
        # In a real environment: aws s3 cp "\$TARBALL_PATH" "\$UPLOAD_PATH"
        log_message "S3 upload simulated successfully."

        # 8. Cleanup (only after successful upload)
        log_message "Cleaning up archived incremental backup files and local tarball..."
        xargs -a "\$BACKUP_TEMP_DIR/incremental_files.list" rm -f
        log_message "Source incremental files deleted."
        rm -f "\$TARBALL_PATH"
        log_message "Local tarball deleted."
    else
        log_message "INFO: Backup backend is set to '\$BACKUP_BACKEND', not 's3'. Skipping upload."
        log_message "Backup archive is available at: \$TARBALL_PATH"
        log_message "Incremental backup files have NOT been cleaned up and will be included in the next run."
    fi
fi

log_message "--- Incremental Cassandra Backup Process Finished Successfully ---"

exit 0
`,
      'restore-from-s3.sh': `#!/bin/bash
# Restores a Cassandra node from a specified backup in S3.
# Supports full node restore, granular keyspace/table restore, and schema-only extraction.

set -euo pipefail

# --- Configuration & Input ---
CONFIG_FILE="/etc/backup/config.json"
HOSTNAME=\$(hostname -s)
RESTORE_LOG_FILE="/var/log/cassandra/restore.log"
BACKUP_ID=""
KEYSPACE_NAME=""
TABLE_NAME=""

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$RESTORE_LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: \$0 [mode] [backup_id] [keyspace] [table]"
    log_message "Modes:"
    log_message "  Full Restore (destructive): \$0 <backup_id>"
    log_message "  Granular Restore:           \$0 <backup_id> <keyspace_name> [table_name]"
    log_message "  Schema-Only Restore:        \$0 --schema-only <backup_id>"
    exit 1
}


# --- Pre-flight Checks ---
if [ "\$(id -u)" -ne 0 ]; then
    log_message "ERROR: This script must be run as root."
    exit 1
fi

for tool in jq aws sstableloader; do
    if ! command -v \$tool &>/dev/null; then
        log_message "ERROR: Required tool '\$tool' is not installed or not in PATH."
        exit 1
    fi
done

if [ ! -f "\$CONFIG_FILE" ]; then
    log_message "ERROR: Backup configuration file not found at \$CONFIG_FILE"
    exit 1
fi

# --- Source configuration from JSON ---
S3_BUCKET_NAME=\$(jq -r '.s3_bucket_name' "\$CONFIG_FILE")
BACKUP_BACKEND=\$(jq -r '.backup_backend // "s3"' "\$CONFIG_FILE")
CASSANDRA_DATA_DIR=\$(jq -r '.cassandra_data_dir' "\$CONFIG_FILE")
CASSANDRA_COMMITLOG_DIR=\$(jq -r '.commitlog_dir' "\$CONFIG_FILE")
CASSANDRA_CACHES_DIR=\$(jq -r '.saved_caches_dir' "\$CONFIG_FILE")
LISTEN_ADDRESS=\$(jq -r '.listen_address' "\$CONFIG_FILE")
SEEDS=\$(jq -r '.seeds_list | join(",")' "\$CONFIG_FILE")
CASSANDRA_USER="cassandra" # Usually static

# Determine node list for sstableloader. Use seeds if available, otherwise localhost.
if [ -n "\$SEEDS" ]; then
    LOADER_NODES="\$SEEDS"
else
    LOADER_NODES="\$LISTEN_ADDRESS"
fi


# --- Function for Schema-Only Restore ---
do_schema_restore() {
    local MANIFEST_JSON="\$1"
    log_message "--- Starting Schema-Only Restore for Backup ID: \$BACKUP_ID ---"

    log_message "Downloading backup to extract schema..."
    if [ "\$BACKUP_BACKEND" != "s3" ]; then
        log_message "ERROR: Cannot restore from backend '\$BACKUP_BACKEND'. This script only supports 's3'."
        exit 1
    fi
    if aws s3 cp "\$S3_PATH" - | tar -xzf - --to-stdout schema.cql > /tmp/schema.cql 2>/dev/null; then
        log_message "SUCCESS: Schema extracted to /tmp/schema.cql"
        log_message "Please review this file, then apply it to your cluster using: cqlsh -u <user> -p <password> -f /tmp/schema.cql"
    else
        log_message "ERROR: Failed to extract schema.cql from the backup. The backup may be corrupted or may not contain a schema file."
        exit 1
    fi
    log_message "--- Schema-Only Restore Finished ---"
}


# --- Function for Full Node Restore ---
do_full_restore() {
    local MANIFEST_JSON="\$1"
    log_message "--- Starting FULL DESTRUCTIVE Node Restore for Backup ID: \$BACKUP_ID ---"

    log_message "This is a DESTRUCTIVE operation. It will:"
    log_message "1. STOP the Cassandra service."
    log_message "2. CHECK for sufficient disk space."
    log_message "3. DELETE all existing data, commitlogs, and caches."
    log_message "4. DOWNLOAD and extract backup from S3."
    log_message "5. CONFIGURE node for startup (cold start or replacement)."
    log_message "6. RESTART the Cassandra service."
    read -p "Are you absolutely sure you want to continue with a full restore? Type 'yes': " confirmation
    if [[ "\$confirmation" != "yes" ]]; then
        log_message "Restore aborted by user."
        exit 0
    fi

    log_message "1. Stopping Cassandra service..."
    systemctl stop cassandra

    log_message "2. Performing pre-restore disk space check..."
    if ! /usr/local/bin/disk-health-check.sh -p "\$CASSANDRA_DATA_DIR" -c 20; then
        exit_code=\$?
        if [ \$exit_code -eq 2 ]; then
            log_message "ERROR: CRITICAL lack of disk space. Restore cannot proceed."
            log_message "Please free up space on the data volume and try again."
            log_message "Aborting restore and restarting Cassandra service."
            systemctl start cassandra
            exit 1
        fi
        log_message "WARNING: Disk space is low. Continuing with restore, but monitor closely."
    fi
    log_message "Disk space check passed."

    log_message "3. Cleaning old directories..."
    rm -rf "\$CASSANDRA_DATA_DIR"/*
    rm -rf "\$CASSANDRA_COMMITLOG_DIR"/*
    rm -rf "\$CASSANDRA_CACHES_DIR"/*
    log_message "Old directories cleaned."

    log_message "4. Downloading and extracting backup..."
    if [ "\$BACKUP_BACKEND" != "s3" ]; then
        log_message "ERROR: Cannot restore from backend '\$BACKUP_BACKEND'. This script only supports 's3'."
        exit 1
    fi
    if ! aws s3 cp "\$S3_PATH" - | tar -xzf - -P; then
        log_message "ERROR: Failed to download or extract backup from S3."
        exit 1
    fi
    log_message "Backup extracted."
    
    # CRITICAL STEP: Determine restore strategy (Initial Seed vs. Replace)
    local ORIGINAL_IP
    ORIGINAL_IP=\$(echo "\$MANIFEST_JSON" | jq -r '.source_node.ip_address')
    local IS_FIRST_NODE=true
    local NODETOOL_HOSTS
    NODETOOL_HOSTS=\$(echo "\$LOADER_NODES" | sed 's/,/ -h /g')

    log_message "Determining restore strategy by checking seed nodes: \$LOADER_NODES"
    # Use nodetool on a list of seeds. If any seed is reachable, we are not the first node.
    if nodetool -h \$NODETOOL_HOSTS status &>/dev/null; then
        IS_FIRST_NODE=false
        log_message "SUCCESS: Connected to live seed node. This node will join an existing cluster."
    else
        log_message "INFO: Could not connect to any live seed nodes. Assuming this is the FIRST NODE in a cold-start DR."
    fi

    local JVM_OPTIONS_FILE="/etc/cassandra/conf/jvm-server.options"
    local CASSANDRA_YAML_FILE="/etc/cassandra/conf/cassandra.yaml"
    
    if [ "\$IS_FIRST_NODE" = true ]; then
        # FIRST NODE STRATEGY: Use initial_token in cassandra.yaml
        log_message "Applying FIRST NODE strategy: Writing initial_token to cassandra.yaml"
        local TOKENS_FROM_BACKUP
        TOKENS_FROM_BACKUP=\$(echo "\$MANIFEST_JSON" | jq -r '.source_node.tokens | join(",")')
        local NUM_TOKENS
        NUM_TOKENS=\$(echo "\$MANIFEST_JSON" | jq -r '.source_node.tokens | length')

        if [ -z "\$TOKENS_FROM_BACKUP" ] || [ "\$NUM_TOKENS" -eq 0 ]; then
            log_message "ERROR: Cannot use initial_token strategy because token data is missing from backup manifest."
            exit 1
        fi

        # Remove old token settings for idempotency
        sed -i '/^num_tokens:/d' "\$CASSANDRA_YAML_FILE"
        sed -i '/^initial_token:/d' "\$CASSANDRA_YAML_FILE"

        # Add new token settings
        echo "num_tokens: \$NUM_TOKENS" >> "\$CASSANDRA_YAML_FILE"
        echo "initial_token: '\$TOKENS_FROM_BACKUP'" >> "\$CASSANDRA_YAML_FILE"
        log_message "Successfully configured num_tokens and initial_token."

    else
        # SUBSEQUENT NODE STRATEGY: Use replace_address
        log_message "Applying SUBSEQUENT NODE strategy: Setting cassandra.replace_address_first_boot"
        if [ "\$ORIGINAL_IP" == "\$LISTEN_ADDRESS" ]; then
            log_message "INFO: Restoring to the same IP. No replacement necessary, but using this path for consistency."
        fi
        
        # Clean up any previous replacement flags
        sed -i '/cassandra.replace_address_first_boot/d' "\$JVM_OPTIONS_FILE"

        # Add the new flag
        echo "-Dcassandra.replace_address_first_boot=\$ORIGINAL_IP" >> "\$JVM_OPTIONS_FILE"
        log_message "Successfully configured JVM for node replacement."
    fi

    log_message "5. Setting permissions..."
    chown -R \$CASSANDRA_USER:\$CASSANDRA_USER "\$CASSANDRA_DATA_DIR"
    chown -R \$CASSANDRA_USER:\$CASSANDRA_USER "\$CASSANDRA_COMMITLOG_DIR"
    chown -R \$CASSANDRA_USER:\$CASSANDRA_USER "\$CASSANDRA_CACHES_DIR"
    log_message "Permissions set."

    log_message "6. Starting Cassandra service..."
    systemctl start cassandra
    log_message "Service started. Waiting for node to initialize..."

    # Wait for the node to come up before cleaning up the flag
    local CASSANDRA_READY=false
    for i in {1..30}; do # Wait up to 5 minutes (30 * 10 seconds)
        if nodetool status > /dev/null 2>&1; then
            CASSANDRA_READY=true
            break
        fi
        log_message "Waiting for Cassandra to be ready... (attempt \$i of 30)"
        sleep 10
    done

    if [ "\$CASSANDRA_READY" = true ]; then
        log_message "SUCCESS: Cassandra node is up and running."
        # Clean up the temporary config so it doesn't get used on the next restart
        if [ "\$IS_FIRST_NODE" = true ]; then
            log_message "Cleaning up initial_token from cassandra.yaml"
            sed -i '/^num_tokens:/d' "\$CASSANDRA_YAML_FILE"
            sed -i '/^initial_token:/d' "\$CASSANDRA_YAML_FILE"
        else
            log_message "Cleaning up replace_address_first_boot flag from JVM options."
            sed -i '/cassandra.replace_address_first_boot/d' "\$JVM_OPTIONS_FILE"
        fi
    else
        log_message "ERROR: Cassandra node failed to start within 5 minutes. Please check system logs for errors."
        exit 1
    fi
    
    log_message "--- Full Restore Process Finished Successfully ---"
}

# --- Function for Granular Restore using sstableloader ---
do_granular_restore() {
    local MANIFEST_JSON="\$1"
    local restore_path
    local restore_type

    if [ -n "\$TABLE_NAME" ]; then
        restore_type="Table '\$TABLE_NAME' in Keyspace '\$KEYSPACE_NAME'"
    else
        restore_type="Keyspace '\$KEYSPACE_NAME'"
    fi

    log_message "--- Starting GRANULAR Restore for \$restore_type from Backup ID: \$BACKUP_ID ---"
    log_message "This will stream data into the LIVE cluster using sstableloader."

    local RESTORE_TEMP_DIR="/tmp/restore_\$BACKUP_ID_\$KEYSPACE_NAME"
    trap 'rm -rf "\$RESTORE_TEMP_DIR"' EXIT
    
    log_message "Performing pre-restore disk space check for temporary directory /tmp..."
    if ! /usr/local/bin/disk-health-check.sh -p /tmp -c 15; then
        exit_code=\$?
        if [ \$exit_code -eq 2 ]; then
            log_message "ERROR: CRITICAL lack of disk space in /tmp. Restore cannot proceed."
            log_message "Please free up space in /tmp and try again."
            exit 1
        fi
        log_message "WARNING: Disk space in /tmp is low. Continuing with restore, but monitor closely."
    fi
    log_message "Disk space check passed."

    mkdir -p "\$RESTORE_TEMP_DIR"

    log_message "Downloading and extracting backup to temporary directory..."
    if [ "\$BACKUP_BACKEND" != "s3" ]; then
        log_message "ERROR: Cannot restore from backend '\$BACKUP_BACKEND'. This script only supports 's3'."
        exit 1
    fi
    aws s3 cp "\$S3_PATH" - | tar -xzf - -C "\$RESTORE_TEMP_DIR"
    
    # sstableloader needs the path to be .../keyspace/table/
    # The backup preserves the full path, so we can find it.
    local extracted_data_path="\$RESTORE_TEMP_DIR\$CASSANDRA_DATA_DIR"

    if [ -n "\$TABLE_NAME" ]; then
        # Find the specific table directory (it has a UUID suffix)
        restore_path=\$(find "\$extracted_data_path/\$KEYSPACE_NAME" -maxdepth 1 -type d -name "\$TABLE_NAME-*")
        if [ -z "\$restore_path" ] || [ ! -d "\$restore_path" ]; then
            log_message "ERROR: Could not find table '\$TABLE_NAME' in the backup for keyspace '\$KEYSPACE_NAME'."
            exit 1
        fi
    else
        restore_path="\$extracted_data_path/\$KEYSPACE_NAME"
        if [ ! -d "\$restore_path" ]; then
            log_message "ERROR: Could not find keyspace '\$KEYSPACE_NAME' in the backup."
            exit 1
        fi
    fi

    log_message "Found data to restore at: \$restore_path"
    log_message "Streaming data to cluster nodes (\$LOADER_NODES) with sstableloader..."

    # Ensure the schema exists before loading data
    log_message "Verifying schema exists..."
    if ! cqlsh -e "DESCRIBE KEYSPACE \$KEYSPACE_NAME;" &>/dev/null; then
        log_message "ERROR: Keyspace '\$KEYSPACE_NAME}' does not exist in the cluster."
        log_message "You must restore the schema before you can load data."
        log_message "Use the --schema-only flag to extract the schema from your backup:"
        log_message "  \$0 --schema-only <backup_id>"
        log_message "Then apply it using: cqlsh -f /tmp/schema.cql"
        exit 1
    fi

    # Run the loader
    if sstableloader -d "\$LOADER_NODES" "\$restore_path"; then
        log_message "sstableloader completed successfully."
    else
        log_message "ERROR: sstableloader failed. Check its output above for details."
        exit 1
    fi

    log_message "Cleaning up temporary files..."
    rm -rf "\$RESTORE_TEMP_DIR"
    trap - EXIT

    log_message "--- Granular Restore Process Finished Successfully ---"
}


# --- Main Logic: Argument Parsing ---

if [ "\$#" -eq 0 ]; then
    usage
fi

if [ "\$1" == "--schema-only" ]; then
    if [ -z "\$2" ]; then
      log_message "ERROR: Backup ID must be provided after --schema-only flag."
      usage
    fi
    BACKUP_ID="\$2"
    MODE="schema"
else
    BACKUP_ID="\$1"
    KEYSPACE_NAME="\$2"
    TABLE_NAME="\$3"
    if [ -z "\$BACKUP_ID" ]; then
        usage
    elif [ -z "\$KEYSPACE_NAME" ]; then
        MODE="full"
    else
        MODE="granular"
    fi
fi


# --- Main Logic: Execution ---

# Determine backup type to find the right S3 path
BACKUP_TYPE=\$(echo "\$BACKUP_ID" | cut -d'_' -f1)
if [[ "\$BACKUP_TYPE" != "full" && "\$BACKUP_TYPE" != "incremental" ]]; then
    log_message "ERROR: Backup ID must start with 'full_' or 'incremental_'. Invalid ID: \$BACKUP_ID"
    exit 1
fi

# Extract date from backup ID like 'type_YYYYMMDDHHMMSS'
BACKUP_DATE_STR=\$(echo "\$BACKUP_ID" | sed -n 's/.*_\\([0-9]\\{8\\}\\).*/\\1/p')
if [ -z "\$BACKUP_DATE_STR" ]; then
    log_message "ERROR: Could not extract date from backup ID '\$BACKUP_ID'. Expected format: type_YYYYMMDDHHMMSS."
    exit 1
fi
BACKUP_DATE_FOLDER=\$(date -d "\$BACKUP_DATE_STR" '+%Y-%m-%d')


TARBALL_NAME="\\\${HOSTNAME}_\$BACKUP_ID.tar.gz"
S3_PATH="s3://\$S3_BUCKET_NAME/cassandra/\$HOSTNAME/\$BACKUP_DATE_FOLDER/\$BACKUP_TYPE/\$TARBALL_NAME"

log_message "Preparing to restore from S3 path: \$S3_PATH"

# --- Fetch and verify manifest first ---
log_message "Fetching backup manifest for verification..."
if [ "\$BACKUP_BACKEND" != "s3" ]; then
    log_message "ERROR: Cannot fetch manifest from backend '\$BACKUP_BACKEND'. This script only supports 's3'."
    exit 1
fi
MANIFEST_JSON=\$(aws s3 cp "\$S3_PATH" - | tar -xzf - --to-stdout backup_manifest.json 2>/dev/null)

if [ -z "\$MANIFEST_JSON" ]; then
    log_message "ERROR: Failed to fetch or find backup_manifest.json in the archive. The backup may be invalid or the S3 path incorrect."
    exit 1
fi

log_message "----------------- BACKUP MANIFEST -----------------"
echo "\$MANIFEST_JSON" | jq '.' | tee -a "\$RESTORE_LOG_FILE"
log_message "---------------------------------------------------"
read -p "Does the manifest above look correct? Type 'yes' to proceed: " manifest_confirmation
if [[ "\$manifest_confirmation" != "yes" ]]; then
    log_message "Restore aborted by user based on manifest review."
    exit 0
fi

# --- Now, execute the chosen mode ---
case \$MODE in
    "schema")
        do_schema_restore "\$MANIFEST_JSON"
        ;;
    "full")
        do_full_restore "\$MANIFEST_JSON"
        ;;
    "granular")
        do_granular_restore "\$MANIFEST_JSON"
        ;;
    *)
        log_message "INTERNAL ERROR: Invalid mode detected."
        exit 1
        ;;
esac

exit 0
`,
      'take-snapshot.sh': `#!/bin/bash
set -euo pipefail

SNAPSHOT_TAG="\\\${1:-snapshot_\$(date +%Y%m%d%H%M%S)}"
KEYSPACES="\\\${2:-}" # Optional: comma-separated list of keyspaces

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1"
}

log_message "--- Taking Cassandra Snapshot ---"
log_message "Snapshot Tag: \$SNAPSHOT_TAG"

CMD="nodetool snapshot -t \$SNAPSHOT_TAG"

if [ -n "\$KEYSPACES" ]; then
    log_message "Targeting keyspaces: \$KEYSPACES"
    # Convert comma-separated to space-separated
    CMD+=" -- \$(echo \$KEYSPACES | sed 's/,/ /g')"
fi

log_message "Executing: \$CMD"
if \$CMD; then
    log_message "SUCCESS: Snapshot '\$SNAPSHOT_TAG' created successfully."
    exit 0
else
    log_message "ERROR: Failed to create snapshot."
    exit 1
fi
`,
      'robust_backup.sh': `#!/bin/bash
set -euo pipefail

# This script creates a local, verified snapshot for ad-hoc backups or testing.
# It does NOT upload to S3 or clean up automatically.

KEYSPACES="\\\${1:-}" # Optional: comma-separated list of keyspaces
SNAPSHOT_TAG="adhoc_snapshot_\$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/var/lib/cassandra/data"
LOG_FILE="/var/log/cassandra/robust_backup.log"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

log_message "--- Starting Robust Local Snapshot ---"
log_message "Snapshot Tag: \$SNAPSHOT_TAG"

# Build command
CMD="nodetool snapshot -t \$SNAPSHOT_TAG"
if [ -n "\$KEYSPACES" ]; then
    log_message "Targeting keyspaces: \$KEYSPACES"
    # Convert comma-separated to space-separated for the command
    CMD+=" -- \$(echo \$KEYSPACES | sed 's/,/ /g')"
fi

# 1. Take snapshot
log_message "Executing: \$CMD"
if ! \$CMD; then
    log_message "ERROR: Failed to take snapshot. Aborting."
    exit 1
fi
log_message "Snapshot created successfully."

# 2. Verify snapshot
log_message "Verifying snapshot files..."
SNAPSHOT_PATH_COUNT=\$(find "\$BACKUP_DIR" -type d -path "*/snapshots/\$SNAPSHOT_TAG" | wc -l)

if [ "\$SNAPSHOT_PATH_COUNT" -eq 0 ]; then
    log_message "WARNING: No snapshot directories found. This may be expected if the targeted keyspaces have no data."
else
    log_message "Found \$SNAPSHOT_PATH_COUNT snapshot directories. Checking for content..."
    # A simple verification: check that there are SSTable files in the snapshot dirs
    SSTABLE_COUNT=\$(find "\$BACKUP_DIR" -type f -path "*/snapshots/\$SNAPSHOT_TAG/*" -name "*.db" | wc -l)
    if [ "\$SSTABLE_COUNT" -gt 0 ]; then
        log_message "OK: Found \$SSTABLE_COUNT SSTable files. Snapshot appears valid."
    else
        log_message "WARNING: No SSTable (.db) files found in snapshot directories. The snapshot might be empty."
    fi
fi

log_message "--- Robust Local Snapshot Finished ---"
log_message "Snapshot tag '\$SNAPSHOT_TAG' is available on disk."
log_message "To clear this snapshot, run: nodetool clearsnapshot -t \$SNAPSHOT_TAG"
exit 0
`,
    };

    

    

    

