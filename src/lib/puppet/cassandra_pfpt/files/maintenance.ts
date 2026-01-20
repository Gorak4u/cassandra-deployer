
export const maintenanceScripts = {
      'cassandra-upgrade-precheck.sh': `#!/bin/bash
# =============================================================================
# CASSANDRA 3.11 to 4.0 PRE-UPGRADE CHECK SCRIPT
# =============================================================================
# Version: 1.1
# Author: Gorakh Gonda [ggonda@proofpoint.com], with improvements.
# Description: Performs non-invasive read-only checks to validate readiness
#              for upgrading Apache Cassandra from 3.11 to 4.0.
#
# USAGE: sudo ./cassandra-upgrade-precheck.sh
# =============================================================================

# --- CONFIGURATION VARIABLES ---
CASSANDRA_HOME="/usr/share/cassandra"
DATA_DIR="/var/lib/cassandra/data"
CONF_DIR="/etc/cassandra/conf"
YAML_FILE="\\$CONF_DIR/cassandra.yaml"
JVM_OPTS_FILE="\\$CONF_DIR/jvm-server.options"
JAVA_HOME="/usr/lib/jvm/jre-11-openjdk"
NODETOOL="nodetool"
CQLSH="cqlsh"
SSTABLEMETADATA="sstablemetadata"

# Thresholds
MIN_DISK_FREE_PCT=50
MIN_RAM_FREE_MB=1024

# Colors for Output
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
NC='\\033[0m' # No Color

# Flags
FAILURES=0
WARNINGS=0

# --- HELPER FUNCTIONS ---

log_info() {
    echo -e "\\\${BLUE}[INFO]\\\${NC} \\$1"
}

log_ok() {
    echo -e "\\\${GREEN}[OK]\\\${NC} \\$1"
}

log_warn() {
    echo -e "\\\${YELLOW}[WARNING]\\\${NC} \\$1"
    ((WARNINGS++))
}

log_fail() {
    echo -e "\\\${RED}[FAIL]\\\${NC} \\$1"
    ((FAILURES++))
}

check_cmd() {
    if ! command -v "\\$1" &> /dev/null; then
        log_fail "Required command '\\$1' not found in PATH."
        return 1
    fi
    return 0
}

header() {
    echo -e "\\n======================================================"
    echo -e " \\$1"
    echo -e "======================================================"
}

# --- CHECKS ---

check_root() {
    if [[ \\$EUID -ne 0 ]]; then
        log_fail "This script must be run as root or with sudo to access data directories."
        exit 1
    fi
}

check_disk_space() {
    header "Checking System Resources"
    
    # Check Disk Space on Data Directory
    if [ -d "\\$DATA_DIR" ]; then
        local used_percent
        used_percent=\\$(df "\\$DATA_DIR" --output=pcent | tail -1 | tr -cd '[:digit:]')
        if [ -z "\\$used_percent" ]; then
            log_fail "Could not determine disk usage for \\$DATA_DIR."
        else
            local pct_free=\\$((100 - used_percent))
            local avail=\\$(df -h "\\$DATA_DIR" | awk 'NR==2 {print \\$4}')
            
            if [ "\\$pct_free" -lt "\\$MIN_DISK_FREE_PCT" ]; then
                log_fail "Disk space critical: Only \\\${pct_free}% free on \\$DATA_DIR. Recommend >\\\${MIN_DISK_FREE_PCT}% for snapshots."
            else
                log_ok "Disk space acceptable: \\\${pct_free}% free (\\$avail available)."
            fi
        fi
    else
        log_fail "Data directory \\$DATA_DIR does not exist."
    fi

    # Check RAM
    local free_mem=\\$(free -m | awk '/^Mem:/{print \\$7}')
    if [ "\\$free_mem" -lt "\\$MIN_RAM_FREE_MB" ]; then
        log_warn "Available RAM is low: \\\${free_mem}MB. Upgrade process requires overhead."
    else
        log_ok "Available RAM: \\\${free_mem}MB."
    fi
}

check_java_version() {
    header "Checking Java Compatibility"
    
    if [ -x "\\$JAVA_HOME/bin/java" ]; then
        local version=\\$("\\$JAVA_HOME/bin/java" -version 2>&1 | awk -F '"' '/version/ {print \\$2}')
        log_info "Target Java Version detected: \\$version"
        
        # Simple check for Java 11 (Standard for C* 4.0)
        if [[ "\\$version" == 11* ]]; then
            log_ok "Java 11 detected. Compatible with Cassandra 4.0."
        elif [[ "\\$version" == 1.8* ]]; then
            log_warn "Java 8 detected. C* 4.0 supports Java 8, but Java 11 is recommended for GC performance."
        else
            log_warn "Unusual Java version detected. Ensure compatibility matrix is verified."
        fi
    else
        log_fail "Java executable not found at \\$JAVA_HOME/bin/java"
    fi
}

check_cluster_health() {
    header "Checking Cluster Health"
    
    if ! check_cmd "\\$NODETOOL"; then return; fi
    
    log_info "Checking Node Status..."
    local non_un_nodes_output=\\$(\\$NODETOOL status 2>/dev/null | tail -n +6 | head -n -1 | grep -v "^UN ")
    if [ -z "\\$non_un_nodes_output" ]; then # If output is empty, wc -l is 1, so check string directly
        non_un_nodes_count=0
    else
        non_un_nodes_count=\\$(echo "\\$non_un_nodes_output" | wc -l)
    fi
    
    if [ "\\$non_un_nodes_count" -gt 0 ]; then
        log_fail "\\$non_un_nodes_count node(s) are not in UN (Up/Normal) state. Cluster must be stable."
        echo "\\$non_un_nodes_output"
    else
        log_ok "All nodes are UP and NORMAL."
    fi

    # Check Schema Agreement
    log_info "Checking Schema Agreement..."
    local versions_count=\\$(\\$NODETOOL describecluster 2>/dev/null | grep -E '^[[:space:]]*[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}:' | wc -l)
    
    if [ "\\$versions_count" -gt 1 ]; then
        log_fail "Schema disagreement detected! Run 'nodetool describecluster'."
    elif [ "\\$versions_count" -eq 0 ]; then
        log_warn "Could not detect schema version from nodetool describecluster."
    else
        log_ok "Schema is in agreement."
    fi

    # Gossip Info
    log_info "Checking Gossip..."
    \\$NODETOOL gossipinfo > /dev/null
    if [ \\$? -eq 0 ]; then
        log_ok "Gossip is active and reachable."
    else
        log_fail "Gossip check failed."
    fi
}

check_data_health() {
    header "Checking Data Health & Compaction"

    # Active Compactions
    local compact_count=\\$(\\$NODETOOL compactionstats | grep "pending tasks:" | awk '{print \\$3}')
    local active_lines=\\$(\\$NODETOOL compactionstats | grep -v "pending tasks" | grep -v "compaction type" | grep -v "^-" | wc -l)
    
    if [[ "\\$compact_count" -gt 0 ]] || [[ "\\$active_lines" -gt 0 ]]; then
        log_warn "Compactions are currently active or pending (\\$compact_count tasks)."
        log_warn "It is HIGHLY recommended to stop compactions ('nodetool stop COMPACTION') before shutting down for upgrade."
    else
        log_ok "No pending compactions detected."
    fi

    # Dropped Messages
    local dropped=\\$(\\$NODETOOL tpstats | grep "dropped" | awk '{sum+=\\$2} END {print sum}')
    if [[ "\\$dropped" -gt 0 ]]; then
        log_warn "Dropped messages detected in tpstats. Check system load."
    fi
}

check_sstables() {
    header "Analyzing SSTable Formats & Metadata"
    
    if ! check_cmd "\\$SSTABLEMETADATA"; then 
        log_warn "'sstablemetadata' command not found. Skipping deep inspection."
        return
    fi

    # 1. Format Check (Prefixes)
    log_info "Scanning for legacy SSTable formats in \\$DATA_DIR..."
    local legacy_files=\\$(find "\\$DATA_DIR" -name "*Data.db" | grep -v "/mc-" | grep -v "/md-" | head -n 5)
    
    if [ ! -z "\\$legacy_files" ]; then
        log_warn "Found SSTables that do not appear to be version 'mc' or 'md'."
        log_warn "Example: \\$(echo \\$legacy_files | awk '{print \\$1}')"
        log_warn "Run 'nodetool upgradesstables' BEFORE upgrading if these are pre-3.0 formats."
    else
        log_ok "SSTable filename formats appear consistent with 3.x."
    fi

    # 2. RepairedAt Check (Incremental Repair)
    log_info "Checking SSTable Metadata for 'Repaired at' timestamp (Incremental Repair Check)..."
    
    local sample_files=\\$(find "\\$DATA_DIR" -name "*Data.db" | shuf -n 10)
    local repair_issues=0
    local repaired_found=0
    local unrepaired_found=0

    for file in \\$sample_files; do
        local output=\\$(\\$SSTABLEMETADATA "\\$file")
        local repaired_at=\\$(echo "\\$output" | grep "Repaired at" | awk '{print \\$3}')
        
        if [[ "\\$repaired_at" != "0" ]]; then
            ((repaired_found++))
        else
            ((unrepaired_found++))
        fi
    done

    if [[ "\\$repaired_found" -gt 0 && "\\$unrepaired_found" -gt 0 ]]; then
        log_warn "Mixed state detected: Found both Repaired and Unrepaired SSTables."
        log_warn "If you are NOT intentionally using Incremental Repair, this needs investigation."
        log_warn "Migrating to C* 4.0 with mixed repair states can cause over-streaming during bootstrap/repair."
    elif [[ "\\$repaired_found" -gt 0 ]]; then
        log_info "Incremental Repair artifacts detected. Ensure this is expected strategy."
    else
        log_ok "Sampled SSTables appear unrepaired (consistent with Full Repair strategy)."
    fi
}

check_schema_objects() {
    header "Checking Schema Objects (MVs / Secondary Indexes)"
    
    if ! check_cmd "\\$CQLSH"; then 
        log_warn "cqlsh not found, skipping schema query."
        return
    fi
    
    # Check for Materialized Views
    log_info "Querying for Materialized Views..."
    local mv_count=\\$(\\$CQLSH -e "SELECT count(*) FROM system_schema.views;" 2>/dev/null | awk 'NR==3 {print \\$1}')
    
    if [[ "\\$mv_count" =~ ^[0-9]+\$ ]] && [[ "\\$mv_count" -gt 0 ]]; then
        log_fail "Found \\$mv_count Materialized Views (MVs)."
        log_fail "MVs can be unstable or require rebuilding after upgrade. Backup schemas specifically."
    elif ! [[ "\\$mv_count" =~ ^[0-9]+\$ ]]; then
        log_warn "Could not determine Materialized View count. Please check manually."
    else
        log_ok "No Materialized Views found."
    fi

    # Check for Secondary Indexes
    log_info "Querying for Secondary Indexes..."
    local idx_count=\\$(\\$CQLSH -e "SELECT count(*) FROM system_schema.indexes;" 2>/dev/null | awk 'NR==3 {print \\$1}')
    if [[ "\\$idx_count" =~ ^[0-9]+\$ ]] && [[ "\\$idx_count" -gt 0 ]]; then
        log_warn "Found \\$idx_count Secondary Indexes. Ensure application logic handles latency if indexes rebuild on startup."
    elif ! [[ "\\$idx_count" =~ ^[0-9]+\$ ]]; then
        log_warn "Could not determine Secondary Index count. Please check manually."
    else
        log_ok "No Secondary Indexes found."
    fi
}

check_config_and_jvm() {
    header "Checking Configuration & JVM"

    # 1. Check cassandra.yaml for deprecated settings
    if [ -f "\\$YAML_FILE" ]; then
        log_info "Scanning \\$YAML_FILE..."
        
        if grep -q "^start_rpc.*true" "\\$YAML_FILE"; then
            log_fail "'start_rpc: true' found. Thrift is REMOVED in Cassandra 4.0. You must disable it."
        fi

        local deprecated_params=("concurrent_validations" "index_interval" "memtable_allocation_type")
        for param in "\\\${deprecated_params[@]}"; do
            if grep -q "^\\$param" "\\$YAML_FILE"; then
                log_warn "Deprecated parameter found in yaml: \\$param. Remove before 4.0 upgrade."
            fi
        done
    else
        log_fail "cassandra.yaml not found at \\$YAML_FILE"
    fi

    # 2. Check JVM Options
    if [ -f "\\$JVM_OPTS_FILE" ]; then
        log_info "Scanning \\$JVM_OPTS_FILE..."
        
        if grep -E "^-XX:\\+UseConcMarkSweepGC" "\\$JVM_OPTS_FILE" | grep -v "^#" > /dev/null; then
            log_fail "CMS GC (UseConcMarkSweepGC) is enabled. C* 4.0 + Java 11 prefers G1GC."
            log_fail "Update jvm.options to use G1GC settings before starting 4.0."
        fi

        if grep -E "^-XX:\\+UseParNewGC" "\\$JVM_OPTS_FILE" | grep -v "^#" > /dev/null; then
            log_fail "UseParNewGC detected. This flag will prevent Java 11 from starting."
        fi
    else
        log_warn "jvm.options not found. Skipping GC check."
    fi
}

# --- MAIN EXECUTION ---

log_info "Starting Pre-Upgrade Checks: Cassandra 3.11 -> 4.0"
log_info "Hostname: \\\$(hostname)"

check_root
check_disk_space
check_java_version
check_cluster_health
check_data_health
check_sstables
check_schema_objects
check_config_and_jvm

echo -e "\\n======================================================"
echo -e " SUMMARY"
echo -e "======================================================"
if [ "\\$FAILURES" -gt 0 ]; then
    echo -e "\\\${RED}CRITICAL FAILURES: \\$FAILURES\\\${NC}"
    echo -e "\\\${YELLOW}WARNINGS: \\$WARNINGS\\\${NC}"
    echo -e "\\\${RED}Fix critical failures before attempting upgrade.\\\${NC}"
    exit 1
else
    if [ "\\$WARNINGS" -gt 0 ]; then
        echo -e "\\\${GREEN}STATUS: PASSED\\\${NC} (with \\\${YELLOW}\\$WARNINGS warnings\\\${NC})"
        echo -e "Review warnings carefully."
        exit 0
    else
        echo -e "\\\${GREEN}STATUS: READY FOR UPGRADE\\\${NC}"
        exit 0
    fi
fi
`,
      'repair-node.sh': `#!/bin/bash
nodetool repair -pr`,
      'cleanup-node.sh': `#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=""
JOBS=0 # 0 means let Cassandra decide
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=20
CRITICAL_THRESHOLD=10
LOG_FILE="/var/log/cassandra/cleanup.log"

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1" | tee -a "\\$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: \$0 [OPTIONS]"
    log_message "Safely runs 'nodetool cleanup' with pre-flight disk space checks."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to clean up. Can be used multiple times."
    log_message "  -j, --jobs <num>            Number of concurrent sstable cleanup jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: \\$DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning free space threshold (%). Aborts if below. Default: \\$WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical free space threshold (%). Aborts if below. Default: \\$CRITICAL_THRESHOLD"
    log_message "  -h, --help                  Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "\\$#" -gt 0 ]]; do
    case \\$1 in
        -k|--keyspace) KEYSPACE="\\$2"; shift ;;
        -t|--table) TABLE_LIST="\\$TABLE_LIST \\$2"; shift ;;
        -j|--jobs) JOBS="\\$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="\\$2"; shift ;;
        -w|--warning) WARNING_THRESHOLD="\\$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="\\$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: \\$1"; usage ;;
    esac
    shift
done

if [[ -n "\\$TABLE_LIST" && -z "\\$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when cleaning up specific tables (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting Nodetool Cleanup Manager ---"

# Build the nodetool command
CMD="nodetool cleanup"
TARGET_DESC="full node"

# Add options
if [[ \\$JOBS -gt 0 ]]; then
    CMD+=" -j \\$JOBS"
fi

# Add keyspace/table arguments
if [[ -n "\\$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '\\$KEYSPACE'"
    CMD+=" -- \\$KEYSPACE"
    if [[ -n "\\$TABLE_LIST" ]]; then
        CMD+=\\$TABLE_LIST
        CLEAN_TABLE_LIST=\\$(echo "\\$TABLE_LIST" | sed 's/^ *//g')
        TARGET_DESC="table(s) '\\$CLEAN_TABLE_LIST' in keyspace '\\$KEYSPACE'"
    fi
fi

log_message "Target: \\$TARGET_DESC"
log_message "Disk path to check: \\$DISK_CHECK_PATH"
log_message "Warning free space threshold: \\$WARNING_THRESHOLD%"
log_message "Critical free space threshold: \\$CRITICAL_THRESHOLD%"
log_message "Command to be executed: \\$CMD"

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "\\$DISK_CHECK_PATH" -w "\\$WARNING_THRESHOLD" -c "\\$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting cleanup to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with cleanup."

# Execute the command
if \\$CMD; then
    log_message "--- Nodetool Cleanup Finished Successfully ---"
    exit 0
else
    CLEANUP_EXIT_CODE=\\$?
    log_message "ERROR: Nodetool cleanup command failed with exit code \\$CLEANUP_EXIT_CODE."
    exit \\$CLEANUP_EXIT_CODE
fi
`,
      'garbage-collect.sh': `#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=""
GRANULARITY="ROW"
JOBS=0 # 0 means let Cassandra decide
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=30
CRITICAL_THRESHOLD=20
LOG_FILE="/var/log/cassandra/garbagecollect.log"

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1" | tee -a "\\$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: \$0 [OPTIONS]"
    log_message "Safely runs 'nodetool garbagecollect' with pre-flight disk space checks."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to collect. Can be used multiple times."
    log_message "  -g, --granularity <CELL|ROW> Granularity of tombstones to remove. Default: ROW"
    log_message "  -j, --jobs <num>            Number of concurrent sstable garbage collection jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: \\$DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning free space threshold (%). Aborts if below. Default: \\$WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical free space threshold (%). Aborts if below. Default: \\$CRITICAL_THRESHOLD"
    log_message "  -h, --help                  Show this help message."
    log_message ""
    log_message "Examples:"
    log_message "  Collect on entire node:       \$0"
    log_message "  Collect on a keyspace:        \$0 -k my_keyspace"
    log_message "  Collect on specific tables:   \$0 -k my_keyspace -t users -t audit_log"
    log_message "  Collect with cell granularity: \$0 -k my_keyspace -t users -g CELL"
    exit 1
}

# --- Argument Parsing ---
while [[ "\\$#" -gt 0 ]]; do
    case \\$1 in
        -k|--keyspace) KEYSPACE="\\$2"; shift ;;
        -t|--table) TABLE_LIST="\\$TABLE_LIST \\$2"; shift ;;
        -g|--granularity) GRANULARITY="\\$2"; shift ;;
        -j|--jobs) JOBS="\\$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="\\$2"; shift ;;
        -w|--warning) WARNING_THRESHOLD="\\$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="\\$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: \\$1"; usage ;;
    esac
    shift
done

if [[ -n "\\$TABLE_LIST" && -z "\\$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when collecting on specific tables (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting Garbage Collect Manager ---"

# Build the nodetool command
CMD="nodetool garbagecollect"
TARGET_DESC="full node"

# Add options
CMD+=" -g \\$GRANULARITY"
if [[ \\$JOBS -gt 0 ]]; then
    CMD+=" -j \\$JOBS"
fi

# Add keyspace/table arguments
if [[ -n "\\$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '\\$KEYSPACE'"
    CMD+=" -- \\$KEYSPACE"
    if [[ -n "\\$TABLE_LIST" ]]; then
        CMD+=\\$TABLE_LIST
        # Remove leading space for description
        CLEAN_TABLE_LIST=\\$(echo "\\$TABLE_LIST" | sed 's/^ *//g')
        TARGET_DESC="table(s) '\\$CLEAN_TABLE_LIST' in keyspace '\\$KEYSPACE'"
    fi
fi

log_message "Target: \\$TARGET_DESC"
log_message "Disk path to check: \\$DISK_CHECK_PATH"
log_message "Warning free space threshold: \\$WARNING_THRESHOLD%"
log_message "Critical free space threshold: \\$CRITICAL_THRESHOLD%"
log_message "Command to be executed: \\$CMD"

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "\\$DISK_CHECK_PATH" -w "\\$WARNING_THRESHOLD" -c "\\$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting garbage collection to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with garbage collection."

# Execute the command
if \\$CMD; then
    log_message "--- Garbage Collect Finished Successfully ---"
    exit 0
else
    GC_EXIT_CODE=\\$?
    log_message "ERROR: Garbage collection command failed with exit code \\$GC_EXIT_CODE."
    exit \\$GC_EXIT_CODE
fi
`,
      'upgrade-sstables.sh': `#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE_LIST=""
JOBS=0 # 0 means let Cassandra decide
DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=30 # Upgrade can be disk intensive
CRITICAL_THRESHOLD=20
LOG_FILE="/var/log/cassandra/upgradesstables.log"

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1" | tee -a "\\$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: \$0 [OPTIONS]"
    log_message "Safely runs 'nodetool upgradesstables' with pre-flight disk space checks."
    log_message "This is typically run after a major version upgrade of Cassandra."
    log_message "  -k, --keyspace <name>       Specify the keyspace. Required if specifying tables."
    log_message "  -t, --table <name>          Specify a table to upgrade. Can be used multiple times."
    log_message "  -j, --jobs <num>            Number of concurrent sstable upgrade jobs. Default: 0 (auto)"
    log_message "  -d, --disk-path <path>      Path to monitor for disk space. Default: \\$DISK_CHECK_PATH"
    log_message "  -w, --warning <%>           Warning free space threshold (%). Aborts if below. Default: \\$WARNING_THRESHOLD"
    log_message "  -c, --critical <%>          Critical free space threshold (%). Aborts if below. Default: \\$CRITICAL_THRESHOLD"
    log_message "  -h, --help                  Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ "\\$#" -gt 0 ]]; do
    case \\$1 in
        -k|--keyspace) KEYSPACE="\\$2"; shift ;;
        -t|--table) TABLE_LIST="\\$TABLE_LIST \\$2"; shift ;;
        -j|--jobs) JOBS="\\$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="\\$2"; shift ;;
        -w|--warning) WARNING_THRESHOLD="\\$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="\\$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: \\$1"; usage ;;
    esac
    shift
done

if [[ -n "\\$TABLE_LIST" && -z "\\$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when upgrading specific tables (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting SSTable Upgrade Manager ---"

# Build the nodetool command
CMD="nodetool upgradesstables"
TARGET_DESC="all keyspaces and tables"

# Add options
if [[ \\$JOBS -gt 0 ]]; then
    CMD+=" -j \\$JOBS"
fi

# Add keyspace/table arguments
if [[ -n "\\$KEYSPACE" ]]; then
    TARGET_DESC="keyspace '\\$KEYSPACE'"
    CMD+=" -- \\$KEYSPACE"
    if [[ -n "\\$TABLE_LIST" ]]; then
        CMD+=\\$TABLE_LIST
        CLEAN_TABLE_LIST=\\$(echo "\\$TABLE_LIST" | sed 's/^ *//g')
        TARGET_DESC="table(s) '\\$CLEAN_TABLE_LIST' in keyspace '\\$KEYSPACE'"
    fi
else
    # If no keyspace is provided, nodetool upgrades all sstables. The -a flag is implied.
    CMD+=" -a"
fi

log_message "Target: \\$TARGET_DESC"
log_message "Disk path to check: \\$DISK_CHECK_PATH"
log_message "Warning free space threshold: \\$WARNING_THRESHOLD%"
log_message "Critical free space threshold: \\$CRITICAL_THRESHOLD%"
log_message "Command to be executed: \\$CMD"

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "\\$DISK_CHECK_PATH" -w "\\$WARNING_THRESHOLD" -c "\\$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting SSTable upgrade to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with SSTable upgrade."

# Execute the command
if \\$CMD; then
    log_message "--- SSTable Upgrade Finished Successfully ---"
    exit 0
else
    UPGRADE_EXIT_CODE=\\$?
    log_message "ERROR: SSTable upgrade command failed with exit code \\$UPGRADE_EXIT_CODE."
    exit \\$UPGRADE_EXIT_CODE
fi
`,
      'compaction-manager.sh': `#!/bin/bash
set -euo pipefail

# --- Defaults & Configuration ---
KEYSPACE=""
TABLE=""
DISK_CHECK_PATH="/var/lib/cassandra/data"
CRITICAL_THRESHOLD=15 # Abort if free space drops below 15%
CHECK_INTERVAL=30     # Check disk space every 30 seconds
LOG_FILE="/var/log/cassandra/compaction_manager.log"

# --- Logging ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1" | tee -a "\\$LOG_FILE"
}

# --- Usage ---
usage() {
    log_message "Usage: \$0 [OPTIONS]"
    log_message "Manages Cassandra compaction with disk space monitoring."
    log_message "  -k, --keyspace <name>    Specify the keyspace to compact. (Required for -t)"
    log_message "  -t, --table <name>       Specify the table to compact."
    log_message "  -d, --disk-path <path>   Path to monitor for disk space. Default: \\$DISK_CHECK_PATH"
    log_message "  -c, --critical <%>       Critical free space threshold (%). Aborts if below. Default: \\$CRITICAL_THRESHOLD"
    log_message "  -i, --interval <sec>     Interval in seconds to check disk space. Default: \\$CHECK_INTERVAL"
    log_message "  -h, --help               Show this help message."
    log_message ""
    log_message "Examples:"
    log_message "  Full node compaction:       \$0"
    log_message "  Keyspace compaction:        \$0 -k my_keyspace"
    log_message "  Table compaction:           \$0 -k my_keyspace -t my_table"
    exit 1
}

# --- Argument Parsing ---
while [[ "\\$#" -gt 0 ]]; do
    case \\$1 in
        -k|--keyspace) KEYSPACE="\\$2"; shift ;;
        -t|--table) TABLE="\\$2"; shift ;;
        -d|--disk-path) DISK_CHECK_PATH="\\$2"; shift ;;
        -c|--critical) CRITICAL_THRESHOLD="\\$2"; shift ;;
        -i|--interval) CHECK_INTERVAL="\\$2"; shift ;;
        -h|--help) usage ;;
        *) log_message "Unknown parameter passed: \\$1"; usage ;;
    esac
    shift
done

if [[ -n "\\$TABLE" && -z "\\$KEYSPACE" ]]; then
    log_message "ERROR: A keyspace (-k) must be specified when compacting a table (-t)."
    exit 1
fi

# --- Main Logic ---
log_message "--- Starting Compaction Manager ---"

# Build the nodetool command
CMD="nodetool compact"
TARGET_DESC="full node"
if [[ -n "\\$KEYSPACE" ]]; then
    CMD+=" \\$KEYSPACE"
    TARGET_DESC="keyspace '\\$KEYSPACE'"
    if [[ -n "\\$TABLE" ]]; then
        CMD+=" \\$TABLE"
        TARGET_DESC="table '\\$TABLE'"
    fi
fi

log_message "Target: \\$TARGET_DESC"
log_message "Disk path to monitor: \\$DISK_CHECK_PATH"
log_message "Critical free space threshold: \\$CRITICAL_THRESHOLD%"
log_message "Disk check interval: \\$CHECK_INTERVALs"

# Start compaction in the background
log_message "Starting compaction process..."
\\$CMD &
COMPACTION_PID=\\$!
log_message "Compaction started with PID: \\$COMPACTION_PID"

# Monitor the process
while ps -p \\$COMPACTION_PID > /dev/null; do
    log_message "Compaction running (PID: \\$COMPACTION_PID). Checking disk space..."
    
    # Use the existing health check script
    if ! /usr/local/bin/disk-health-check.sh -p "\\$DISK_CHECK_PATH" -c "\\$CRITICAL_THRESHOLD"; then
        log_message "CRITICAL: Disk space threshold reached. Stopping compaction."
        nodetool stop COMPACTION
        # Wait a moment for the stop command to be processed
        sleep 10
        # Check if the process is still running, if so, kill it forcefully
        if ps -p \\$COMPACTION_PID > /dev/null; then
             log_message "Nodetool stop did not terminate process. Sending KILL signal to PID \\$COMPACTION_PID."
             kill -9 \\$COMPACTION_PID
        fi
        log_message "ERROR: Compaction aborted due to low disk space."
        exit 2
    fi

    log_message "Disk space OK. Sleeping for \\$CHECK_INTERVAL seconds."
    sleep \\$CHECK_INTERVAL
done

wait \\$COMPACTION_PID
COMPACTION_EXIT_CODE=\\$?

if [[ \\$COMPACTION_EXIT_CODE -eq 0 ]]; then
    log_message "--- Compaction Manager Finished Successfully ---"
    exit 0
else
    # This handles cases where compaction fails for reasons other than disk space
    log_message "ERROR: Compaction process (PID: \\$COMPACTION_PID) exited with non-zero status: \\$COMPACTION_EXIT_CODE."
    exit \\$COMPACTION_EXIT_CODE
fi
`,
      'cassandra_range_repair.py': `#!/usr/bin/env python3
import subprocess
import sys
import argparse

def run_repair(keyspace, full=False):
    """
    Runs nodetool repair on a given keyspace.
    By default, it runs a primary range repair (-pr).
    """
    if full:
        repair_type = "full"
        command = f"nodetool repair {keyspace}"
    else:
        repair_type = "primary range"
        command = f"nodetool repair -pr {keyspace}"

    print(f"--- Starting {repair_type} repair for keyspace '{keyspace}' ---")
    print(f"Executing command: {command}")

    try:
        # Use Popen to stream output in real time
        process = subprocess.Popen(
            command.split(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        # Read and print output line by line
        for line in iter(process.stdout.readline, ''):
            print(line, end='')

        process.stdout.close()
        return_code = process.wait()

        if return_code == 0:
            print(f"--- Repair for keyspace '{keyspace}' completed successfully. ---")
        else:
            print(f"--- ERROR: Repair for keyspace '{keyspace}' failed with exit code {return_code}. ---", file=sys.stderr)
        
        return return_code

    except FileNotFoundError:
        print("ERROR: 'nodetool' command not found. Is Cassandra installed and in your PATH?", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        return 1

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="A wrapper script for running Cassandra's nodetool repair.")
    parser.add_argument('keyspace', help='The name of the keyspace to repair.')
    parser.add_argument('--full', action='store_true', help='Perform a full repair instead of a primary range repair.')
    
    args = parser.parse_args()
    
    exit_code = run_repair(args.keyspace, args.full)
    sys.exit(exit_code)
`,
      'range-repair.sh': `#!/bin/bash
set -euo pipefail

# This script runs a primary-range repair on the local node.
# It includes a pre-flight disk space check.

DISK_CHECK_PATH="/var/lib/cassandra/data"
WARNING_THRESHOLD=25
CRITICAL_THRESHOLD=15
LOG_FILE="/var/log/cassandra/repair.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1" | tee -a "\\$LOG_FILE"
}

log_message "--- Starting Primary Range Repair ---"
log_message "This will repair the primary token ranges this node is responsible for."

# Pre-flight disk space check
log_message "Performing pre-flight disk space check..."
if ! /usr/local/bin/disk-health-check.sh -p "\\$DISK_CHECK_PATH" -w "\\$WARNING_THRESHOLD" -c "\\$CRITICAL_THRESHOLD"; then
    log_message "ERROR: Pre-flight disk space check failed. Aborting repair to prevent disk space issues."
    exit 1
fi
log_message "Disk space OK. Proceeding with repair."

# Execute repair
if nodetool repair -pr; then
    log_message "--- Primary Range Repair Finished Successfully ---"
    exit 0
else
    REPAIR_EXIT_CODE=\\$?
    log_message "ERROR: Nodetool repair failed with exit code \\$REPAIR_EXIT_CODE."
    exit \\$REPAIR_EXIT_CODE
fi
`,
};

    

    
