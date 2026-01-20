
export const tasks = {
      'nodetool.json': `
{
  "description": "Run a nodetool command on a Cassandra node.",
  "input_method": "stdin",
  "parameters": {
    "command": {
      "description": "The nodetool command to run (e.g., 'status', 'info', 'describecluster').",
      "type": "String[1]"
    }
  }
}
`.trim(),
      'nodetool.sh': `#!/bin/bash
# Puppet Task to run a nodetool command

# The command is passed as a JSON object on stdin
if ! read -r cmd_json; then
  echo "Failed to read command from stdin"
  exit 1
fi

# Extract the command parameter from the JSON input
# We use jq for robust JSON parsing
COMMAND=\\$(echo "\\$cmd_json" | /usr/bin/jq -r '.command')

if [ -z "\\$COMMAND" ]; then
  echo "Error: 'command' parameter not provided in JSON input."
  exit 1
fi

# Basic security check: prevent running commands that could be destructive
# This is a simple blacklist. In a real-world scenario, you might prefer a whitelist.
if [[ "\\$COMMAND" =~ ^(stop|decommission|removenode|move|assassinate) ]]; then
  echo "Error: Destructive commands like '\\$COMMAND' are not permitted via this task."
  exit 1
fi

# Execute the nodetool command
# Ensure nodetool is in the path
export PATH=\\$PATH:/usr/bin:/usr/sbin

nodetool \\$COMMAND
exit \\$?
`.trim(),
    };

    
