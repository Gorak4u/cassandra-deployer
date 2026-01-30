#!/bin/bash
# This file is managed by Puppet.
set -euo pipefail

# --- Defaults ---
SOURCE_DC=""
INTER_DC_THROUGHPUT=0 # Unlimited
COMPACTION_THROUGHPUT=0 # Pause compactions
DEFAULT_COMPACTION_RATE=16 # Default from cassandra_pfpt module
DEFAULT_INTER_DC_RATE=200 # Default from Cassandra

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- Cleanup function to restore settings ---
cleanup() {
    log_message "${BLUE}--- Restoring original throughput settings ---${NC}"
    nodetool setcompactionthroughput ${DEFAULT_COMPACTION_RATE}
    nodetool setinterdcstreamthroughput ${DEFAULT_INTER_DC_RATE}
    log_message "${GREEN}Compaction and stream throughput restored to defaults.${NC}"
}

usage() {
    log_message "Usage: $0 <source_datacenter> [OPTIONS]"
    log_message "Safely rebuilds a node, optimizing throughput during the process."
    log_message ""
    log_message "  <source_datacenter>          (Required) The name of the datacenter to stream from."
    log_message ""
    log_message "Options:"
    log_message "  --compaction-throughput <rate_in_mbps>    Set compaction throughput during rebuild. Default: ${COMPACTION_THROUGHPUT} (paused)."
    log_message "  --inter-dc-stream-throughput <rate_in_mbps> Set inter-DC stream throughput. Default: ${INTER_DC_THROUGHPUT} (unlimited)."
    log_message "  -h, --help                                Show this help message."
    exit 1
}

# --- Argument Parsing ---
if [ -z "$1" ] || [[ "$1" == -* ]]; then
    log_message "${RED}ERROR: Source datacenter must be provided as the first argument.${NC}"
    usage
fi
SOURCE_DC="$1"
shift # Consume the positional argument

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --compaction-throughput) COMPACTION_THROUGHPUT="$2"; shift ;;
        --inter-dc-stream-throughput) INTER_DC_THROUGHPUT="$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "${RED}Unknown parameter passed: $1${NC}"; usage ;;
    esac
    shift
done

# --- Pre-flight checks ---
log_message "${BLUE}--- Performing Pre-flight Cluster Health Check ---${NC}"
if ! /usr/local/bin/cluster-health.sh --silent; then
    log_message "${RED}Cluster health check failed. Aborting rebuild to prevent running on an unstable cluster.${NC}"
    exit 1
fi
log_message "${GREEN}Cluster health check passed. Proceeding with rebuild.${NC}"


log_message "${BLUE}--- Starting Node Rebuild from DC: $SOURCE_DC ---${NC}"
log_message "${YELLOW}This will stream data from other replicas to this node.${NC}"
log_message "${YELLOW}Ensure this node is stopped, its data directory is empty, and it has started up again before running this.${NC}"
read -p "Are you sure you want to continue? Type 'yes': " confirmation
if [[ "$confirmation" != "yes" ]]; then
    log_message "Rebuild aborted by user."
    exit 0
fi

# Set trap to ensure settings are restored on exit
trap cleanup EXIT

# --- Set Optimized Throughput ---
log_message "${BLUE}--- Optimizing node for rebuild ---${NC}"
log_message "Pausing compactions (setting throughput to ${COMPACTION_THROUGHPUT} MB/s)..."
nodetool setcompactionthroughput ${COMPACTION_THROUGHPUT}
log_message "Setting inter-DC stream throughput to ${INTER_DC_THROUGHPUT} MB/s..."
nodetool setinterdcstreamthroughput ${INTER_DC_THROUGHPUT}
log_message "${GREEN}Throughput settings applied.${NC}"

# --- Execute Rebuild ---
log_message "${BLUE}Starting nodetool rebuild...${NC}"
if nodetool rebuild -- "$SOURCE_DC"; then
    log_message "${GREEN}SUCCESS: Nodetool rebuild completed successfully.${NC}"
    # The trap will handle cleanup
    exit 0
else
    REBUILD_STATUS=$?
    log_message "${RED}ERROR: Nodetool rebuild FAILED with exit code $REBUILD_STATUS.${NC}"
    # The trap will still run to clean up
    exit $REBUILD_STATUS
fi
