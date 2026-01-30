#!/bin/bash
# This file is managed by Puppet.
# Securely decommissions a Cassandra node from the cluster.

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_message "${BLUE}--- Performing Pre-flight Cluster Health Check ---${NC}"
if ! /usr/local/bin/cluster-health.sh --silent; then
    log_message "${RED}Cluster health check failed. Aborting decommission to prevent running on an unstable cluster.${NC}"
    exit 1
fi
log_message "${GREEN}Cluster health check passed. Proceeding with decommission.${NC}"

log_message "${BLUE}INFO: This script will decommission the local Cassandra node.${NC}"
log_message "${YELLOW}This process will stream all of its data to other nodes in the cluster.${NC}"
log_message "${YELLOW}It cannot be undone.${NC}"
log_message "${YELLOW}Are you sure you want to proceed? Type 'yes' to confirm.${NC}"

read -r confirmation

if [ "$confirmation" != "yes" ]; then
  log_message "Aborted. Node was not decommissioned."
  exit 0
fi

log_message "${BLUE}Starting nodetool decommission...${NC}"
nodetool decommission

DECOMMISSION_STATUS=$?

if [ $DECOMMISSION_STATUS -eq 0 ]; then
  log_message "${GREEN}SUCCESS: Nodetool decommission completed successfully.${NC}"
  log_message "${GREEN}It is now safe to shut down the cassandra service and turn off this machine.${NC}"
  exit 0
else
  log_message "${RED}ERROR: Nodetool decommission FAILED with exit code $DECOMMISSION_STATUS.${NC}"
  log_message "${RED}Check the system logs for more information. Do NOT shut down this node until the issue is resolved.${NC}"
  exit 1
fi
