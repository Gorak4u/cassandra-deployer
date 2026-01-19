
export const sstables = `
## SSTable Upgrades

After a major Cassandra version upgrade (e.g., from 3.x to 4.x), you must run \`nodetool upgradesstables\` on each node to rewrite the SSTables into the new version's format. This profile deploys \`/usr/local/bin/upgrade-sstables.sh\` to manage this process safely.

### Why Use the Script?
The upgrade process writes new SSTables before deleting the old ones, which can significantly increase disk usage. This script performs a pre-flight disk check to ensure there is enough space before starting, preventing potential failures.

### Usage
Run the script sequentially on each node in the cluster, waiting for one to finish before starting the next.

**To upgrade SSTables on the entire node (most common):**
\`\`\`bash
sudo /usr/local/bin/upgrade-sstables.sh
\`\`\`

**To upgrade a specific keyspace:**
\`\`\`bash
sudo /usr/local/bin/upgrade-sstables.sh -k my_app_keyspace
\`\`\`

All output is logged to \`/var/log/cassandra/upgradesstables.log\`.
`.trim();
