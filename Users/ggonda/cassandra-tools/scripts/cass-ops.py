#!/usr/bin/env python3
# This file is managed by Puppet.
#
# Unified operations script for Cassandra.
# This script acts as a dispatcher for various management and operational scripts.

import sys
import os
import argparse
import subprocess

# --- Color Codes for Help Text ---
class Colors:
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    END = '\033[0m'

# --- Command Definitions ---
# Maps command categories to commands. Each command has:
# (description, script_name, safety_level)
# Safety levels: readonly, modify, destructive, info
COMMAND_CATEGORIES = {
    "Health & Status (Read-Only)": {
        'health': ('Run a comprehensive health check on the local node.', 'node_health_check.sh', 'readonly'),
        'cluster-health': ('Quickly check cluster connectivity and nodetool status.', 'cluster-health.sh', 'readonly'),
        'disk-health': ('Check disk usage against warning/critical thresholds.', 'disk-health-check.sh', 'readonly'),
        'version': ('Audit and print versions of key software (OS, Java, Cassandra).', 'version-check.sh', 'readonly'),
        'backup-status': ('Check the status of the last completed backup for a node.', 'backup-status.sh', 'readonly'),
        'backup-verify': ('Verify the integrity and restorability of the latest backup set.', 'verify-backup.sh', 'readonly'),
        'upgrade-check': ('Run pre-flight checks before a major version upgrade.', 'cassandra-upgrade-precheck.sh', 'readonly'),
        'tombstone-scan': ('Scan tables for high tombstone counts. Can perform a deep-dive on a specific table.', 'tombstone-scan.sh', 'readonly'),
        'sstabledump': ('Inspect the content of SSTables for a given table.', 'sstabledump.sh', 'readonly'),
    },
    "Node Lifecycle (High-Impact / Destructive)": {
        'stop': ('Safely drain and stop the Cassandra service.', 'stop-node.sh', 'destructive'),
        'restart': ('Perform a safe, rolling restart of the Cassandra service.', 'rolling_restart.sh', 'destructive'),
        'reboot': ('Safely drain Cassandra and reboot the machine.', 'reboot-node.sh', 'destructive'),
        'decommission': ('Permanently remove this node from the cluster after streaming its data.', 'decommission-node.sh', 'destructive'),
        'replace': ('Configure this NEW, STOPPED node to replace a dead node.', 'prepare-replacement.sh', 'destructive'),
        'assassinate': ('Forcibly remove a dead node from the cluster\'s gossip ring.', 'assassinate-node.sh', 'destructive'),
        'rebuild': ('Rebuild the data on this node by streaming from another datacenter.', 'rebuild-node.sh', 'destructive'),
    },
    "Data & Maintenance (Modify State)": {
        'drain': ('Drain the node, flushing memtables and stopping client traffic.', 'drain-node.sh', 'modify'),
        'repair': ('Run a safe, manual full repair on the node. Can target a specific keyspace/table.', 'full-repair.sh', 'modify'),
        'cleanup': ('Run \'nodetool cleanup\' with safety checks.', 'cleanup-node.sh', 'modify'),
        'compact': ('Run \'nodetool compact\' with safety checks and disk space monitoring.', 'compaction-manager.sh', 'modify'),
        'garbage-collect': ('Run \'nodetool garbagecollect\' with safety checks and disk space monitoring.', 'garbage-collect.sh', 'modify'),
        'upgrade-sstables': ('Run \'nodetool upgradesstables\' with safety checks.', 'upgrade-sstables.sh', 'modify'),
    },
    "Backup & Restore (High-Impact)": {
        'backup': ('Manually trigger a full, node-local backup to S3.', 'full-backup-to-s3.sh', 'modify'),
        'incremental-backup': ('Manually trigger an incremental backup to S3.', 'incremental-backup-to-s3.sh', 'modify'),
        'snapshot': ('Take an ad-hoc snapshot with a generated tag.', 'take-snapshot.sh', 'modify'),
        'restore': ('Restore data from S3. Run without arguments for an interactive wizard.', 'restore-from-s3.sh', 'destructive'),
    },
    "Automation Control": {
        'disable-automation': ('Temporarily disable Puppet and scheduled repair jobs.', 'disable-automation.sh', 'modify'),
        'enable-automation': ('Re-enable Puppet and scheduled repair jobs.', 'enable-automation.sh', 'modify'),
    },
    "Documentation & Testing": {
        'stress': ('Run \'cassandra-stress\' via a robust wrapper.', 'stress-test.sh', 'info'),
        'manual': ('Display the full operations manual in the terminal.', 'cassandra-manual.sh', 'info'),
        'backup-guide': ('Display the full backup and recovery guide.', 'BACKUP_AND_RECOVERY_GUIDE.md', 'less'),
        'puppet-guide': ('Display the Puppet architecture guide.', 'PUPPET_ARCHITECTURE_GUIDE.md', 'less'),
    }
}

