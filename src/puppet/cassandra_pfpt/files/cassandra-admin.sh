#!/bin/bash
set -euo pipefail

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Help Function ---
usage() {
    echo -e "${BOLD}Cassandra Operations Master Script${NC}"
    echo ""
    echo -e "A unified wrapper for managing common Cassandra operational tasks on this node."
    echo ""
    echo -e "${YELLOW}Usage: $0 <command> [arguments...]${NC}"
    echo ""
    echo -e "${BLUE}--- Node & Cluster Status ---${NC}"
    echo -e "  ${GREEN}health${NC}                 Run a comprehensive health check on the local node."
    echo -e "  ${GREEN}cluster-health${NC}          Quickly check cluster connectivity and nodetool status."
    echo -e "  ${GREEN}disk-health${NC}             Check disk usage against warning/critical thresholds. Usage: disk-health [-p /path] [-w 80] [-c 90]"
    echo -e "  ${GREEN}version${NC}                 Audit and print versions of key software (OS, Java, Cassandra)."
    echo ""
    echo -e "${BLUE}--- Node Lifecycle & Maintenance ---${NC}"
    echo -e "  ${GREEN}stop${NC}                   Safely drain and stop the Cassandra service."
    echo -e "  ${GREEN}restart${NC}                Perform a safe, rolling restart of the Cassandra service."
    echo -e "  ${GREEN}reboot${NC}                 Safely drain Cassandra and reboot the machine."
    echo -e "  ${GREEN}drain${NC}                  Drain the node, flushing memtables and stopping client traffic."
    echo -e "  ${GREEN}decommission${NC}           Permanently remove this node from the cluster after streaming its data."
    echo -e "  ${GREEN}replace${NC} <dead_node_ip>  Configure this NEW, STOPPED node to replace a dead node."
    echo -e "  ${GREEN}rebuild${NC} <source_dc>     Rebuild the data on this node by streaming from another datacenter."
    echo ""
    echo -e "${BLUE}--- Data Management & Repair ---${NC}"
    echo -e "  ${GREEN}repair${NC} [<keyspace>]     Run a safe, granular repair on the node's token ranges. Can target a specific keyspace."
    echo -e "  ${GREEN}cleanup${NC} [opts]          Run 'nodetool cleanup' with safety checks. Use 'cleanup -- --help' for options."
    echo -e "  ${GREEN}compact${NC} [opts]          Run 'nodetool compact' with safety checks. Use 'compact -- --help' for options."
    echo -e "  ${GREEN}garbage-collect${NC} [opts]  Run 'nodetool garbagecollect' with safety checks. Use 'garbage-collect -- --help' for options."
    echo -e "  ${GREEN}upgrade-sstables${NC} [opts] Run 'nodetool upgradesstables' with safety checks. Use 'upgrade-sstables -- --help' for options."
    echo ""
    echo -e "${BLUE}--- Backup & Recovery ---${NC}"
    echo -e "  ${GREEN}backup${NC}                  Manually trigger a full, node-local backup to S3."
    echo -e "  ${GREEN}snapshot${NC} [<keyspaces>]  Take an ad-hoc snapshot with a generated tag. Optionally specify comma-separated keyspaces."
    echo -e "  ${GREEN}restore${NC} [opts]          Restore data from S3 backups. This is a complex command; run 'restore -- --help' for its usage."
    echo ""
    echo -e "${BLUE}--- Advanced & Destructive Operations (Use with caution!) ---${NC}"
    echo -e "  ${GREEN}assassinate${NC} <dead_node_ip> Forcibly remove a dead node from the cluster's gossip ring."
    echo ""
    echo -e "${BLUE}--- Performance Testing ---${NC}"
    echo -e "  ${GREEN}stress${NC} [opts]            Run 'cassandra-stress' via a robust wrapper. Run 'stress -- --help' for options."
    echo ""
    exit 1
}

if [ "$#" -eq 0 ]; then
    usage
fi

COMMAND="$1"
shift # Remove the command from the argument list

# The main dispatcher
case "$COMMAND" in
    health)
        /usr/local/bin/node_health_check.sh "$@"
        ;;
    cluster-health)
        /usr/local/bin/cluster-health.sh "$@"
        ;;
    disk-health)
        /usr/local/bin/disk-health-check.sh "$@"
        ;;
    version)
        /usr/local/bin/version-check.sh "$@"
        ;;
    stop)
        /usr/local/bin/stop-node.sh "$@"
        ;;
    restart)
        /usr/local/bin/rolling_restart.sh "$@"
        ;;
    reboot)
        /usr/local/bin/reboot-node.sh "$@"
        ;;
    drain)
        /usr/local/bin/drain-node.sh "$@"
        ;;
    decommission)
        /usr/local/bin/decommission-node.sh "$@"
        ;;
    replace)
        /usr/local/bin/prepare-replacement.sh "$@"
        ;;
    rebuild)
        /usr/local/bin/rebuild-node.sh "$@"
        ;;
    repair)
        /usr/local/bin/range-repair.sh "$@"
        ;;
    cleanup)
        /usr/local/bin/cleanup-node.sh "$@"
        ;;
    compact)
        /usr/local/bin/compaction-manager.sh "$@"
        ;;
    garbage-collect)
        /usr/local/bin/garbage-collect.sh "$@"
        ;;
    upgrade-sstables)
        /usr/local/bin/upgrade-sstables.sh "$@"
        ;;
    backup)
        /usr/local/bin/full-backup-to-s3.sh "$@"
        ;;
    snapshot)
        /usr/local/bin/take-snapshot.sh "$@"
        ;;
    restore)
        # Note: The restore script has complex arguments.
        /usr/local/bin/restore-from-s3.sh "$@"
        ;;
    assassinate)
        /usr/local/bin/assassinate-node.sh "$@"
        ;;
    stress)
        /usr/local/bin/stress-test.sh "$@"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$COMMAND'${NC}"
        echo ""
        usage
        ;;
esac
