#!/bin/bash
# Wrapper script for Cassandra token range repair.
# Runs the python script and waits for a specified interval.

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

PYTHON_SCRIPT="/usr/local/bin/cassandra_range_repair.py"
LOCK_FILE="/var/run/range-repair.lock"
REPAIR_INTERVAL_DAYS=5 # Run repair every 5 days
REPAIR_INTERVAL_SECONDS=$((REPAIR_INTERVAL_DAYS * 24 * 60 * 60))

# Ensure only one instance of the script runs
if [ -f "$LOCK_FILE" ]; then
    log_message "Lock file exists ($LOCK_FILE). Another instance might be running or exited improperly. Exiting."
    exit 1
fi
trap "rm -f $LOCK_FILE" EXIT
touch "$LOCK_FILE"

log_message "Starting Cassandra range repair service loop."

while true; do
    START_TIME=$(date +%s)
    log_message "Initiating token range repair."

    # Run the Python repair script
    if "$PYTHON_SCRIPT"; then
        log_message "Token range repair completed successfully."
    else
        log_message "Token range repair FAILED. Will retry after interval."
    fi

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    SLEEP_DURATION=$((REPAIR_INTERVAL_SECONDS - DURATION))

    if [ "$SLEEP_DURATION" -le 0 ]; then
        log_message "Repair duration ($DURATION s) exceeded or matched interval ($REPAIR_INTERVAL_SECONDS s). Running next repair immediately."
        SLEEP_DURATION=10 # Sleep a small amount to prevent busy loop if repair is very fast
    fi

    log_message "Repair cycle finished in $DURATION seconds. Sleeping for $SLEEP_DURATION seconds."
    sleep "$SLEEP_DURATION"
done