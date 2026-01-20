
export const healthScripts = {
      'cluster-health.sh': `#!/bin/bash
# Checks Cassandra cluster health, Cqlsh connectivity, and native transport port

IP_ADDRESS="\\\${1:-\$(hostname -I | awk '{print \$1}')}" # Use provided IP or default to primary IP
CQLSH_CONFIG="/root/.cassandra/cqlshrc"

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1"
}

# 1. Check nodetool status for 'UN' (Up, Normal)
log_message "Checking nodetool status..."
NODETOOL_STATUS=\$(nodetool status 2>&1)
if echo "\$NODETOOL_STATUS" | grep -q 'UN'; then
  log_message "Nodetool status: OK - At least one Up/Normal node found."
else
  log_message "Nodetool status: WARNING - No Up/Normal nodes found or nodetool failed."
  echo "\$NODETOOL_STATUS"
  # return 1 # Don't exit here, might be starting up
fi

# 2. Check cqlsh connectivity
log_message "Checking cqlsh connectivity using \$CQLSH_CONFIG..."
if cqlsh --cqlshrc "\$CQLSH_CONFIG" "\\\${IP_ADDRESS}" -e "SELECT cluster_name FROM system.local;" >/dev/null 2>&1; then
  log_message "Cqlsh connectivity: OK"
else
  log_message "Cqlsh connectivity: FAILED"
  return 1
fi

# 3. Check native transport port 9042 using nc
log_message "Checking native transport port 9042..."
if nc -z -w 5 "\\\${IP_ADDRESS}" 9042 >/dev/null 2>&1; then
  log_message "Port 9042 (Native Transport): OPEN"
else
  log_message "Port 9042 (Native Transport): CLOSED or FAILED"
  return 1
fi

log_message "Cluster health check completed successfully."
exit 0
`,
      'disk-health-check.sh': `#!/bin/bash

set -euo pipefail

# These are defaults if not passed via flags.
CASSANDRA_DATADIR=/var/lib/cassandra/data
WARNING_THRESHOLD=30
CRITICAL_THRESHOLD=15

# Color codes
RESET="\\e[0m"
BOLD="\\e[1m"
COL_RED="\\e[31m"
COL_YELLOW="\\e[33m"

function usage() {
  cat<<EOF
usage: \$0 [OPTIONS]

Checks the available disk space for a directory (defaults to '\$CASSANDRA_DATADIR') against given thresholds.
Thresholds are percentages of FREE space.

Flags:
   -p PATH  Path to check disk space for. Default: \$CASSANDRA_DATADIR
   -w INT   Warning threshold (percent free). Default: \$WARNING_THRESHOLD
   -c INT   Critical threshold (percent free). Default: \$CRITICAL_THRESHOLD
   -h       Show this help message.

Exit Codes:
 0: Disk space is sufficient.
 1: Disk space is below the warning threshold.
 2: Disk space is below the critical threshold.
 3: Script failed to get disk space information.
EOF
}

function warning() {
  local msg="\$@"
  printf "\$BOLD\$COL_YELLOW""WARNING: \$msg""\$RESET\\n" >&2
}

function error() {
  local msg="\$@"
  printf "\$BOLD\$COL_RED""ERROR: \$msg""\$RESET\\n" >&2
}

function get_free_disk_space() {
  local mountpoint="\$1"
  local used_percent
  
  used_percent=\$(df "\$mountpoint" --output=pcent | tail -1 | tr -cd '[:digit:]')
  rc=\$?

  if [[ -z "\$used_percent" ]] || [[ \$rc != 0 ]]; then
    error "Failed to get disk space for path '\$mountpoint'."
    exit 3
  fi

  echo \$(( 100 - used_percent ))
}

# --- Main Logic ---
while getopts "hp:w:c:" arg; do
  case \$arg in
    h)
      usage
      exit 0
      ;;
    p)
      CASSANDRA_DATADIR=\$OPTARG
      ;;
    w)
      WARNING_THRESHOLD=\$OPTARG
      ;;
    c)
      CRITICAL_THRESHOLD=\$OPTARG
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

free_space=\$(get_free_disk_space "\$CASSANDRA_DATADIR")
exit_code=\$?

if [[ \$free_space -lt \$CRITICAL_THRESHOLD ]]; then
  error "Free disk space for '\$CASSANDRA_DATADIR' is \$free_space%, which is below the critical threshold of \$CRITICAL_THRESHOLD%."
  exit 2
fi

if [[ \$free_space -lt \$WARNING_THRESHOLD ]]; then
  warning "Free disk space for '\$CASSANDRA_DATADIR' is \$free_space%, which is below the warning threshold of \$WARNING_THRESHOLD%."
  exit 1
fi

printf "OK: Free disk space for '\$CASSANDRA_DATADIR' is \$free_space%%, which is above all thresholds.\\n"
exit 0
`,
      'node_health_check.sh': `#!/bin/bash
set -e

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \\$1"
}

log_ok() {
  log_message "OK: \\$1"
}

log_error() {
  log_message "ERROR: \\$1"
  exit 1
}

log_warning() {
  log_message "WARNING: \\$1"
}

log_message "--- Starting Node Health Check ---"
LOCAL_IP=\$(hostname -i)

# 1. Disk Space Check
log_message "1. Checking disk space..."
if ! /usr/local/bin/disk-health-check.sh; then
    log_error "Disk space check failed. See output from disk-health-check.sh."
else
    log_ok "Disk space is sufficient."
fi

# 2. Node Status Check
log_message "2. Checking local node status..."
NODE_STATUS=\$(nodetool status | grep "\\$LOCAL_IP" | awk '{print \\$1}')

if [ "\\$NODE_STATUS" == "UN" ]; then
    log_ok "Node status is UN (Up/Normal)."
elif [ -z "\\$NODE_STATUS" ]; then
    log_error "Could not find local node IP (\\$LOCAL_IP) in nodetool status output."
else
    log_error "Node status is '\\$NODE_STATUS', not UN."
fi

# 3. Gossip Check
log_message "3. Checking gossip status..."
GOSSIP_STATUS=\$(nodetool gossipinfo | grep "STATUS" | grep "\\$LOCAL_IP" | cut -d':' -f2)
if [[ "\\$GOSSIP_STATUS" == "NORMAL" ]]; then
    log_ok "Gossip state is NORMAL."
else
    log_warning "Gossip state is '\\$GOSSIP_STATUS', not NORMAL. This might be temporary."
fi

# 4. Check for active streams
log_message "4. Checking for network streams..."
if ! nodetool netstats | grep -q "Mode: NORMAL"; then
    log_warning "Node is not in NORMAL mode. It might be streaming, joining, or leaving."
    nodetool netstats
else
    log_ok "Network mode is NORMAL."
fi

# 5. Check for exceptions in the log
log_message "5. Scanning system log for recent exceptions..."
if journalctl -u cassandra -S "10 minutes ago" | grep -q "Exception"; then
    log_warning "Found 'Exception' in Cassandra logs from the last 10 minutes. Please review logs manually."
    journalctl -u cassandra -S "10 minutes ago" | grep "Exception" | tail -n 10
else
    log_ok "No recent exceptions found in logs."
fi

log_message "--- Node Health Check Completed ---"
`,
      'version-check.sh': `#!/bin/bash
# Description: Audit script to check and print versions of various components.

usage() {
    echo "Usage: \$(basename "\\$0") [-h|--help]"
    echo ""
    echo "Options:"
    echo "  -h, --help    Display this help message"
    exit 1
}

# Parse command-line arguments
while [[ "\\$#" -gt 0 ]]; do
    case "\\$1" in
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: \\$1"
            usage
            ;;
    esac
    shift
done

log_version() {
    local component_name="\\$1"
    local command_to_run="\\$2"
    local output

    echo "--- Checking \\$component_name ---"
    if command -v \$(echo "\\$command_to_run" | awk '{print \\$1}') >/dev/null 2>&1; then
        output=\$(eval "\\$command_to_run" 2>&1)
        if [ \\$? -eq 0 ]; then
            echo "Version:"
            echo "\\$output" | head -n 5 # Limit output to relevant lines
        else
            echo "Error running command for \\$component_name: \\$output"
        fi
    else
        echo "\\$component_name command not found: \$(echo "\\$command_to_run" | awk '{print \\$1}')"
    fi
    echo ""
}

log_version "Operating System" "cat /etc/os-release"
log_version "Kernel" "uname -r"
log_version "Puppet" "puppet -V"
log_version "Java" "java -version"
log_version "Cassandra (nodetool)" "nodetool version"
log_version "Python" "python3 --version || python --version"
`,
};

    
