
export const compaction = `
## Compaction Management

This profile deploys an intelligent script, \`/usr/local/bin/compaction-manager.sh\`, to help operators safely run manual compactions while monitoring disk space.

### Why Use the Compaction Manager?
Running a manual compaction (\`nodetool compact\`) can consume a significant amount of disk space temporarily. If a node runs out of space during compaction, it can lead to a critical failure. The \`compaction-manager.sh\` script prevents this by running the compaction process in the background while periodically checking disk space. If the free space drops below a critical threshold, it automatically stops the compaction process to prevent a disk-full error.

### Usage

The script can be run to target a specific table, an entire keyspace, or the whole node.

**To compact a specific table:**
\`\`\`bash
sudo /usr/local/bin/compaction-manager.sh --keyspace my_app --table users
\`\`\`

**To compact an entire keyspace:**
\`\`\`bash
sudo /usr/local/bin/compaction-manager.sh --keyspace my_app
\`\`\`

**To compact all keyspaces on a node:**
\`\`\`bash
sudo /usr/local/bin/compaction-manager.sh
\`\`\`

You can customize its behavior with flags:
*   \`--critical <percent>\`: Sets the critical free space percentage to abort at (Default: 15).
*   \`--interval <seconds>\`: Sets how often to check the disk (Default: 30).

All output and progress are logged to \`/var/log/cassandra/compaction_manager.log\`.

### Performing a Rolling Compaction (DC or Cluster-wide)

The \`compaction-manager.sh\` script operates on a single node. To perform a safe, rolling compaction across an entire datacenter or cluster, you should run the script sequentially on each node.

**Procedure:**
1.  SSH into the first node in the datacenter.
2.  Run the desired compaction command (e.g., \`sudo /usr/local/bin/compaction-manager.sh -k my_keyspace\`).
3.  Monitor the log file (\`tail -f /var/log/cassandra/compaction_manager.log\`) until the script reports "Compaction Manager Finished Successfully".
4.  Move to the next node in the datacenter and repeat steps 2-3.
5.  Continue this process until all nodes in the target group have been compacted.
`.trim();
