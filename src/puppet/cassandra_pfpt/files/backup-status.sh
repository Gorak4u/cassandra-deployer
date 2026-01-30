#!/bin/bash
# This file is managed by Puppet.
# Checks the status of the last successful backup by reading its manifest from S3.

set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Configuration & Logging Initialization ---
CONFIG_FILE="/etc/backup/config.json"
LOG_FILE="/var/log/cassandra/backup_status.log"
JSON_OUTPUT=false

log_message() {
    # Suppress human-readable logs when JSON output is requested
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    fi
}

# --- Pre-flight Checks ---
for tool in jq aws; do
    if ! command -v $tool &> /dev/null; then
        # This error should always be shown
        echo -e "${RED}Required tool '$tool' is not installed or in PATH.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
done

if [ ! -f "$CONFIG_FILE" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        jq -n --arg msg "Backup configuration file not found at $CONFIG_FILE" \
            '{status: "ERROR", message: $msg}'
    else
        log_message "${RED}Backup configuration file not found at $CONFIG_FILE${NC}"
    fi
    exit 1
fi

# --- Source All Configuration from JSON ---
S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")
HOSTNAME=$(hostname -s)
SOURCE_HOST_OVERRIDE=""

usage() {
    echo "Usage: $0 [--source-host <hostname>] [--json]"
    echo "  --source-host   Optional: Check status for a different host."
    echo "  --json          Optional: Output the status as a single JSON object."
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --source-host) SOURCE_HOST_OVERRIDE="$2"; shift ;;
        --json) JSON_OUTPUT=true ;;
        *) log_message "${RED}Unknown parameter passed: $1${NC}"; usage ;;
    esac
    shift
done

EFFECTIVE_SOURCE_HOST=${SOURCE_HOST_OVERRIDE:-$HOSTNAME}

# --- Main Logic ---
log_message "${BLUE}--- Checking Last Backup Status for Host: $EFFECTIVE_SOURCE_HOST ---${NC}"

if [ "$BACKUP_BACKEND" != "s3" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        jq -n --arg backend "$BACKUP_BACKEND" \
            '{status: "SKIPPED", message: "Backup backend is not s3", backend: $backend}'
    else
        log_message "${YELLOW}Backup backend is not 's3'. This script can only check S3 backups.${NC}"
    fi
    exit 0
fi

# Find the latest backup directory from S3
log_message "Searching for the latest backup set in s3://${S3_BUCKET_NAME}/${EFFECTIVE_SOURCE_HOST}/..."
LATEST_BACKUP_TS=$(aws s3 ls "s3://${S3_BUCKET_NAME}/${EFFECTIVE_SOURCE_HOST}/" | grep 'PRE' | awk '{print $2}' | sed 's/\///' | sort -r | head -n 1)

if [ -z "$LATEST_BACKUP_TS" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        jq -n \
            --arg host "$EFFECTIVE_SOURCE_HOST" \
            --arg bucket "$S3_BUCKET_NAME" \
            '{status: "NOT_FOUND", message: "No backups found for host", host: $host, bucket: $bucket}'
    else
        log_message "${RED}No backups found for host '${EFFECTIVE_SOURCE_HOST}' in bucket '${S3_BUCKET_NAME}'.${NC}"
    fi
    exit 1
fi

log_message "Found latest backup set: ${LATEST_BACKUP_TS}"

# Download the manifest
MANIFEST_S3_PATH="s3://${S3_BUCKET_NAME}/${EFFECTIVE_SOURCE_HOST}/${LATEST_BACKUP_TS}/backup_manifest.json"
log_message "Downloading manifest: ${MANIFEST_S3_PATH}"
MANIFEST_JSON=$(aws s3 cp "$MANIFEST_S3_PATH" - 2>/dev/null)

if ! echo "$MANIFEST_JSON" | jq -e . > /dev/null 2>&1; then
    if [ "$JSON_OUTPUT" = true ]; then
        jq -n \
            --arg backup_id "$LATEST_BACKUP_TS" \
            '{status: "ERROR", message: "Failed to download or parse manifest for the latest backup set. Backup may be corrupt or incomplete.", backup_id: $backup_id}'
    else
        log_message "${RED}Failed to download or read a valid manifest for backup set ${LATEST_BACKUP_TS}.${NC}"
        log_message "${RED}The backup may be incomplete, corrupt, or there may be an S3 permissions issue.${NC}"
    fi
    exit 1
fi

# Parse information
BACKUP_ID=$(echo "$MANIFEST_JSON" | jq -r '.backup_id')
BACKUP_TYPE=$(echo "$MANIFEST_JSON" | jq -r '.backup_type')
TIMESTAMP_UTC=$(echo "$MANIFEST_JSON" | jq -r '.timestamp_utc')
NODE_IP=$(echo "$MANIFEST_JSON" | jq -r '.source_node.ip_address')
NODE_DC=$(echo "$MANIFEST_JSON" | jq -r '.source_node.datacenter')
TABLES_COUNT=$(echo "$MANIFEST_JSON" | jq -r '.tables_backed_up_count // (.tables_backed_up | length)')

if [ "$JSON_OUTPUT" = true ]; then
    jq -n \
      --arg status "OK" \
      --arg host "$EFFECTIVE_SOURCE_HOST" \
      --arg bucket "$S3_BUCKET_NAME" \
      --arg backup_id "$BACKUP_ID" \
      --arg backup_type "$BACKUP_TYPE" \
      --arg completed_at_utc "$TIMESTAMP_UTC" \
      --arg source_ip "$NODE_IP" \
      --arg source_dc "$NODE_DC" \
      --argjson tables_count "$TABLES_COUNT" \
      '{
        status: $status,
        host: $host,
        bucket: $bucket,
        backup_id: $backup_id,
        backup_type: $backup_type,
        completed_at_utc: $completed_at_utc,
        source_ip: $source_ip,
        source_dc: $source_dc,
        tables_count: $tables_count
      }'
else
    echo ""
    echo -e "${GREEN}--- Last Backup Status Report ---${NC}"
    echo -e "${BOLD}Host:${NC}                  $EFFECTIVE_SOURCE_HOST"
    echo -e "${BOLD}S3 Bucket:${NC}             $S3_BUCKET_NAME"
    echo -e "-----------------------------------"
    echo -e "${BOLD}Backup ID (Timestamp):${NC} $BACKUP_ID"
    echo -e "${BOLD}Backup Type:${NC}           ${BLUE}${BACKUP_TYPE^^}${NC}"
    echo -e "${BOLD}Completed At (UTC):${NC}    $TIMESTAMP_UTC"
    echo -e "${BOLD}Source Node IP:${NC}        $NODE_IP"
    echo -e "${BOLD}Source Datacenter:${NC}     $NODE_DC"
    if [ "$BACKUP_TYPE" == "full" ]; then
        echo -e "${BOLD}Tables Backed Up:${NC}      $TABLES_COUNT"
    else
        echo -e "${BOLD}Tables with Changes:${NC}   $TABLES_COUNT"
    fi
    echo -e "-----------------------------------"
    echo -e "${GREEN}${BOLD}Status:${NC}                ${GREEN}OK - Manifest found and readable.${NC}"
    echo ""
fi

exit 0
