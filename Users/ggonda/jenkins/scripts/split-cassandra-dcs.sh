#!/bin/bash
#
# A script to orchestrate the splitting of a multi-datacenter Cassandra cluster
# into two separate, independent clusters. This script uses cassy.sh to execute commands.
# It should be run from an external management server where cassy.sh and qv are available.

set -euo pipefail

# --- Defaults ---
DC1_QUERY=""
DC2_QUERY=""
DC1_NODES=""
DC2_NODES=""
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
    echo -e "${YELLOW}PREREQUISITES:${NC}"
    echo -e "  1. A full, verified backup of all data should exist before starting."
    echo -e "  2. Plan for network firewall changes to isolate the DCs after the split is complete."
    echo
    echo -e "${YELLOW}REQUIRED OPTIONS:${NC}"
    printf "  %-30s %s\n" "--dc1-query <query>" "The 'qv' query string to get the nodes of the first datacenter."
    printf "  %-30s %s\n" "--dc2-query <query>" "The 'qv' query string to get the nodes of the second datacenter."
    printf "  %-30s %s\n" "--dc1-nodes <list>" "A comma-separated list of nodes for the first datacenter."
    printf "  %-30s %s\n" "--dc2-nodes <list>" "A comma-separated list of nodes for the second datacenter."
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
        --dc1-query) DC1_QUERY="$2"; shift ;;
        --dc2-query) DC2_QUERY="$2"; shift ;;
        --dc1-nodes) DC1_NODES="$2"; shift ;;
        --dc2-nodes) DC2_NODES="$2"; shift ;;
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
if [ -z "$DC1_NAME" ] || [ -z "$DC2_NAME" ]; then
    log_error "Missing datacenter names (--dc1-name, --dc2-name)."; usage; exit 1
fi
if { [ -z "$DC1_QUERY" ] && [ -z "$DC1_NODES" ]; } || { [ -z "$DC2_QUERY" ] && [ -z "$DC2_NODES" ]; }; then
    log_error "Must specify a node source for both datacenters (e.g., --dc1-query or --dc1-nodes)."; usage; exit 1
fi
if [ -n "$DC1_QUERY" ] && [ -n "$DC1_NODES" ]; then
    log_error "Cannot use --dc1-query and --dc1-nodes together. Please choose one."; usage; exit 1
fi
if [ -n "$DC2_QUERY" ] && [ -n "$DC2_NODES" ]; then
    log_error "Cannot use --dc2-query and --dc2-nodes together. Please choose one."; usage; exit 1
fi

if [ ! -x "$CASSY_SCRIPT_PATH" ]; then
    log_error "cassy.sh script not found or not executable at: $CASSY_SCRIPT_PATH"
    exit 1
fi
if [ -n "$DC1_QUERY" ] || [ -n "$DC2_QUERY" ]; then
    if ! command -v qv &> /dev/null; then
        log_error "'qv' command not found, which is required for node discovery via --*-query flags."
        exit 1
    fi
fi


log_info "--- Starting Multi-DC Split Process ---"
log_warn "This is a significant operation. Ensure you have backups and a network isolation plan."
log_info "Datacenter 1: $DC1_NAME"
log_info "Datacenter 2: $DC2_NAME"

# --- Phase 1: Discovery ---
log_info "--- Phase 1: Discovery ---"
DC1_NODES_ARRAY=()
DC2_NODES_ARRAY=()

if [ -n "$DC1_QUERY" ]; then
    DC1_NODES_ARRAY=($(qv -t "$DC1_QUERY"))
else
    IFS=',' read -r -a DC1_NODES_ARRAY <<< "$DC1_NODES"
fi

if [ -n "$DC2_QUERY" ]; then
    DC2_NODES_ARRAY=($(qv -t "$DC2_QUERY"))
else
    IFS=',' read -r -a DC2_NODES_ARRAY <<< "$DC2_NODES"
fi


