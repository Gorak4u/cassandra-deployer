#!/bin/bash
# Checks Cassandra cluster health, Cqlsh connectivity, and native transport port

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

IP_ADDRESS="${1:-$(hostname -I | awk '{print $1}')}" # Use provided IP or default to primary IP
CQLSH_CONFIG="/root/.cassandra/cqlshrc"
CQLSH_SSL_OPT=""

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check for SSL configuration in cqlshrc
if [ -f "$CQLSH_CONFIG" ] && grep -q '\[ssl\]' "$CQLSH_CONFIG"; then
    log_message "${BLUE}SSL section found in cqlshrc, using --ssl for cqlsh commands.${NC}"
    CQLSH_SSL_OPT="--ssl"
fi

# 1. Check nodetool status for 'UN' (Up, Normal)
log_message "${BLUE}Checking nodetool status...${NC}"
NODETOOL_STATUS=$(nodetool status 2>&1)
if echo "$NODETOOL_STATUS" | grep -q 'UN'; then
  log_message "${GREEN}Nodetool status: OK - At least one Up/Normal node found.${NC}"
else
  log_message "${YELLOW}Nodetool status: WARNING - No Up/Normal nodes found or nodetool failed.${NC}"
  echo "$NODETOOL_STATUS"
  # return 1 # Don't exit here, might be starting up
fi

# 2. Check cqlsh connectivity
log_message "${BLUE}Checking cqlsh connectivity using $CQLSH_CONFIG...${NC}"
if cqlsh --cqlshrc "$CQLSH_CONFIG" ${CQLSH_SSL_OPT} "${IP_ADDRESS}" -e "SELECT cluster_name FROM system.local;" >/dev/null 2>&1; then
  log_message "${GREEN}Cqlsh connectivity: OK${NC}"
else
  log_message "${RED}Cqlsh connectivity: FAILED${NC}"
  return 1
fi

# 3. Check native transport port 9042 using nc
log_message "${BLUE}Checking native transport port 9042...${NC}"
if nc -z -w 5 "${IP_ADDRESS}" 9042 >/dev/null 2>&1; then
  log_message "${GREEN}Port 9042 (Native Transport): OPEN${NC}"
else
  log_message "${RED}Port 9042 (Native Transport): CLOSED or FAILED${NC}"
  return 1
fi

log_message "${GREEN}Cluster health check completed successfully.${NC}"
exit 0
