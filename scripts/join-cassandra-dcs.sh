#!/bin/bash
#
# A script to orchestrate the joining of two separate Cassandra datacenters (clusters)
# into a single multi-datacenter cluster. This script uses cassy.sh to execute commands.
# It should be run from an external management server where cassy.sh and qv are available.

set -euo pipefail

# --- Defaults ---
OLD_DC_QUERY=""
NEW_DC_QUERY=""
OLD_DC_NAME=""
NEW_DC_NAME=""
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
    echo -e "${BOLD}Cassandra Multi-DC Join Orchestrator${NC}"
    echo -e "This script safely joins a new Cassandra datacenter to an existing one."
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 [OPTIONS]"
    echo
    echo -e "${YELLOW}DESCRIPTION:${NC}"
    echo -e "  This script automates the complex process of merging two separate Cassandra clusters"
    echo -e "  into a single, multi-datacenter cluster. It performs validation, updates cluster"
    echo -e "  topology, and orchestrates the data rebuild process using the 'cassy.sh' tool."
    echo
    echo -e "${YELLOW}PREREQUISITES:${NC}"
    echo -e "  1. Both clusters MUST have the exact same 'cluster_name' in their cassandra.yaml."
    echo -e "  2. Both clusters MUST be running the same major version of Cassandra and Java."
    echo -e "  3. Network connectivity (ports 7000/7001) MUST be open between all nodes in both datacenters."
    echo -e "  4. 'cassy.sh' and 'qv' must be installed and available on the machine running this script."
    echo
    echo -e "${YELLOW}REQUIRED OPTIONS:${NC}"
    printf "  %-30s %s\n" "--old-dc-query <query>" "The 'qv' query string to get the nodes of the existing datacenter."
    printf "  %-30s %s\n" "--new-dc-query <query>" "The 'qv' query string to get the nodes of the new datacenter to be joined."
    printf "  %-30s %s\n" "--old-dc-name <name>" "The name of the existing datacenter (e.g., 'dc1')."
    printf "  %-30s %s\n" "--new-dc-name <name>" "The name of the new datacenter (e.g., 'dc2')."
    echo
    echo -e "${YELLOW}OTHER OPTIONS:${NC}"
    printf "  %-30s %s\n" "--cassy-path <path>" "Path to the cassy.sh script. Default: ./scripts/cassy.sh"
    printf "  %-30s %s\n" "--dry-run" "Show all 'cassy.sh' commands that would be run, without executing them."
    printf "  %-30s %s\n" "-h, --help" "Show this help message."
    echo
    echo -e "${YELLOW}EXAMPLE:${NC}"
    echo -e "  $0 --old-dc-query \"-r role_cassandra_pfpt -d us-east-1\" \\"
    echo -e "       --new-dc-query \"-r role_cassandra_pfpt -d eu-west-1\" \\"
    echo -e "       --old-dc-name \"us-east-1\" \\"
    echo -e "       --new-dc-name \"eu-west-1\""
    exit 0
}

# --- Function to run cassy.sh commands ---
run_cassy() {
    # This function logs the command and executes it, respecting DRY_RUN.
    # It passes all its arguments directly to the cassy.sh script.
    local args=("$@")
    log_info "Preparing to execute: ${CYAN}${CASSY_SCRIPT_PATH} ${args[*]}${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN: Command not executed."
        return 0
    fi
    # Execute the command directly, which is safer than using eval.
    "$CASSY_SCRIPT_PATH" "${args[@]}"
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --old-dc-query) OLD_DC_QUERY="$2"; shift ;;
        --new-dc-query) NEW_DC_QUERY="$2"; shift ;;
        --old-dc-name) OLD_DC_NAME="$2"; shift ;;
        --new-dc-name) NEW_DC_NAME="$2"; shift ;;
        --cassy-path) CASSY_SCRIPT_PATH="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage ;;
        *) log_error "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# --- Validation ---
if [ -z "$OLD_DC_QUERY" ] || [ -z "$NEW_DC_QUERY" ] || [ -z "$OLD_DC_NAME" ] || [ -z "$NEW_DC_NAME" ]; then
    log_error "Missing one or more required arguments."
    usage
    exit 1
fi
if [ ! -x "$CASSY_SCRIPT_PATH" ]; then
    log_error "cassy.sh script not found or not executable at: $CASSY_SCRIPT_PATH"
    exit 1
fi
if ! command -v qv &> /dev/null; then
    log_error "'qv' command not found, which is required for node discovery."
    exit 1
