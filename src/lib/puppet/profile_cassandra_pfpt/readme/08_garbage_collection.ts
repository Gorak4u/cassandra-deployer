
export const garbage_collection = `
## Garbage Collection

Similar to compaction, running a manual garbage collection can be managed safely using the \`/usr/local/bin/garbage-collect.sh\` script. This script is a wrapper around \`nodetool garbagecollect\` that provides important safety checks and targeting options.

### Why Use the Garbage Collection Script?
While less disk-intensive than a full compaction, running garbage collection still benefits from a pre-flight check to ensure the node has sufficient disk space before starting. The script prevents you from initiating the operation on a disk that is already nearing capacity.

### Usage
The script allows you to target the entire node, a specific keyspace, or one or more tables.

**To run garbage collection on the entire node:**
\`\`\`bash
sudo /usr/local/bin/garbage-collect.sh
\`\`\`

**To run on a specific keyspace:**
\`\`\`bash
sudo /usr/local/bin/garbage-collect.sh -k my_keyspace
\`\`\`

**To run on multiple tables within a keyspace:**
\`\`\`bash
sudo /usr/local/bin/garbage-collect.sh -k my_app -t users -t audit_log
\`\`\`

You can customize its behavior with flags:
*   \`-g, --granularity <CELL|ROW>\`: Sets the granularity of tombstones to remove (Default: \`ROW\`).
*   \`-j, --jobs <num>\`: Sets the number of concurrent sstable garbage collection jobs (Default: 0 for auto).
*   \`-w, --warning <percent>\`: Sets the warning free space percentage to abort at (Default: 30).
*   \`-c, --critical <percent>\`: Sets the critical free space percentage to abort at (Default: 20).

### Performing a Rolling Garbage Collection
To perform a safe, rolling garbage collection across an entire datacenter or cluster, you should run the script sequentially on each node, similar to the process for compaction. Wait for the script to complete successfully on one node before moving to the next.
`.trim();
