#!/bin/bash
# This file is managed by Puppet.
# Description: Audit script to check and print versions of various components.

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $(basename "$0") [-h|--help]"
    echo ""
    echo "Options:"
    echo "  -h, --help    Display this help message"
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
    shift
done

log_version() {
    local component_name="$1"
    local command_to_run="$2"
    local output

    echo -e "${BLUE}--- Checking $component_name ---${NC}"
    if command -v $(echo "$command_to_run" | awk '{print $1}') >/dev/null 2>&1; then
        output=$(eval "$command_to_run" 2>&1)
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Version:${NC}"
            echo "$output" | head -n 5 # Limit output to relevant lines
        else
            echo -e "${RED}Error running command for $component_name: $output${NC}"
        fi
    else
        echo -e "${RED}$component_name command not found: $(echo "$command_to_run" | awk '{print $1}')${NC}"
    fi
    echo ""
}

log_version "Operating System" "cat /etc/os-release"
log_version "Kernel" "uname -r"
log_version "Puppet" "puppet -V"
log_version "Java" "java -version"
log_version "Cassandra (nodetool)" "nodetool version"
log_version "Python" "python3 --version || python --version"
