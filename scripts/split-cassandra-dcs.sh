#!/bin/bash
#
# A script to orchestrate the splitting of a multi-datacenter Cassandra cluster
# into two separate, independent clusters. This script uses cassy.sh to execute commands.
# It should be run from an external management server where cassy.sh and qv are available.

set -euo pipefail

# --- Defaults ---
DC1_QUERY=""
DC2_QUERY=""
DC1_NAME=""
DC2_NAME=""
DRY_RUN=false
CASSY_SCRIPT_PATH="./scripts/cassy.sh"

# --- Color Codes ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

# --- Logging ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Usage ---
usage() {
    echo -e "${BOLD}Cassandra Multi-DC Split Orchestrator${NC}"
    echo -e "This script safely splits a multi-datacenter Cassandra cluster into two independent clusters."
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 [OPTIONS]"
    echo
    echo -e "${YELLOW}DESCRIPTION:${NC}"
    echo -e "  This script automates the process of splitting a single, multi-datacenter Cassandra cluster"
    echo -e "  into two separate clusters. It performs validation, updates cluster topology, and orchestrates"
    echo -e "  the data isolation process using the 'cassy.sh' tool."
    echo
    echo -e "${YELLOW}REQUIRED OPTIONS:${NC}"
    printf "  %-30s %s\n" "--dc1-query <query>" "The 'qv' query string to get the nodes of the first datacenter."
    printf "  %-30s %s\n" "--dc2-query <query>" "The 'qv' query string to get the nodes of the second datacenter."
    printf "  %-30s %s\n" "--dc1-name <name>" "The name of the first datacenter (e.g., 'dc1')."
    printf "  %-30s %s\n" "--dc2-name <name>" "The name of the second datacenter (e.g., 'dc2')."
    echo
    echo -e "${YELLOW}OTHER OPTIONS:${NC}"
    printf "  %-30s %s\n" "--cassy-path <path>" "Path to the cassy.sh script. Default: ./scripts/cassy.sh"
    printf "  %-30s %s\n" "--dry-run" "Show all 'cassy.sh' commands that would be run, without executing them."
    printf "  %-30s %s\n" "-h, --help" "Show this help message."
    echo
    echo -e "${YELLOW}EXAMPLE:${NC}"
    echo -e "  $0 --dc1-query \"-r role_cassandra_pfpt -d us-east-1\" \\"
    echo -e "       --dc2-query \"-r role_cassandra_pfpt -d eu-west-1\" \\"
    echo -e "       --dc1-name \"us-east-1\" \\"
    echo -e "       --dc2-name \"eu-west-1\""
    exit 0
}

# --- Function to run cassy.sh commands ---
run_cassy() {
    local cmd_string="$CASSY_SCRIPT_PATH $*"
    log_info "Executing: ${CYAN}${cmd_string}${NC}"
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    # Execute the command
    eval "$cmd_string"
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dc1-query) DC1_QUERY="$2"; shift ;;
        --dc2-query) DC2_QUERY="$2"; shift ;;
        --dc1-name) DC1_NAME="$2"; shift ;;
        --dc2-name) DC2_NAME="$2"; shift ;;
        --cassy-path) CASSY_SCRIPT_PATH="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage ;;
        *) log_error "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# --- Validation ---
if [ -z "$DC1_QUERY" ] || [ -z "$DC2_QUERY" ] || [ -z "$DC1_NAME" ] || [ -z "$DC2_NAME" ]; then
    log_error "Missing one or more required arguments."
    usage
    exit 1
fi
if [ ! -f "$CASSY_SCRIPT_PATH" ]; then
    log_error "cassy.sh script not found at: $CASSY_SCRIPT_PATH"
    exit 1
fi
if ! command -v qv &> /dev/null; then
    log_error "'qv' command not found, which is required for node discovery."
    exit 1
fi

log_info "--- Starting Multi-DC Split Process ---"
log_info "Datacenter 1: $DC1_NAME"
log_info "Datacenter 2: $DC2_NAME"

# --- Phase 1: Discovery ---
log_info "--- Phase 1: Discovery ---"
DC1_NODES=($(qv -t "$DC1_QUERY"))
DC2_NODES=($(qv -t "$DC2_QUERY"))

