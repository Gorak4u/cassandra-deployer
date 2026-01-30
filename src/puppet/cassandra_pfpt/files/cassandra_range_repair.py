#!/usr/bin/env python3
# This file is managed by Puppet.
#
# Original script from https://github.com/BrianGallew/cassandra_range_repair
# This version has been significantly updated to add:
# - Timed repair duration to spread load over a number of hours.
# - A pause/resume mechanism via a file flag.
# - A status file for external monitoring.
# - JMX authentication support.

import subprocess
import sys
import argparse
import logging
import socket
import os
import time
from datetime import datetime

# --- Constants ---
PAUSE_FILE = '/var/lib/repairpaused'
STATUS_DIR = '/var/lib/repair'
STATUS_FILE = os.path.join(STATUS_DIR, 'status.txt')

# --- Global Nodetool Command ---
# This will be populated by command-line args
nodetool_base_command = ['nodetool']

# --- Logging Setup ---
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    stream=sys.stdout
)

# --- Helper Functions ---

def ensure_status_dir():
    """Ensures the directory for the status file exists."""
    if not os.path.exists(STATUS_DIR):
        try:
            logging.info("Creating status directory: %s", STATUS_DIR)
            os.makedirs(STATUS_DIR, exist_ok=True)
            # Set permissions to be world-readable
            os.chmod(STATUS_DIR, 0o755)
        except OSError as e:
            logging.error("Failed to create status directory %s: %s", STATUS_DIR, e)
            sys.exit(1)

def update_status_file(message):
    """Writes a timestamped message to the status file."""
    try:
        with open(STATUS_FILE, 'w') as f:
            f.write(f"[{datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}] {message}\n")
    except IOError as e:
        logging.warning("Could not write to status file %s: %s", STATUS_FILE, e)

def check_for_pause():
    """Checks for the existence of the pause file and waits if it's found."""
    if not os.path.exists(PAUSE_FILE):
        return

    logging.info("Repair paused due to presence of %s. Checking again in 60 seconds.", PAUSE_FILE)
    update_status_file("Repair paused.")
    while os.path.exists(PAUSE_FILE):
        time.sleep(60)
    logging.info("Pause file removed. Resuming repair.")

def get_local_ip():
    """Gets the primary IP address of the local node from nodetool."""
    try:
        status_output = subprocess.check_output(nodetool_base_command + ['status'], text=True)
        for line in status_output.splitlines():
            if len(line) > 0 and (line.startswith('UN') or line.startswith('DN')):
                 parts = line.strip().split()
                 if len(parts) > 1:
                     return parts[1]
        logging.error("Could not parse local IP from 'nodetool status'.")
        return None
    except (subprocess.CalledProcessError, FileNotFoundError, IndexError) as e:
        logging.error("Could not determine local IP address from 'nodetool status'. Error: %s", e)
        return None

