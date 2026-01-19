
export const cleanup = `
## Node Cleanup

When the token ring changes (e.g., a node is added to the cluster), you must run \`nodetool cleanup\` on existing nodes. This process removes data that no longer belongs to that node according to the new token assignments. This profile deploys \`/usr/local/bin/cleanup-node.sh\` to run this operation safely.

### Why Use the Script?
Running \`cleanup\` can be resource-intensive. This script provides a wrapper that adds pre-flight disk space checks to ensure the operation doesn't start on a node that is already low on space.

### Usage
\`cleanup\` should be run on a node *after* a new node has fully bootstrapped into the same datacenter. Run it sequentially on each existing node.

**To clean up the entire node:**
\`\`\`bash
sudo /usr/local/bin/cleanup-node.sh
\`\`\`

**To clean up a specific keyspace:**
\`\`\`bash
sudo /usr/local/bin/cleanup-node.sh -k my_app_keyspace
\`\`\`

All output is logged to \`/var/log/cassandra/cleanup.log\`.
`.trim();