if [ ${#DC1_NODES[@]} -eq 0 ] || [ ${#DC2_NODES[@]} -eq 0 ]; then
    log_error "Could not discover nodes for one or both datacenters. Aborting."
    exit 1
fi

log_info "Discovered ${#DC1_NODES[@]} nodes in $DC1_NAME and ${#DC2_NODES[@]} in $DC2_NAME."
DC1_RUN_NODE=${DC1_NODES[0]}
DC2_RUN_NODE=${DC2_NODES[0]}

# --- Phase 2: Alter Topology on DC1 ---
log_info "--- Phase 2: Isolate $DC1_NAME by Altering its System Keyspace Topology ---"
log_warn "This step will alter system keyspaces on $DC1_NAME to remove $DC2_NAME from replication."

ALTER_AUTH_CMD="ALTER KEYSPACE system_auth WITH replication = {'class': 'NetworkTopologyStrategy', '$DC1_NAME': 3};"
ALTER_DIST_CMD="ALTER KEYSPACE system_distributed WITH replication = {'class': 'NetworkTopologyStrategy', '$DC1_NAME': 3};"

run_cassy --node "$DC1_RUN_NODE" -c "cqlsh -e \"${ALTER_AUTH_CMD}\""
run_cassy --node "$DC1_RUN_NODE" -c "cqlsh -e \"${ALTER_DIST_CMD}\""

log_success "System keyspace replication updated on $DC1_NAME."

# --- Phase 3: Rolling Restart of DC1 ---
log_info "--- Phase 3: Rolling Restart of $DC1_NAME ---"
log_warn "This will perform a rolling restart of all nodes in $DC1_NAME to pick up the new isolated topology."

run_cassy --rolling-op restart --qv-query "\"$DC1_QUERY\""

log_success "Rolling restart of $DC1_NAME completed."

# --- Phase 4: Decommission DC2 nodes from DC1's perspective ---
log_info "--- Phase 4: Decommission $DC2_NAME nodes from $DC1_NAME's perspective ---"
log_warn "This will run 'nodetool decommission' on each node in $DC2_NAME from a node in $DC1_NAME."

for node in "${DC2_NODES[@]}"; do
    log_info "Decommissioning node $node from $DC1_NAME's perspective..."
    run_cassy --node "$DC1_RUN_NODE" -c "nodetool decommission $node"
done

log_success "Decommission of $DC2_NAME nodes from $DC1_NAME's perspective completed."

# --- Phase 5: Alter Topology on DC2 ---
log_info "--- Phase 5: Isolate $DC2_NAME by Altering its System Keyspace Topology ---"
log_warn "This step will alter system keyspaces on $DC2_NAME to remove $DC1_NAME from replication."

ALTER_AUTH_CMD_DC2="ALTER KEYSPACE system_auth WITH replication = {'class': 'NetworkTopologyStrategy', '$DC2_NAME': 3};"
ALTER_DIST_CMD_DC2="ALTER KEYSPACE system_distributed WITH replication = {'class': 'NetworkTopologyStrategy', '$DC2_NAME': 3};"

run_cassy --node "$DC2_RUN_NODE" -c "cqlsh -e \"${ALTER_AUTH_CMD_DC2}\""
run_cassy --node "$DC2_RUN_NODE" -c "cqlsh -e \"${ALTER_DIST_CMD_DC2}\""

log_success "System keyspace replication updated on $DC2_NAME."

# --- Phase 6: Rolling Restart of DC2 ---
log_info "--- Phase 6: Rolling Restart of $DC2_NAME ---"
log_warn "This will perform a rolling restart of all nodes in $DC2_NAME to pick up the new isolated topology."

run_cassy --rolling-op restart --qv-query "\"$DC2_QUERY\""

log_success "Rolling restart of $DC2_NAME completed."

# --- Phase 7: Decommission DC1 nodes from DC2's perspective ---
log_info "--- Phase 7: Decommission $DC1_NAME nodes from $DC2_NAME's perspective ---"
log_warn "This will run 'nodetool decommission' on each node in $DC1_NAME from a node in $DC2_NAME."

for node in "${DC1_NODES[@]}"; do
    log_info "Decommissioning node $node from $DC2_NAME's perspective..."
    run_cassy --node "$DC2_RUN_NODE" -c "nodetool decommission $node"
done

log_success "Decommission of $DC1_NAME nodes from $DC2_NAME's perspective completed."

log_info "--- Multi-DC Split Process Finished ---"
log_info "The two datacenters should now be operating as independent clusters."
log_info "Run 'cassy --qv-query \"$DC1_QUERY\" -c \"nodetool status\"' and 'cassy --qv-query \"$DC2_QUERY\" -c \"nodetool status\"' to verify each cluster's state."

exit 0