def get_token_ranges(local_ip):
    """Gets the token ranges owned by the local node."""
    logging.info("Fetching token ranges for local node: %s", local_ip)
    try:
        ring_output = subprocess.check_output(nodetool_base_command + ['ring'], text=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        logging.error("Failed to run 'nodetool ring'. Is Cassandra running? Error: %s", e)
        return None

    node_tokens = []
    all_tokens = []
    
    for line in ring_output.splitlines():
        parts = line.strip().split()
        if len(parts) < 8:
            continue
        
        token = parts[-1]
        address = parts[0]
        
        try:
            all_tokens.append(int(token))
            if address == local_ip:
                node_tokens.append(int(token))
        except ValueError:
            continue
    
    if not node_tokens:
        logging.warning("Could not find any tokens for IP %s in 'nodetool ring' output.", local_ip)
        return None

    all_tokens = sorted(list(set(all_tokens)))
    node_tokens.sort()
    
    ranges = []
    for token in node_tokens:
        idx = all_tokens.index(token)
        start_token = all_tokens[idx - 1]
        end_token = token
        ranges.append((str(start_token), str(end_token)))

    logging.info("Found %d token ranges for this node.", len(ranges))
    return ranges

def run_repair_for_range(keyspace, start_token, end_token):
    """Runs nodetool repair for a specific keyspace and token range."""
    # The '-pr' (primary range) flag is essential for this strategy
    command = nodetool_base_command + [
        'repair', '-pr',
        '-st', str(start_token),
        '-et', str(end_token),
        '--', keyspace
    ]
    
    logging.info("Executing command: %s", ' '.join(command))
    
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in iter(process.stdout.readline, ''):
            logging.info(line.strip())
        process.stdout.close()
        return_code = process.wait()

        if return_code != 0:
            logging.error("Repair for range (%s, %s] failed with exit code %s.", start_token, end_token, return_code)
        
        return return_code
    except (FileNotFoundError, Exception) as e:
        logging.error("An unexpected error occurred during repair: %s", e)
        return 1

def get_keyspaces():
    """Gets a list of all non-system keyspaces."""
    logging.info("Fetching all non-system keyspaces...")
    try:
        keyspace_output = subprocess.check_output(nodetool_base_command + ['keyspaces'], text=True)
        keyspaces = []
        system_keyspaces = ['system', 'system_auth', 'system_distributed', 'system_schema', 'system_traces', 'system_views', 'system_virtual_schema', 'dse_system', 'dse_perf', 'dse_security', 'solr_admin']
        for ks in keyspace_output.splitlines():
            ks = ks.strip()
            if ks and ks not in system_keyspaces:
                keyspaces.append(ks)
        logging.info("Found keyspaces to repair: %s", keyspaces)
        return keyspaces
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        logging.error("Failed to get keyspaces from nodetool: %s", e)
        return None

def main():
    global nodetool_base_command

    parser = argparse.ArgumentParser(
        description="""A script to perform Cassandra repair on a node by iterating through its primary token ranges.
                       This breaks the repair into smaller chunks to reduce performance impact, with options for timed duration and pausing."""
    )
    parser.add_argument('keyspace', nargs='?', default=None, help='Optional: The name of the keyspace to repair. If not provided, all non-system keyspaces will be repaired one by one.')
    parser.add_argument('--hours', type=float, default=0, help='Optional: The total time in hours the entire repair job should take. If > 0, the script will pause between steps to meet the duration.')
    parser.add_argument('--local-ip', help='The listen_address of this Cassandra node. If not provided, it will be auto-detected.')
    parser.add_argument('--jmx-user', help='JMX username for nodetool authentication.')
    parser.add_argument('--jmx-pass', help='JMX password for nodetool authentication.')
    
    args = parser.parse_args()

    # Build the base nodetool command with auth if provided
    if args.jmx_user and args.jmx_pass:
        nodetool_base_command.extend(['-u', args.jmx_user, '-pw', args.jmx_pass])

    ensure_status_dir()
    update_status_file("Repair process starting.")

    local_ip = args.local_ip or get_local_ip()
    if not local_ip:
        logging.critical("Could not determine local IP. Please specify with --local-ip. Aborting.")
        update_status_file("Failed: Could not determine local IP.")
        sys.exit(1)
        
    token_ranges = get_token_ranges(local_ip)
    if not token_ranges:
        logging.error("No token ranges found for node %s. Aborting repair.", local_ip)
        update_status_file("Failed: No token ranges found.")
        sys.exit(1)
        
    keyspaces_to_repair = [args.keyspace] if args.keyspace else get_keyspaces()
    if not keyspaces_to_repair:
        logging.critical("Could not fetch list of keyspaces to repair. Aborting.")
        update_status_file("Failed: No keyspaces found to repair.")
        sys.exit(1)

    logging.info("--- Starting Granular Repair on node %s ---", local_ip)

    total_steps = len(token_ranges) * len(keyspaces_to_repair)
    time_per_step_seconds = (args.hours * 3600 / total_steps) if args.hours > 0 and total_steps > 0 else 0
    
    if time_per_step_seconds > 0:
        logging.info("Repair job timed to complete in %.2f hours. Time per step: ~%d seconds.", args.hours, int(time_per_step_seconds))

    step_counter = 0
    overall_failures = 0
    
    for ks in keyspaces_to_repair:
        logging.info("--- Preparing to repair keyspace: %s ---", ks)
        failures_in_ks = 0
        for i, (start, end) in enumerate(token_ranges):
            check_for_pause()
            
            step_start_time = time.time()
            
            logging.info("--- Repairing keyspace '%s', range %d of %d: (%s, %s] ---", ks, i + 1, len(token_ranges), start, end)
            exit_code = run_repair_for_range(ks, start, end)
            
            step_counter += 1
            progress_message = f"{step_counter}/{total_steps} steps complete for node."
            update_status_file(progress_message)

            if exit_code != 0:
                failures_in_ks += 1
                logging.warning("Failed to repair a range for keyspace '%s'. Continuing with next range...", ks)
            
            if time_per_step_seconds > 0:
                elapsed_time = time.time() - step_start_time
                wait_time = time_per_step_seconds - elapsed_time
                if wait_time > 0:
                    logging.info("Waiting for %d seconds to maintain scheduled pace.", int(wait_time))
                    time.sleep(wait_time)
        
        if failures_in_ks > 0:
            overall_failures += 1
            logging.error("%d of %d ranges failed to repair for keyspace '%s'.", failures_in_ks, len(token_ranges), ks)
        else:
            logging.info("All %d ranges repaired successfully for keyspace '%s'.", len(token_ranges), ks)

    logging.info("--- Granular Repair Process Finished ---")
    if overall_failures > 0:
        error_msg = f"Failed: Repair failed for {overall_failures} keyspace(s)."
        logging.error(error_msg)
        update_status_file(error_msg)
        sys.exit(1)
    
    success_msg = "Success: All specified keyspaces were repaired successfully."
    logging.info(success_msg)
    update_status_file(success_msg)
    sys.exit(0)

if __name__ == '__main__':
    main()
