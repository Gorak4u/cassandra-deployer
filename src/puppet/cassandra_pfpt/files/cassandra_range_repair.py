#!/usr/bin/env python3
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