if [ ${#DC1_NODES_ARRAY[@]} -eq 0 ] || [ ${#DC2_NODES_ARRAY[@]} -eq 0 ]; then
    log_error "Could not discover nodes for one or both datacenters. Aborting."
    exit 1
fi

log_info "Discovered ${#DC1_NODES_ARRAY[@]} nodes in $DC1_NAME and ${#DC2_NODES_ARRAY[@]} in $DC2_NAME."
DC1_RUN_NODE=${DC1_NODES_ARRAY[0]}
DC2_RUN_NODE=${DC2_NODES_ARRAY[0]}

DC1_NODES_ARG=$([ -n "$DC1_QUERY" ] && echo "--qv-query \"$DC1_QUERY\"" || echo "--nodes \"$DC1_NODES\"")
DC2_NODES_ARG=$([ -n "$DC2_QUERY" ] && echo "--qv-query \"$DC2_QUERY\"" || echo "--nodes \"$DC2_NODES\"")

# --- Pre-Flight: Disable Automation ---
log_info "--- Pre-Flight: Disable Automation ---"
log_warn "This script will now disable Puppet and scheduled jobs on all nodes in both datacenters."
log_warn "This is a critical safety step to prevent interference during the split process."
read -p "Are you sure you want to disable automation and proceed with the split? (yes/no): " confirmation
if [[ "$confirmation" != "yes" ]]; then
    log_info "Split process aborted by user."
    exit 0
fi

disable_reason="Pausing automation for multi-DC split process initiated at $(date)"
log_info "Disabling automation on DC1 nodes..."
run_cassy $DC1_NODES_ARG -P -c "sudo /usr/local/bin/cass-ops disable-automation '${disable_reason}'"
log_info "Disabling automation on DC2 nodes..."
run_cassy $DC2_NODES_ARG -P -c "sudo /usr/local/bin/cass-ops disable-automation '${disable_reason}'"
log_success "Automation disabled on all target nodes."


# --- Phase 2: Alter Topology on DC1 ---
log_info "--- Phase 2: Isolate $DC1_NAME by Altering its System Keyspace Topology ---"
log_warn "This step will alter system keyspaces on $DC1_NAME to remove $DC2_NAME from replication."

# The RF of 3 is hardcoded as a sensible production default.
ALTER_AUTH_CMD="ALTER KEYSPACE system_auth WITH replication = {'class': 'NetworkTopologyStrategy', '$DC1_NAME': 3};"
ALTER_DIST_CMD="ALTER KEYSPACE system_distributed WITH replication = {'class': 'NetworkTopologyStrategy', '$DC1_NAME': 3};"

run_cassy --node "$DC1_RUN_NODE" -c "cqlsh -e \"${ALTER_AUTH_CMD}\""
run_cassy --node "$DC1_RUN_NODE" -c "cqlsh -e \"${ALTER_DIST_CMD}\""

log_success "System keyspace replication updated on $DC1_NAME."

# --- Phase 3: Rolling Restart of DC1 ---
log_info "--- Phase 3: Rolling Restart of $DC1_NAME ---"
log_warn "This will perform a rolling restart of all nodes in $DC1_NAME to pick up the new isolated topology."
run_cassy --rolling-op restart $DC1_NODES_ARG
log_success "Rolling restart of $DC1_NAME completed."

# --- Phase 4: Alter Topology on DC2 ---
log_info "--- Phase 4: Isolate $DC2_NAME by Altering its System Keyspace Topology ---"
log_warn "This step will alter system keyspaces on $DC2_NAME to remove $DC1_NAME from replication."

ALTER_AUTH_CMD_DC2="ALTER KEYSPACE system_auth WITH replication = {'class': 'NetworkTopologyStrategy', '$DC2_NAME': 3};"
ALTER_DIST_CMD_DC2="ALTER KEYSPACE system_distributed WITH replication = {'class': 'NetworkTopologyStrategy', '$DC2_NAME': 3};"

run_cassy --node "$DC2_RUN_NODE" -c "cqlsh -e \"${ALTER_AUTH_CMD_DC2}\""
run_cassy --node "$DC2_RUN_NODE" -c "cqlsh -e \"${ALTER_DIST_CMD_DC2}\""

log_success "System keyspace replication updated on $DC2_NAME."

# --- Phase 5: Rolling Restart of DC2 ---
log_info "--- Phase 5: Rolling Restart of $DC2_NAME ---"
log_warn "This will perform a rolling restart of all nodes in $DC2_NAME to pick up its new isolated topology."
run_cassy --rolling-op restart $DC2_NODES_ARG
log_success "Rolling restart of $DC2_NAME completed."

log_info "--- Multi-DC Split Process Finished ---"
log_warn "IMPORTANT: The final step is to apply firewall rules to prevent network traffic between the two datacenters."
log_info "The two datacenters should now be operating as independent clusters."
log_info "Run '$CASSY_SCRIPT_PATH $DC1_NODES_ARG -c \"nodetool status\"' and '$CASSY_SCRIPT_PATH $DC2_NODES_ARG -c \"nodetool status\"' to verify each cluster's state."

log_warn "--- CRITICAL FINAL STEP ---"
log_warn "Automation is still DISABLED on all nodes in both former datacenters."
log_warn "Once you have applied firewall rules and verified the clusters are independent, you MUST re-enable it."
log_warn "Run the following commands from your management node:"
log_info "  ${CYAN}${CASSY_SCRIPT_PATH} ${DC1_NODES_ARG} -P -c \"sudo /usr/local/bin/cass-ops enable-automation\"${NC}"
log_info "  ${CYAN}${CASSY_SCRIPT_PATH} ${DC2_NODES_ARG} -P -c \"sudo /usr/local/bin/cass-ops enable-automation\"${NC}"

exit 0
