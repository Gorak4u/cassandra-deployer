#!/bin/bash
#
# A script to orchestrate renaming an entire Cassandra cluster.
# THIS IS A DESTRUCTIVE OPERATION THAT REQUIRES CLUSTER DOWNTIME.
# It should be run from an external management server where cassy.sh and qv are available.

set -euo pipefail

# --- Defaults ---
QV_QUERY=""
OLD_NAME=""
NEW_NAME=""
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
    echo -e "${BOLD}Cassandra Cluster Rename Orchestrator${NC}"
    echo -e "${RED}WARNING: This script performs a downtime-required operation.${NC}"
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 [OPTIONS]"
    echo
    echo -e "${YELLOW}DESCRIPTION:${NC}"
    echo -e "  This script orchestrates a full cluster rename. It stops the cluster, updates the name"
    echo -e "  in both the system tables and configuration files, and then restarts it."
    echo -e "  After running, you MUST update your Puppet/Hiera configuration to match the new name."
    echo
    echo -e "${YELLOW}REQUIRED OPTIONS:${NC}"
    printf "  %-30s %s\n" "--qv-query <query>" "The 'qv' query string to get all nodes of the cluster."
    printf "  %-30s %s\n" "--old-name <name>" "The current cluster name."
    printf "  %-30s %s\n" "--new-name <name>" "The new cluster name."
    echo
    echo -e "${YELLOW}OTHER OPTIONS:${NC}"
    printf "  %-30s %s\n" "--cassy-path <path>" "Path to the cassy.sh script. Default: ./scripts/cassy.sh"
    printf "  %-30s %s\n" "--dry-run" "Show all 'cassy.sh' commands that would be run, without executing them."
    printf "  %-30s %s\n" "-h, --help" "Show this help message."
    echo
    echo -e "${YELLOW}EXAMPLE:${NC}"
    echo -e "  $0 --qv-query \"-r role_cassandra_pfpt -d us-east-1\" \\"
    echo -e "       --old-name \"MyProductionCluster\" \\"
    echo -e "       --new-name \"MyPrimaryCluster\""
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
        --qv-query) QV_QUERY="$2"; shift ;;
        --old-name) OLD_NAME="$2"; shift ;;
        --new-name) NEW_NAME="$2"; shift ;;
        --cassy-path) CASSY_SCRIPT_PATH="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage ;;
        *) log_error "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# --- Validation ---
if [ -z "$QV_QUERY" ] || [ -z "$OLD_NAME" ] || [ -z "$NEW_NAME" ]; then
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

log_info "--- Starting Cluster Rename Process ---"
log_info "Old Name: $OLD_NAME"
log_info "New Name: $NEW_NAME"

# --- Phase 1: Discovery and Validation ---
log_info "--- Phase 1: Discovery and Validation ---"
NODES=($(qv -t "$QV_QUERY"))
if [ ${#NODES[@]} -eq 0 ]; then
    log_error "Could not discover any nodes with the given qv query. Aborting."
    exit 1
fi
RUN_NODE=${NODES[0]}
log_info "Discovered ${#NODES[@]} nodes in the cluster."

log_info "Validating current cluster name on node '$RUN_NODE'..."
# The parsing here is brittle, but reflects the line-based output of cqlsh.
CURRENT_NAME=$("$CASSY_SCRIPT_PATH" --node "$RUN_NODE" --json -c "cqlsh -e \"SELECT cluster_name FROM system.local;\"" | jq -r '.results[0].output | split("\n")[2] | trim')

if [ "$CURRENT_NAME" != "$OLD_NAME" ]; then
    log_error "Validation failed! The cluster's current name is '$CURRENT_NAME', not '$OLD_NAME' as specified."
    exit 1
fi
log_success "Current cluster name matches '$OLD_NAME'."

# --- Confirmation ---
log_warn "--- DOWNTIME REQUIRED ---"
log_warn "This script will shut down the entire Cassandra cluster to perform the rename."
log_warn "It will also disable Puppet and scheduled jobs on all nodes before starting."
read -p "Are you absolutely sure you want to disable automation and proceed with the rename? (yes/no): " confirmation
if [[ "$confirmation" != "yes" ]]; then
    log_info "Rename aborted by user."
    exit 0
fi

# --- Disable Automation ---
log_info "--- Disabling Automation on all nodes ---"
disable_reason="Pausing automation for cluster rename from '${OLD_NAME}' to '${NEW_NAME}'"
run_cassy --qv-query "$QV_QUERY" -P -c "sudo /usr/local/bin/cass-ops disable-automation '${disable_reason}'"
log_success "Automation disabled on all cluster nodes."


# --- Phase 2: Live Update of system.local ---
log_info "--- Phase 2: Updating cluster name in system.local (live) ---"
UPDATE_CQL_CMD="cqlsh -e \"UPDATE system.local SET cluster_name = '${NEW_NAME}' WHERE key='local';\""
run_cassy --qv-query "$QV_QUERY" -P -c "$UPDATE_CQL_CMD"
log_success "system.local updated on all nodes."

# --- Phase 3: Stop Cluster ---
log_info "--- Phase 3: Stopping all Cassandra nodes ---"
run_cassy --qv-query "$QV_QUERY" -P -c 'sudo /usr/local/bin/cass-ops stop'
log_success "All Cassandra services stopped."

# --- Phase 4: Update Config Files ---
log_info "--- Phase 4: Updating cassandra.yaml on all nodes ---"
SED_CMD="sudo sed -i -e \"s/cluster_name: '${OLD_NAME}'/cluster_name: '${NEW_NAME}'/g\" /etc/cassandra/conf/cassandra.yaml"
run_cassy --qv-query "$QV_QUERY" -P -c "$SED_CMD"
log_success "cassandra.yaml updated on all nodes."

# --- Phase 5: Start Cluster ---
log_info "--- Phase 5: Starting all Cassandra nodes ---"
run_cassy --qv-query "$QV_QUERY" -P -c 'sudo systemctl start cassandra'
log_success "Start command issued to all nodes."

# --- Final Instructions ---
log_info "--- Rename Process Finished ---"
log_warn "IMPORTANT: The cluster rename is complete, but the change is NOT PERMANENT yet."
log_warn "You MUST now update your Puppet/Hiera configuration to reflect the new cluster name:"
log_info "  ${CYAN}profile_cassandra_pfpt::cluster_name: '${NEW_NAME}'${NC}"
log_warn "Failure to do so will cause the next Puppet run to revert the change and break the cluster."

log_warn "--- CRITICAL FINAL STEP ---"
log_warn "Automation is still DISABLED on all nodes in the cluster."
log_warn "After updating Hiera, you MUST re-enable automation on all nodes."
log_warn "Run the following command from your management node:"
log_info "  ${CYAN}${CASSY_SCRIPT_PATH} --qv-query \"${QV_QUERY}\" -P -c \"sudo /usr/local/bin/cass-ops enable-automation\"${NC}"
log_info "Then run Puppet on all nodes to make the configuration change permanent."
log_info "Monitor cluster health with: ${CASSY_SCRIPT_PATH} --qv-query \"$QV_QUERY\" -c 'nodetool status'"

exit 0