fi

log_info "--- Starting Multi-DC Join Process ---"
log_info "Old DC Name: $OLD_DC_NAME"
log_info "New DC Name: $NEW_DC_NAME"

# --- Phase 1: Discovery and Validation ---
log_info "--- Phase 1: Discovery and Validation ---"
OLD_NODES=($(qv -t "$OLD_DC_QUERY"))
NEW_NODES=($(qv -t "$NEW_DC_QUERY"))

if [ ${#OLD_NODES[@]} -eq 0 ] || [ ${#NEW_NODES[@]} -eq 0 ]; then
    log_error "Could not discover nodes for one or both datacenters. Aborting."
    exit 1
fi

log_info "Discovered ${#OLD_NODES[@]} nodes in old DC and ${#NEW_NODES[@]} in new DC."
OLD_DC_RUN_NODE=${OLD_NODES[0]}
NEW_DC_RUN_NODE=${NEW_NODES[0]}

log_info "Performing validation checks..."
# Check Cluster Name
log_info "Checking cluster names match..."
CLUSTER_OLD_NAME=$("$CASSY_SCRIPT_PATH" --node "$OLD_DC_RUN_NODE" --json -c "sudo cass-ops health --json" | jq -r '.results[0].output | fromjson | .checks[] | select(.name=="schema_agreement") | .details' | grep 'Name:' | awk '{print $2}')
CLUSTER_NEW_NAME=$("$CASSY_SCRIPT_PATH" --node "$NEW_DC_RUN_NODE" --json -c "sudo cass-ops health --json" | jq -r '.results[0].output | fromjson | .checks[] | select(.name=="schema_agreement") | .details' | grep 'Name:' | awk '{print $2}')

if [ "$CLUSTER_OLD_NAME" != "$CLUSTER_NEW_NAME" ]; then
    log_error "Cluster names do not match! Old DC: '$CLUSTER_OLD_NAME', New DC: '$CLUSTER_NEW_NAME'. Aborting."
    exit 1
fi
log_success "Cluster names match: $CLUSTER_OLD_NAME"

# --- Phase 2: Alter Topology ---
log_info "--- Phase 2: Alter System Keyspace Topology ---"
log_warn "This step will alter system keyspaces on the OLD datacenter to include the NEW datacenter."

# The RF of 3 is hardcoded as a sensible production default.
ALTER_AUTH_CMD="ALTER KEYSPACE system_auth WITH replication = {'class': 'NetworkTopologyStrategy', '$OLD_DC_NAME': 3, '$NEW_DC_NAME': 3};"
ALTER_DIST_CMD="ALTER KEYSPACE system_distributed WITH replication = {'class': 'NetworkTopologyStrategy', '$OLD_DC_NAME': 3, '$NEW_DC_NAME': 3};"

run_cassy --node "$OLD_DC_RUN_NODE" -c "cqlsh -e \"${ALTER_AUTH_CMD}\""
run_cassy --node "$OLD_DC_RUN_NODE" -c "cqlsh -e \"${ALTER_DIST_CMD}\""

log_success "System keyspace replication updated on the old datacenter."

# --- Phase 3: Rolling Restart of New DC ---
log_info "--- Phase 3: Rolling Restart of New Datacenter ---"
log_warn "This will perform a rolling restart of all nodes in the new DC (${NEW_DC_NAME}) to pick up the new topology."
log_warn "This assumes cassandra.yaml on the new nodes has been updated (via Puppet/Hiera) to include seeds from the old DC."

# Pass the qv query with internal quotes escaped for correct execution
run_cassy --rolling-op restart --qv-query "$NEW_DC_QUERY"

log_success "Rolling restart of new datacenter completed."

# --- Phase 4: Data Rebuild ---
log_info "--- Phase 4: Data Rebuild ---"
log_warn "This will run 'nodetool rebuild' sequentially on each node in the new DC to stream data from the old DC."

REBUILD_CMD="sudo /usr/local/bin/cass-ops rebuild $OLD_DC_NAME"

# Use cassy.sh to run the rebuild command sequentially across the new DC
run_cassy --qv-query "$NEW_DC_QUERY" -c "$REBUILD_CMD"

log_success "Data rebuild process completed for the new datacenter."
log_info "--- Multi-DC Join Process Finished ---"
log_info "Run '$CASSY_SCRIPT_PATH --qv-query \"$OLD_DC_QUERY\" -c \"nodetool status\"' to verify cluster state."

exit 0
