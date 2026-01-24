#!/usr/bin/env python3
# This file is managed by Puppet.

import subprocess
import sys
import argparse
import logging
import socket

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    stream=sys.stdout
)

def get_local_ip():
    """Gets the primary IP address of the local node from nodetool."""
    try:
        status_output = subprocess.check_output(['nodetool', 'status'], text=True)
        for line in status_output.splitlines():
            # Status can be UN, UJ, UL, DN, DJ, DL etc. Look for U(p) or D(own) at the start of the line.
            if len(line) > 0 and (line[0] == 'U' or line[0] == 'D'):
                 parts = line.strip().split()
                 # Address is the second column
                 if len(parts) > 1:
                     # This should be the local node if run on the box.
                     return parts[1]
        logging.error("Could not parse local IP from 'nodetool status'.")
        return None
    except (subprocess.CalledProcessError, FileNotFoundError, IndexError) as e:
        logging.error(f"Could not determine local IP address from 'nodetool status'. Error: {e}")
        return None


def get_token_ranges(local_ip):
    """Gets the token ranges owned by the local node."""
    logging.info("Fetching token ranges for local node: %s", local_ip)
    try:
        ring_output = subprocess.check_output(['nodetool', 'ring'], text=True)
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
            # check if last part is a number (token)
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
        # The start token is the one before it in the sorted list of all ring tokens.
        # Wrap around for the first token in the ring.
        start_token = all_tokens[idx - 1]
        end_token = token
        ranges.append((str(start_token), str(end_token)))

    logging.info("Found %d token ranges for this node.", len(ranges))
    return ranges


def run_repair_for_range(keyspace, start_token, end_token):
    """Runs nodetool repair for a specific keyspace and token range."""
    
    command = [
        'nodetool',
        'repair',
        '-st', str(start_token),
        '-et', str(end_token),
        '--', keyspace
    ]
    
    logging.info("Executing command: %s", ' '.join(command))
    
    try:
        # Stream output in real time
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
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
        keyspace_output = subprocess.check_output(['nodetool', 'keyspaces'], text=True)
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
    parser = argparse.ArgumentParser(
        description="""A script to perform Cassandra repair on a node by iterating through its primary token ranges. 
                       This breaks the repair into smaller chunks to reduce performance impact."""
    )
    parser.add_argument('keyspace', nargs='?', default=None, help='Optional: The name of the keyspace to repair. If not provided, all non-system keyspaces will be repaired one by one.')
    parser.add_argument('--local-ip', help='The listen_address of this Cassandra node. If not provided, it will be auto-detected.')
    
    args = parser.parse_args()

    local_ip = args.local_ip if args.local_ip else get_local_ip()
    
    if not local_ip:
        logging.critical("Could not determine local IP. Please specify with --local-ip. Aborting.")
        sys.exit(1)
        
    token_ranges = get_token_ranges(local_ip)
    if not token_ranges:
        logging.error("No token ranges found for node %s. Aborting repair.", local_ip)
        sys.exit(1)
        
    keyspaces_to_repair = []
    if args.keyspace:
        keyspaces_to_repair.append(args.keyspace)
    else:
        logging.info("No keyspace specified, will repair all non-system keyspaces.")
        keyspaces_to_repair = get_keyspaces()
        if keyspaces_to_repair is None:
            logging.critical("Could not fetch list of keyspaces. Aborting.")
            sys.exit(1)

    logging.info("--- Starting Granular Repair on node %s ---", local_ip)
    
    overall_failures = 0
    for ks in keyspaces_to_repair:
        logging.info("--- Preparing to repair keyspace: %s ---", ks)
        total_ranges = len(token_ranges)
        failures = 0
        for i, (start, end) in enumerate(token_ranges):
            logging.info("--- Repairing keyspace '%s', range %d of %d: (%s, %s] ---", ks, i + 1, total_ranges, start, end)
            exit_code = run_repair_for_range(ks, start, end)
            if exit_code != 0:
                failures += 1
                logging.warning("Failed to repair a range for keyspace '%s'. Continuing with next range...", ks)
        
        if failures > 0:
            overall_failures +=1
            logging.error("%d of %d ranges failed to repair for keyspace '%s'.", failures, total_ranges, ks)
        else:
            logging.info("All %d ranges repaired successfully for keyspace '%s'.", total_ranges, ks)

    logging.info("--- Granular Repair Process Finished ---")
    if overall_failures > 0:
        logging.error("Repair failed for %d keyspace(s). Please check the logs.", overall_failures)
        sys.exit(1)
    
    logging.info("All specified keyspaces were repaired successfully.")
    sys.exit(0)

if __name__ == '__main__':
    main()