# Flatten the categories into a single dictionary for argparse and lookups
ALL_COMMANDS = {cmd: details for category in COMMAND_CATEGORIES.values() for cmd, details in category.items()}


def print_help():
    """Prints a formatted, categorized, and color-coded help message."""
    print(f"{Colors.BOLD}usage: cass-ops [-h] <command> ...{Colors.END}\n")
    print("Unified operations script for Cassandra.\n")
    
    max_len = max(len(k) for k in ALL_COMMANDS.keys())

    for category, commands in COMMAND_CATEGORIES.items():
        print(f"{Colors.BOLD}{Colors.UNDERLINE}{category}{Colors.END}")
        for cmd, (help_text, *_) in sorted(commands.items()):
            
            safety_level = ALL_COMMANDS[cmd][2]
            color = Colors.END
            if safety_level == 'readonly':
                color = Colors.GREEN
            elif safety_level == 'modify':
                color = Colors.YELLOW
            elif safety_level == 'destructive':
                color = Colors.RED
            elif safety_level == 'info':
                color = Colors.CYAN
            
            print(f"  {color}{cmd.ljust(max_len)}{Colors.END}    {help_text}")
        print("")

    print("optional arguments:")
    print(f"  -h, --help            show this help message and exit")
    print(f"\n{Colors.BOLD}Safety Legend:{Colors.END}")
    print(f"  {Colors.GREEN}Read-Only{Colors.END}   - Safe, non-intrusive checks.")
    print(f"  {Colors.YELLOW}Modify{Colors.END}        - Changes state, but generally not data-destructive.")
    print(f"  {Colors.RED}Destructive{Colors.END}   - High-risk. Can alter data or cluster topology.")
    print(f"  {Colors.CYAN}Info/Testing{Colors.END}  - Informational or for test environments.")


def main():
    # --- Root Parser ---
    parser = argparse.ArgumentParser(
        prog='cass-ops',
        description='Unified operations script for Cassandra.',
        add_help=False, # We are using a custom help message
    )
    parser.add_argument('command', help='The command to execute.', choices=ALL_COMMANDS.keys())

    # --- Help Handling ---
    if len(sys.argv) < 2 or sys.argv[1] in ['-h', '--help']:
        print_help()
        sys.exit(0)
    
    command = sys.argv[1]
    
    # --- Check for root privileges based on safety level ---
    cmd_details = ALL_COMMANDS.get(command)
    if not cmd_details:
        print(f"{Colors.RED}Error: Unknown command '{command}'.{Colors.END}")
        sys.exit(1)
        
    safety_level = cmd_details[2]
    
    if os.geteuid() != 0 and safety_level in ['modify', 'destructive']:
        print(f"{Colors.RED}Error: The '{command}' command requires root privileges. Please run with 'sudo'.{Colors.END}")
        sys.exit(1)

    # --- Dispatch to the correct script ---
    script_name = cmd_details[1]
    script_base_dir = os.path.dirname(os.path.realpath(__file__))

    # Handle special cases like documentation viewers
    if len(cmd_details) > 3 and cmd_details[3] == 'less':
        doc_path = os.path.join('/usr/share/doc/cassandra_pfpt', script_name)
        if not os.path.exists(doc_path):
            print(f"{Colors.RED}Error: Documentation file not found at {doc_path}{Colors.END}")
            sys.exit(1)
        subprocess.call(['less', '-R', doc_path])
        sys.exit(0)

    # For all other scripts
    script_path = os.path.join(script_base_dir, script_name)
    if not os.path.exists(script_path):
        print(f"{Colors.RED}Error: Script for command '{command}' not found at {script_path}{Colors.END}")
        sys.exit(1)

    args_to_pass = sys.argv[2:]

    try:
        os.execv(script_path, [script_path] + args_to_pass)
    except Exception as e:
        print(f"{Colors.RED}Error executing script '{script_path}': {e}{Colors.END}")
        sys.exit(1)

if __name__ == '__main__':
    main()
