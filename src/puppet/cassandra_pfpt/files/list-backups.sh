#!/bin/bash
set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Config ---
CONFIG_FILE="/etc/backup/config.json"
SOURCE_HOST=""

# --- Logging & Usage ---
log_message() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

usage() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    echo -e "Lists available backups in the configured S3 bucket."
    echo -e ""
    echo -e "Options:"
    echo -e "  -s, --source-host <hostname>   Optional: Specify a single host to list backups for. Defaults to all hosts."
    echo -e "  -h, --help                     Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--source-host) SOURCE_HOST="$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "${RED}Unknown parameter passed: $1${NC}"; usage ;;
    esac
    shift
done

# --- Main Logic ---
log_message "${BLUE}--- Listing Available Backups ---${NC}"

if [ ! -f "$CONFIG_FILE" ]; then
    log_message "${RED}ERROR: Backup configuration file not found at $CONFIG_FILE${NC}"
    exit 1
fi

S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$CONFIG_FILE")
BACKUP_BACKEND=$(jq -r '.backup_backend // "s3"' "$CONFIG_FILE")

if [ "$BACKUP_BACKEND" != "s3" ]; then
    log_message "${YELLOW}Backup backend is not 's3'. This command only works with S3 backups.${NC}"
    exit 0
fi

if ! command -v aws &> /dev/null; then
    log_message "${RED}ERROR: 'aws' command-line tool is not installed or not in PATH.${NC}"
    exit 1
fi

if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_message "${RED}ERROR: AWS credentials are not configured or are invalid.${NC}"
    exit 1
fi

HOSTS_TO_CHECK=()
if [ -n "$SOURCE_HOST" ]; then
    HOSTS_TO_CHECK+=("$SOURCE_HOST")
    log_message "${BLUE}Searching for backups for host: $SOURCE_HOST in bucket s3://$S3_BUCKET_NAME${NC}"
else
    log_message "${BLUE}Discovering all hosts with backups in bucket s3://$S3_BUCKET_NAME...${NC}"
    HOSTS_TO_CHECK=($(aws s3 ls "s3://$S3_BUCKET_NAME/" | awk '{print $2}' | sed 's/\///'))
fi

if [ ${#HOSTS_TO_CHECK[@]} -eq 0 ]; then
    log_message "${YELLOW}No hosts found with backups in the specified bucket and path.${NC}"
    exit 0
fi

echo "" # Newline for formatting
for host in "${HOSTS_TO_CHECK[@]}"; do
    echo -e "${BOLD}${GREEN}Host: ${host}${NC}"
    echo -e "${YELLOW}----------------------------${NC}"
    
    # List directories (backup timestamps) under the host's prefix
    backups=$(aws s3 ls "s3://$S3_BUCKET_NAME/$host/" | awk '{print $2}' | sed 's/\///')
    
    if [ -z "$backups" ]; then
        echo -e "  No backups found for this host."
    else
        # Get manifest for each backup to show type
        while IFS= read -r backup_ts; do
            manifest=$(aws s3 cp "s3://$S3_BUCKET_NAME/$host/$backup_ts/backup_manifest.json" - 2>/dev/null || echo "{}")
            backup_type=$(echo "$manifest" | jq -r '.backup_type // "unknown"')
            
            # Color code the backup type
            type_color=$NC
            if [ "$backup_type" == "full" ]; then
                type_color=$CYAN
            elif [ "$backup_type" == "incremental" ]; then
                type_color=$BLUE
            fi

            echo -e "  - ${BOLD}$backup_ts${NC} (type: ${type_color}${backup_type}${NC})"
        done <<< "$backups"
    fi
    echo "" # Newline for formatting between hosts
done
