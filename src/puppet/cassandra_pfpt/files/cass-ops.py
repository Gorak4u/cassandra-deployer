#!/usr/bin/env python3
# This file is managed by Puppet.
#
# Unified operations script for Cassandra.
# This script acts as a dispatcher for various management and operational scripts.

import sys
import os
import argparse
import subprocess

# --- Command Definitions ---
# Maps a command name to its script file and a help description.
COMMANDS = {
    # Health & Status
    'health': ('Run a comprehensive health check on the local node.', 'node_health_check.sh'),
    'cluster-health': ('Quickly check cluster connectivity and nodetool status.', 'cluster-health.sh'),
    'disk-health': ('Check disk usage against warning/critical thresholds.', 'disk-health-check.sh'),
    'version': ('Audit and print versions of key software (OS, Java, Cassandra).', 'version-check.sh'),
    'backup-status': ('Check the status of the last completed backup for a node.', 'backup-status.sh'),
    'backup-verify': ('Verify the integrity and restorability of the latest backup set.', 'verify-backup.sh'),

    # Node Lifecycle
    'stop': ('Safely drain and stop the Cassandra service.', 'stop-node.sh'),
    'restart': ('Perform a safe, rolling restart of the Cassandra service.', 'rolling_restart.sh'),
    'reboot': ('Safely drain Cassandra and reboot the machine.', 'reboot-node.sh'),
    'drain': ('Drain the node, flushing memtables and stopping client traffic.', 'drain-node.sh'),
    'decommission': ('Permanently remove this node from the cluster after streaming its data.', 'decommission-node.sh'),
    'replace': ('Configure this NEW, STOPPED node to replace a dead node.', 'prepare-replacement.sh'),
    'assassinate': ('Forcibly remove a dead node from the cluster\'s gossip ring.', 'assassinate-node.sh'),
    'rebuild': ('Rebuild the data on this node by streaming from another datacenter.', 'rebuild-node.sh'),

    # Data & Maintenance
    'repair': ('Run a safe, manual full repair on the node. Can target a specific keyspace/table.', 'full-repair.sh'),
    'cleanup': ('Run \'nodetool cleanup\' with safety checks.', 'cleanup-node.sh'),
    'compact': ('Run \'nodetool compact\' with safety checks and advanced options.', 'compaction-manager.sh'),
    'garbage-collect': ('Run \'nodetool garbagecollect\' with safety checks.', 'garbage-collect.sh'),
    'upgrade-sstables': ('Run \'nodetool upgradesstables\' with safety checks.', 'upgrade-sstables.sh'),
    
    # Backup & Restore
    'backup': ('Manually trigger a full, node-local backup to S3.', 'full-backup-to-s3.sh'),
    'incremental-backup': ('Manually trigger an incremental backup to S3.', 'incremental-backup-to-s3.sh'),
    'snapshot': ('Take an ad-hoc snapshot with a generated tag.', 'take-snapshot.sh'),
    'restore': ('Restore data from S3. Run without arguments for an interactive wizard.', 'restore-from-s3.sh'),

    # Testing & Documentation
    'stress': ('Run \'cassandra-stress\' via a robust wrapper.', 'stress-test.sh'),
    'manual': ('Display the full operations manual in the terminal.', 'cassandra-manual.sh'),
    'upgrade-check': ('Run pre-flight checks before a major version upgrade.', 'cassandra-upgrade-precheck.sh'),
    'backup-guide': ('Display the full backup and recovery guide.', 'BACKUP_AND_RECOVERY_GUIDE.md', 'less'),
    'puppet-guide': ('Display the Puppet architecture guide.', 'PUPPET_ARCHITECTURE_GUIDE.md', 'less'),
}

def main():
    # --- Root Parser ---
    # Manually construct help text to match the desired format
    command_list = "{" + ",".join(sorted(COMMANDS.keys())) + "}"
    
    parser = argparse.ArgumentParser(
        prog='cass-ops',
        description='Unified operations script for Cassandra.',
        usage=f'cass-ops [-h] <command> ...',
        formatter_class=argparse.RawTextHelpFormatter,
    )
    
    # This is a bit of a trick to get the desired output format without a title
    parser.add_argument('command', help=f'The command to execute.\n\nAvailable Commands:\n {command_list}', choices=COMMANDS.keys())

    # --- Parse only the first argument to identify the command ---
    if len(sys.argv) < 2 or sys.argv[1] in ['-h', '--help']:
        # Generate detailed help text dynamically
        print(f"usage: cass-ops [-h] <command> ...\n")
        print("Unified operations script for Cassandra.\n")
        print("Available Commands:")
        # Find the longest command name for alignment
        max_len = max(len(k) for k in COMMANDS.keys())
        print(f"  {command_list}\n")
        for cmd, (help_text, *_) in sorted(COMMANDS.items()):
            print(f"  {cmd.ljust(max_len)}    {help_text}")
        
        print("\noptional arguments:")
        print("  -h, --help            show this help message and exit")
        sys.exit(0)
    
    command = sys.argv[1]
    
    # --- Check for root privileges ---
    if os.geteuid() != 0:
        safe_commands = ['manual', 'backup-guide', 'puppet-guide', 'version', 'cluster-health', 'backup-status', 'restore']
        if command not in safe_commands:
            print(f"\033[0;31mError: This operation requires root privileges. Please run with 'sudo'.\033[0m")
            sys.exit(1)

    # --- Dispatch to the correct script ---
    cmd_config = COMMANDS[command]
    script_name = cmd_config[1]
    script_base_dir = os.path.dirname(os.path.realpath(__file__))

    # Handle special cases like documentation viewers
    if len(cmd_config) > 2 and cmd_config[2] == 'less':
        doc_path = os.path.join('/usr/share/doc/cassandra_pfpt', script_name)
        if not os.path.exists(doc_path):
            print(f"\033[0;31mError: Documentation file not found at {doc_path}\033[0m")
            sys.exit(1)
        subprocess.call(['less', '-R', doc_path])
        sys.exit(0)

    # For all other scripts
    script_path = os.path.join(script_base_dir, script_name)
    if not os.path.exists(script_path):
        print(f"\033[0;31mError: Script for command '{command}' not found at {script_path}\033[0m")
        sys.exit(1)

    args_to_pass = sys.argv[2:]

    try:
        os.execv(script_path, [script_path] + args_to_pass)
    except Exception as e:
        print(f"\033[0;31mError executing script '{script_path}': {e}\033[0m")
        sys.exit(1)

if __name__ == '__main__':
    main()
