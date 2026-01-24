#!/bin/bash
# This file is managed by Puppet.
#
# /etc/puppetlabs/facter/facts.d/cassandra_facts.sh
#
# This is an External Fact script for Facter. It provides facts about the
# local Cassandra node's status, configuration, and resource usage.
#
# These facts will be available in Puppet as, e.g., $facts['cassandra_node_status'].

# --- Helper Function ---
# Safely get a value from a command, returning nothing if it fails.
get_value() {
    local cmd="$1"
    local result
    result=$(eval "$cmd" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result"
    fi
}

# --- Pre-flight Checks ---
# Exit gracefully if nodetool is not available.
if ! command -v nodetool &> /dev/null; then
    exit 0
fi

# Exit gracefully if key config files don't exist
CASSANDRA_YAML="/etc/cassandra/conf/cassandra.yaml"
RACKDC_PROPS="/etc/cassandra/conf/cassandra-rackdc.properties"
BACKUP_CONFIG="/etc/backup/config.json"

if [ ! -f "$CASSANDRA_YAML" ]; then
    exit 0
fi

# --- Gather Facts ---

# Get local IP for filtering nodetool output
LOCAL_IP=$(hostname -i | awk '{print $1}')
if [ -z "$LOCAL_IP" ]; then
    exit 0
fi

# 1. Status & Health Facts
echo "cassandra_node_status=$(get_value "nodetool status | grep '$LOCAL_IP' | awk '{print \$1}'")"
echo "cassandra_schema_version=$(get_value "nodetool describecluster | grep 'Schema versions:' | awk '{print \$NF}' | tr -d '[]' | cut -d',' -f1")"
echo "cassandra_uptime_seconds=$(get_value "nodetool info | grep 'Uptime (seconds)' | awk '{print \$3}'")"

# 2. Configuration & Identity Facts
echo "cassandra_version=$(get_value "nodetool version | grep 'ReleaseVersion' | awk '{print \$2}'")"
echo "cassandra_cluster_name=$(get_value "nodetool describecluster | grep 'Name:' | awk '{print \$2}'")"

if [ -f "$RACKDC_PROPS" ]; then
    echo "cassandra_datacenter=$(get_value "grep '^dc=' $RACKDC_PROPS | cut -d'=' -f2")"
    echo "cassandra_rack=$(get_value "grep '^rack=' $RACKDC_PROPS | cut -d'=' -f2")"
fi

# Check if this node is a seed
SEEDS=$(get_value "grep 'seeds:' $CASSANDRA_YAML | sed 's/.*seeds: \"//' | sed 's/\"//'")
if [[ "$SEEDS" == *"$LOCAL_IP"* ]]; then
    echo "cassandra_is_seed=true"
else
    echo "cassandra_is_seed=false"
fi

# 3. Resource Usage Facts
if [ -f "$BACKUP_CONFIG" ] && command -v jq &> /dev/null; then
    DATA_DIR=$(jq -r '.cassandra_data_dir' "$BACKUP_CONFIG" 2>/dev/null)
    COMMITLOG_DIR=$(jq -r '.commitlog_dir' "$BACKUP_CONFIG" 2>/dev/null)

    if [ -d "$DATA_DIR" ]; then
        echo "cassandra_data_disk_usage_percent=$(get_value "df '$DATA_DIR' --output=pcent | tail -1 | tr -cd '[:digit:]'")"
    fi
    if [ -d "$COMMITLOG_DIR" ]; then
        echo "cassandra_commitlog_disk_usage_percent=$(get_value "df '$COMMITLOG_DIR' --output=pcent | tail -1 | tr -cd '[:digit:]'")"
    fi
fi
