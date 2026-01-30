#!/bin/bash
# This file is managed by Puppet.

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

show_description() {
(
echo -e "${BOLD}${BLUE}## Description${NC}"
echo -e ""
echo -e "This profile includes the \`cassandra_pfpt\` component module and provides it with a rich set of operational capabilities through Hiera-driven configuration and a suite of robust management scripts. The primary entry point for all operations is the \`cass-ops\` command-line tool, installed in \`/usr/local/bin\`."
) | less -R
}

show_setup() {
(
echo -e "${BOLD}${BLUE}## Setup${NC}"
echo -e ""
echo -e "This profile is intended to be included by a role class."
echo -e ""
echo -e "${CYAN}\`\`\`puppet"
echo -e "# In your role manifest (e.g., roles/manifests/cassandra.pp)"
echo -e "class role::cassandra {"
echo -e "  include profile_cassandra_pfpt"
echo -e "}"
echo -e "\`\`\`${NC}"
echo -e ""
echo -e "> All configuration for the node should be provided via your Hiera data source (e.g., in your \`common.yaml\` or node-specific YAML files). The backup scripts require the \`jq\`, \`awscli\`, and \`openssl\` packages, which this profile will install by default. The \`cass-ops\` tool also requires \`python3-colorama\` for color-coded output, which is also managed by the module."
) | less -R
}

show_usage_examples() {
(
echo -e "${BOLD}${BLUE}## Usage Examples${NC}"
echo -e ""
echo -e "${BOLD}${BLUE}### Comprehensive Configuration Example${NC}"
echo -e ""
echo -e "The following Hiera example demonstrates how to configure a multi-node cluster with automated backups, scheduled repairs, and custom JVM settings enabled."
echo -e ""
echo -e "${CYAN}\`\`\`yaml"
echo -e "# In your Hiera data (e.g., nodes/cassandra-node-1.yaml)"
echo -e ""
echo -e "# --- Core Settings ---"
echo -e "profile_cassandra_pfpt::cluster_name: 'MyProductionCluster'"
echo -e "profile_cassandra_pfpt::cassandra_password: 'a-very-secure-password'"
echo -e ""
echo -e "# --- Topology & Seeds ---"
echo -e "profile_cassandra_pfpt::datacenter: 'dc1'"
echo -e "profile_cassandra_pfpt::rack: 'rack1'"
echo -e "profile_cassandra_pfpt::seeds:"
echo -e "  - '10.0.1.10'"
echo -e "  - '10.0.1.11'"
echo -e "  - '10.0.1.12'"
echo -e ""
echo -e "# --- JVM Settings ---"
echo -e "profile_cassandra_pfpt::max_heap_size: '8G'"
echo -e "profile_cassandra_pfpt::jvm_additional_opts:"
echo -e "  'print_flame_graphs': '-XX:+PreserveFramePointer'"
echo -e ""
echo -e "# --- Backup Configuration ---"
echo -e "profile_cassandra_pfpt::backup_encryption_key: 'Your-Super-Secret-32-Character-Key' # IMPORTANT: Use Hiera-eyaml for this in production"
echo -e "profile_cassandra_pfpt::manage_full_backups: true"
echo -e "profile_cassandra_pfpt::full_backup_schedule: '0 2 * * *' # cron spec"
echo -e "profile_cassandra_pfpt::manage_incremental_backups: true"
echo -e "profile_cassandra_pfpt::incremental_backup_schedule: '0 */4 * * *' # cron spec"
echo -e "profile_cassandra_pfpt::backup_s3_bucket: 'my-prod-cassandra-backups'"
echo -e "profile_cassandra_pfpt::clearsnapshot_keep_days: 7"
echo -e "profile_cassandra_pfpt::s3_retention_period: 30 # Keep backups in S3 for 30 days"
echo -e "profile_cassandra_pfpt::upload_streaming: false # Set to true to use faster but less-robust streaming uploads"
echo -e ""
echo -e "# --- Automated Repair Configuration ---"
echo -e "profile_cassandra_pfpt::manage_scheduled_repair: true"
echo -e "profile_cassandra_pfpt::repair_schedule: '*-*-1/5 01:00:00' # Every 5 days"
echo -e "\`\`\`${NC}"
echo -e ""
echo -e "${BOLD}${BLUE}### Managing Cassandra Roles${NC}"
echo -e ""
echo -e "You can declaratively manage Cassandra user roles. For production environments, it is highly recommended to encrypt passwords using ${BOLD}Hiera-eyaml${NC}. The profile supports this automatically, as Puppet will decrypt the secrets before passing them to the module."
echo -e ""
echo -e "Here is an example showing both a plain-text password and an encrypted one:"
echo -e ""
echo -e "${CYAN}\`\`\`yaml"
echo -e "# In your Hiera data"
echo -e "profile_cassandra_pfpt::cassandra_roles:"
echo -e "  # Example with a plain-text password (suitable for development)"
echo -e "  'readonly_user':"
echo -e "    password: 'SafePassword123'"
echo -e "    is_superuser: false"
echo -e "    can_login: true"
echo -e ""
echo -e "  # Example with a securely encrypted password using eyaml (for production)"
echo -e "  'app_admin':"
echo -e "    password: >"
echo -e "      ENC[PKCS7,MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAq3s4/L5W"
echo -e "      ... (rest of your encrypted string) ..."
echo -e "      9y9gBFdCIg4a5A==]"
echo -e "    is_superuser: true"
echo -e "    can_login: true"
echo -e "\`\`\`${NC}"
) | less -R
}

show_quick_reference() {
(
echo -e "${BOLD}${BLUE}## Operator's Quick Reference: The \`cass-ops\` Command${NC}"
echo -e ""
echo -e "This profile installs a unified administrative wrapper script, \`cass-ops\`, at \`/usr/local/bin\`. This is your primary entry point for all manual and automated operational tasks. It simplifies management by providing a single, memorable command with clear, grouped sub-commands."
echo -e ""
echo -e "To see all available commands, simply run it with no arguments:"
echo -e ""
echo -e "${CYAN}\`\`\`bash"
echo -e "$ sudo /usr/local/bin/cass-ops"
echo -e "\`\`\`${NC}"
echo -e "This will display the full, formatted help text with all commands grouped by category."
echo -e ""
echo -e "> ${BOLD}Note on legacy scripts:${NC} The original \`cassandra-admin.sh\` script is also available for manual use if needed, but \`cass-ops\` is the primary and recommended tool for all operations."

) | less -R
}

show_day2_ops() {
(
echo -e "${BOLD}${BLUE}## Day-2 Operations Guide${NC}"
echo -e ""
echo -e "This section provides a practical guide for common operational tasks."
echo -e ""
echo -e "${BOLD}${BLUE}### Node and Cluster Health Checks${NC}"
echo -e ""
echo -e "> Before performing any maintenance, always check the health of the node and cluster."
echo -e ""
echo -e "*   ${BOLD}Check the Local Node:${NC} Run \`sudo /usr/local/bin/cass-ops health\`. This script is your first stop. It checks disk space, node status (UN), gossip state, active streams, and recent log exceptions, giving you a quick \"go/no-go\" for maintenance."
echo -e "*   ${BOLD}Check Cluster Connectivity:${NC} Run \`sudo /usr/local/bin/cass-ops cluster-health\`. This verifies that the node can communicate with the cluster and that the CQL port is open."
echo -e "*   ${BOLD}Check Disk Space Manually:${NC} Run \`sudo /usr/local/bin/cass-ops disk-health\` to see the current free space percentage on the data volume."
echo -e ""
echo -e "${BOLD}${BLUE}### Node Lifecycle Management${NC}"
echo -e ""
echo -e "${BOLD}#### Performing a Safe Rolling Restart${NC}"
echo -e "To apply configuration changes or for other maintenance, always use the provided script for a safe restart."
echo -e ""
echo -e "1.  SSH into the node you wish to restart."
echo -e "2.  Execute \`sudo /usr/local/bin/cass-ops restart\`."
echo -e "3.  The script will automatically drain the node, stop the service, start it again, and wait until it verifies the node has successfully rejoined the cluster in \`UN\` state."
echo -e ""
echo -e "${BOLD}#### Decommissioning a Node${NC}"
echo -e "When you need to permanently remove a node from the cluster:"
echo -e ""
echo -e "1.  SSH into the node you want to remove."
echo -e "2.  Run \`sudo /usr/local/bin/cass-ops decommission\`."
echo -e "3.  The script will ask for confirmation, then run \`nodetool decommission\`. After it completes successfully, it is safe to shut down and terminate the instance."
echo -e ""
echo -e "${BOLD}#### Replacing a Failed Node${NC}"
echo -e "If a node has failed permanently and cannot be recovered, you must replace it with a new one."
echo -e ""
echo -e "1.  Provision a new machine with the same resources and apply this Puppet profile. ${BOLD}Do not start the Cassandra service.${NC}"
echo -e "2.  SSH into the ${BOLD}new, stopped${NC} node."
echo -e "3.  Execute the \`replace\` command, providing the IP of the dead node it is replacing:"
echo -e "    ${CYAN}\`\`\`bash"
echo -e "    sudo /usr/local/bin/cass-ops replace <ip_of_dead_node>"
echo -e "    \`\`\`${NC}"
echo -e "4.  The script will configure the necessary JVM flag (\`-Dcassandra.replace_address_first_boot\`)."
echo -e "5.  You can now ${BOLD}start the Cassandra service${NC} on the new node. It will automatically bootstrap into the cluster, assuming the identity and token ranges of the dead node."
echo -e ""
echo -e "${BOLD}${BLUE}### Data and Maintenance Operations${NC}"
echo -e ""
echo -e "${BOLD}#### Manually Repairing Data${NC}"
echo -e "Use this command to run a direct, blocking, manual repair. This is useful for ad-hoc data consistency checks but can be resource-intensive. The automated, scheduled repair is the primary mechanism for maintaining data consistency."
echo -e ""
echo -e "*   ${BOLD}To manually repair all non-system keyspaces:${NC}"
echo -e "    ${CYAN}\`\`\`bash"
echo -e "    sudo /usr/local/bin/cass-ops repair"
echo -e "    \`\`\`${NC}"
echo -e "*   ${BOLD}To manually repair a specific keyspace:${NC}"
echo -e "    ${CYAN}\`\`\`bash"
echo -e "    sudo /usr/local/bin/cass-ops repair my_keyspace"
echo -e "    \`\`\`${NC}"
echo -e ""
echo -e "${BOLD}#### Compaction${NC}"
echo -e "To manually trigger compaction while safely monitoring disk space:"
echo -e ""
echo -e "${CYAN}\`\`\`bash"
echo -e "# Compact a specific table"
echo -e "sudo /usr/local/bin/cass-ops compact -k my_keyspace -t my_table"
echo -e ""
echo -e "# Compact an entire keyspace"
echo -e "sudo /usr/local/bin/cass-ops compact -k my_keyspace"
echo -e "\`\`\`${NC}"
echo -e ""
echo -e "${BOLD}#### Garbage Collection${NC}"
echo -e "To manually remove droppable tombstones with pre-flight safety checks:"
echo -e ""
echo -e "${CYAN}\`\`\`bash"
echo -e "sudo /usr/local/bin/cass-ops garbage-collect -k my_keyspace -t users"
echo -e "\`\`\`${NC}"
echo -e ""
echo -e "${BOLD}#### SSTable Upgrades${NC}"
echo -e "After a major Cassandra version upgrade, run this on each node sequentially:"
echo -e ""
echo -e "${CYAN}\`\`\`bash"
echo -e "sudo /usr/local/bin/cass-ops upgrade-sstables"
echo -e "\`\`\`${NC}"
echo -e ""
echo -e "${BOLD}#### Node Cleanup${NC}"
echo -e "After adding a new node to the cluster, run \`cleanup\` on the existing nodes in the same DC to remove data that no longer belongs to them."
echo -e ""
echo -e "${CYAN}\`\`\`bash"
echo -e "sudo /usr/local/bin/cass-ops cleanup"
echo -e "\`\`\`${NC}"
) | less -R
}

show_automated_maintenance() {
(
echo -e "${BOLD}${BLUE}## Automated Maintenance Guide${NC}"
echo -e ""
echo -e "${BOLD}${BLUE}### Automated Backups${NC}"
echo -e ""
echo -e "This profile provides a fully automated, S3-based backup solution using \`cron\`."
echo -e ""
echo -e "${BOLD}#### How It Works${NC}"
echo -e "1.  ${BOLD}Granular Backups:${NC} Backups are no longer single, large archives. Instead, each table (for full backups) or set of incremental changes is archived and uploaded as a small, separate file to S3."
echo -e "2.  ${BOLD}Scheduling:${NC} Puppet creates \`cron\` job files in \`/etc/cron.d/\` on each node."
echo -e "3.  ${BOLD}Execution:${NC} \`cron\` automatically triggers the backup scripts via \`cass-ops\`."
echo -e "4.  ${BOLD}Process:${NC} The scripts generate a \`backup_manifest.json\` with critical metadata for each backup run (identified by a \`YYYY-MM-DD-HH-MM\` timestamp), encrypt the archives, and upload them to a structured path in S3."
echo -e "5.  ${BOLD}Local Snapshot Cleanup:${NC} The full backup script automatically deletes local snapshots older than \`clearsnapshot_keep_days\`."
echo -e "6.  ${BOLD}S3 Lifecycle Management:${NC} The full backup script also ensures an S3 lifecycle policy is in place on the bucket to automatically delete old backups after the \`s3_retention_period\`."
echo -e ""
echo -e "${BOLD}#### Pausing Backups${NC}"
echo -e "> To temporarily disable backups on a node for maintenance, create a flag file:"
echo -e "> \`sudo touch /var/lib/backup-disabled\`."
echo -e "> To re-enable, simply remove the file."
echo -e ""
echo -e "${BOLD}${BLUE}### Automated Repair${NC}"
echo -e ""
echo -e "A safe, low-impact, automated repair process is critical for data consistency."
echo -e ""
echo -e "${BOLD}#### How it Works${NC}"
echo -e "1.  ${BOLD}Configuration:${NC} Enable via \`profile_cassandra_pfpt::manage_scheduled_repair: true\`."
echo -e "2.  ${BOLD}Scheduling:${NC} Puppet creates a \`systemd\` timer (\`cassandra-repair.timer\`) that, by default, runs every 5 days to align with a 10-day \`gc_grace_seconds\`."
echo -e "3.  ${BOLD}Execution:${NC} The timer runs \`range-repair.sh\`, which executes the intelligent Python script to repair the node in small, manageable chunks, minimizing performance impact."
echo -e "4.  ${BOLD}Control:${NC} You can manually stop, start, or check the status of a repair using \`systemd\` commands:"
echo -e "    *   \`sudo systemctl stop cassandra-repair.service\` (To kill a running repair)"
echo -e "    *   \`sudo systemctl start cassandra-repair.service\` (To manually start a repair)"
echo -e "    *   \`sudo systemctl stop cassandra-repair.timer\` (To pause the automated schedule)"
) | less -R
}

show_dr_guide() {
(
echo -e "${BOLD}${BLUE}## Backup & Recovery Guide${NC}"
echo -e ""
echo -e "The backup and recovery process is documented in a comprehensive, standalone guide."
echo -e "This guide covers the architecture, all operational commands, and detailed step-by-step"
echo -e "walkthroughs for various disaster recovery scenarios."
echo -e ""
echo -e "To view this guide, please run the following command:"
echo -e ""
echo -e "${CYAN}    sudo cass-ops backup-guide${NC}"
echo -e ""
echo -e "This will open the complete guide in a scrollable view directly in your terminal."

) | less -R
}

show_puppet_guide() {
(
echo -e "${BOLD}${BLUE}## Puppet Architecture Guide${NC}"
echo -e ""
echo -e "A complete guide to the Puppet automation architecture (Roles & Profiles, Hiera data flow, etc.)"
echo -e "is available as a standalone document."
echo -e ""
echo -e "To view this guide, please run the following command:"
echo -e ""
echo -e "${CYAN}    sudo cass-ops puppet-guide${NC}"
echo -e ""

) | less -R
}

show_production_readiness() {
(
echo -e "${BOLD}${BLUE}## Production Readiness Guide${NC}"
echo -e ""
echo -e "Having functional backups is the first step. Ensuring they are reliable and secure is the next."
echo -e ""
echo -e "${BOLD}${BLUE}### Automated Service Monitoring and Restart${NC}"
echo -e ""
echo -e "This module uses the native capabilities of \`systemd\` to ensure the Cassandra service remains running. If the Cassandra process crashes or is terminated unexpectedly, \`systemd\` will automatically attempt to restart it."
echo -e ""
echo -e "*   ${BOLD}How it Works:${NC} Puppet creates a \`systemd\` override file that configures \`Restart=always\` and \`RestartSec=10\`. This means \`systemd\` will always try to bring the service back up, waiting 10 seconds between attempts to prevent rapid-fire restart loops."
echo -e "*   ${BOLD}Configuration:${NC} You can customize this behavior in Hiera. For example, to disable it, set \`profile_cassandra_pfpt::service_restart: 'no'\`. See the Hiera reference for more details."
echo -e "*   ${BOLD}Monitoring:${NC} While this provides automatic recovery, it's still critical to have external alerting (e.g., via Prometheus) to notify you *when* a restart has occurred, as it often points to an underlying issue that needs investigation."
echo -e ""
echo -e "${BOLD}${BLUE}### Monitoring Backups and Alerting${NC}"
echo -e ""
echo -e "A backup that fails silently is not a backup. The automated backup jobs run via \`cron\`. You must monitor their status."
echo -e ""
echo -e "*   ${BOLD}Manual Checks:${NC}"
echo -e "    *   Check the cron log file (typically \`/var/log/cron\` or \`/var/log/syslog\` depending on your OS) for entries related to \`cassandra-full-backup\` and \`cassandra-incremental-backup\`."
echo -e "    *   Check the dedicated backup logs: \`/var/log/cassandra/full_backup.log\` and \`/var/log/cassandra/incremental_backup.log\`."
echo -e ""
echo -e "*   ${BOLD}Automated Alerting (Recommended):${NC}"
echo -e "    *   Integrate your monitoring system (e.g., Prometheus with \`node_exporter\`'s textfile collector, Datadog) to parse the output of the backup log files."
echo -e "    *   ${RED}Create alerts that trigger if a backup log has not been updated in 24 hours or if it contains \"ERROR\".${NC}"
echo -e ""
echo -e "${BOLD}${BLUE}### Testing Your Disaster Recovery Plan (Fire Drills)${NC}"
echo -e ""
echo -e "The only way to trust your backups is to test them regularly."
echo -e ""
echo -e "1.  ${BOLD}Schedule Quarterly Drills:${NC} At least once per quarter, perform a full DR test."
echo -e "2.  ${BOLD}Provision an Isolated Environment:${NC} Spin up a new, temporary VPC with a small, isolated Cassandra cluster (e.g., 3 nodes)."
echo -e "3.  ${BOLD}Execute the DR Playbook:${NC} Follow the \"Full Cluster Restore (Cold Start DR)\" scenario documented in the full backup and recovery guide (\`cass-ops backup-guide\`)."
echo -e "4.  ${BOLD}Validate Data:${NC} Once restored, run queries to verify that the data is consistent and accessible."
echo -e "5.  ${BOLD}Document and Decommission:${NC} Note any issues found during the drill and then tear down the test environment."
echo -e ""
echo -e "${BOLD}${BLUE}### Important Security and Cost Considerations${NC}"
echo -e ""
echo -e "*   ${BOLD}Encryption Key Management:${NC}"
echo -e "    *   The \`backup_encryption_key\` is the most critical secret. It should be managed in Hiera-eyaml."
echo -e "    *   ${BOLD}Key Rotation:${NC} To rotate the key, update the encrypted value in Hiera. Puppet will deploy the change. From that point on, ${BOLD}new backups${NC} will use the new key."
echo -e "    *   ${RED}IMPORTANT:${NC} You must securely store ${BOLD}all old keys${NC} that were used for previous backups. If you need to restore from a backup made a month ago, you will need the key that was active at that time."
echo -e ""
echo -e "*   ${BOLD}S3 Cost Management:${NC}"
echo -e "    *   S3 costs can grow significantly over time."
echo -e "    *   The backup script now automatically manages a lifecycle policy to expire objects after \`s3_retention_period\` days."
echo -e "    *   For more advanced strategies, consider using ${BOLD}S3 Lifecycle Policies${NC} on your backup bucket directly. A typical policy would be:"
echo -e "        *   Transition backups older than 30 days to a cheaper storage class (e.g., S3 Infrequent Access)."
echo -e "        *   Transition backups older than 90 days to archival storage (e.g., S3 Glacier Deep Archive)."
echo -e "        *   Permanently delete backups older than your retention policy (e.g., 1 year)."
echo -e ""
echo -e "*   ${BOLD}Cross-Region Disaster Recovery:${NC}"
echo -e "    *   To protect against a full AWS region failure, enable ${BOLD}S3 Cross-Region Replication${NC} on your backup bucket to automatically copy backups to a secondary DR region."
echo -e "    *   Be aware of the data transfer costs associated with both replication and a potential cross-region restore."
) | less -R
}

show_hiera_reference() {
(
echo -e "${BOLD}${BLUE}## Hiera Parameter Reference${NC}"
echo -e ""
echo -e "This section documents every available Hiera key for this profile."
echo -e ""
echo -e "${BOLD}${BLUE}### Core Settings${NC}"
echo -e "*   \`profile_cassandra_pfpt::cassandra_version\` (String): The version of the Cassandra package to install. Default: \`'4.1.10-1'\`."
echo -e "*   \`profile_cassandra_pfpt::java_version\` (String): The major version of Java to install (e.g., '8', '11'). Default: \`'11'\`."
echo -e "*   \`profile_cassandra_pfpt::cluster_name\` (String): The name of the Cassandra cluster. Default: \`'pfpt-cassandra-cluster'\`."
echo -e "*   \`profile_cassandra_pfpt::seeds\` (Array[String]): A list of seed node IP addresses. If empty, the node will seed from itself. Default: \`[]\`."
echo -e "*   \`profile_cassandra_pfpt::cassandra_password\` (String): The password for the main \`cassandra\` superuser. Default: \`'PP#C@ss@ndr@000'\`."
echo -e ""
echo -e "${BOLD}${BLUE}### Topology${NC}"
echo -e "*   \`profile_cassandra_pfpt::datacenter\` (String): The name of the datacenter this node belongs to. Default: \`'dc1'\`."
echo -e "*   \`profile_cassandra_pfpt::rack\` (String): The name of the rack this node belongs to. Default: \`'rack1'\`."
echo -e "*   \`profile_cassandra_pfpt::endpoint_snitch\` (String): The snitch to use for determining network topology. Default: \`'GossipingPropertyFileSnitch'\`."
echo -e "*   \`profile_cassandra_pfpt::racks\` (Hash): A hash for mapping racks to datacenters, used by \`GossipingPropertyFileSnitch\`. Default: \`{}\`."
echo -e ""
echo -e "${BOLD}${BLUE}### Networking${NC}"
echo -e "*   \`profile_cassandra_pfpt::listen_address\` (String): The IP address for Cassandra to listen on. Default: \`\$facts['networking']['ip']\`."
echo -e "*   \`profile_cassandra_pfpt::native_transport_port\` (Integer): The port for CQL clients. Default: \`9042\`."
echo -e "*   \`profile_cassandra_pfpt::storage_port\` (Integer): The port for internode communication. Default: \`7000\`."
echo -e "*   \`profile_cassandra_pfpt::ssl_storage_port\` (Integer): The port for SSL internode communication. Default: \`7001\`."
echo -e "*   \`profile_cassandra_pfpt::rpc_port\` (Integer): The port for the Thrift RPC service. Default: \`9160\`."
echo -e "*   \`profile_cassandra_pfpt::start_native_transport\` (Boolean): Whether to start the CQL native transport service. Default: \`true\`."
echo -e "*   \`profile_cassandra_pfpt::start_rpc\` (Boolean): Whether to start the legacy Thrift RPC service. Default: \`true\`."
echo -e ""
echo -e "${BOLD}${BLUE}### Service Management${NC}"
echo -e "*   \`profile_cassandra_pfpt::service_restart\` (String): The \`Restart\` policy for the \`systemd\` service. Can be \`no\`, \`on-success\`, \`on-failure\`, \`on-abnormal\`, \`on-watchdog\`, \`on-abort\`, or \`always\`. Default: \`'always'\`."
echo -e "*   \`profile_cassandra_pfpt::service_restart_sec\` (Integer): The number of seconds to wait before restarting the service. Default: \`10\`."
echo -e ""
echo -e "${BOLD}${BLUE}### Directories & Paths${NC}"
echo -e "*   \`profile_cassandra_pfpt::data_dir\` (String): Path to the data directories. Default: \`'/var/lib/cassandra/data'\`."
echo -e "*   \`profile_cassandra_pfpt::commitlog_dir\` (String): Path to the commit log directory. Default: \`'/var/lib/cassandra/commitlog'\`."
echo -e "*   \`profile_cassandra_pfpt::saved_caches_dir\` (String): Path to the saved caches directory. Default: \`'/var/lib/cassandra/saved_caches'\`."
echo -e "*   \`profile_cassandra_pfpt::hints_directory\` (String): Path to the hints directory. Default: \`'/var/lib/cassandra/hints'\`."
echo -e "*   \`profile_cassandra_pfpt::cdc_raw_directory\` (String): Path for Change Data Capture logs. Default: \`'/var/lib/cassandra/cdc_raw'\`."
echo -e ""
echo -e "${BOLD}${BLUE}### JVM & Performance${NC}"
echo -e "*   \`profile_cassandra_pfpt::max_heap_size\` (String): The maximum JVM heap size (e.g., '4G', '8000M'). Default: \`'3G'\`."
echo -e "*   \`profile_cassandra_pfpt::gc_type\` (String): The garbage collector type to use ('G1GC' or 'CMS'). Default: \`'G1GC'\`."
echo -e "*   \`profile_cassandra_pfpt::num_tokens\` (Integer): The number of tokens to assign to the node. Default: \`256\`."
echo -e "*   \`profile_cassandra_pfpt::initial_token\` (String): For disaster recovery, specifies the comma-separated list of tokens for the first node being restored in a new cluster. Should be used with \`num_tokens: 1\`. Default: \`undef\`."
echo -e "*   \`profile_cassandra_pfpt::concurrent_reads\` (Integer): The number of concurrent read requests. Default: \`32\`."
echo -e "*   \`profile_cassandra_pfpt::concurrent_writes\` (Integer): The number of concurrent write requests. Default: \`32\`."
echo -e "*   \`profile_cassandra_pfpt::concurrent_compactors\` (Integer): The number of concurrent compaction processes. Default: \`4\`."
echo -e "*   \`profile_cassandra_pfpt::compaction_throughput_mb_per_sec\` (Integer): Throttles compaction to a specific throughput. Default: \`16\`."
echo -e "*   \`profile_cassandra_pfpt::jvm_additional_opts\` (Hash): A hash of extra JVM arguments to add or override in \`jvm-server.options\`. Default: \`{}\`."
echo -e ""
echo -e "${BOLD}${BLUE}### Security & Authentication${NC}"
echo -e "*   \`profile_cassandra_pfpt::authenticator\` (String): The authentication backend. Default: \`'PasswordAuthenticator'\`."
echo -e "*   \`profile_cassandra_pfpt::authorizer\` (String): The authorization backend. Default: \`'CassandraAuthorizer'\`."
echo -e "*   \`profile_cassandra_pfpt::role_manager\` (String): The role management backend. Default: \`'CassandraRoleManager'\`."
echo -e "*   \`profile_cassandra_pfpt::cassandra_roles\` (Hash): A hash defining user roles to be managed declaratively. See example above. Default: \`{}\`."
echo -e "*   \`profile_cassandra_pfpt::system_keyspaces_replication\` (Hash): Defines the replication factor for system keyspaces in a multi-DC setup. Example: \`{ 'dc1' => 3, 'dc2' => 3 }\`. Default: \`{}\`."
echo -e ""
echo -e "${BOLD}${BLUE}### Automated Maintenance${NC}"
echo -e "*   \`profile_cassandra_pfpt::manage_scheduled_repair\` (Boolean): Set to \`true\` to enable the automated weekly repair job. Default: \`false\`."
echo -e "*   \`profile_cassandra_pfpt::repair_schedule\` (String): The \`systemd\` OnCalendar schedule for the automated repair job. Default: \`'*-*-1/5 01:00:00'\`. This schedules the repair to run every 5 days, which is a safe interval for a 10-day \`gc_grace_seconds\`."
echo -e "*   \`profile_cassandra_pfpt::repair_keyspace\` (String): If set, the automated repair job will only repair this specific keyspace. If unset, it repairs all non-system keyspaces. Default: \`undef\`."
echo -e "*   \`profile_cassandra_pfpt::manage_full_backups\` (Boolean): Enables the scheduled full backup script. Default: \`false\`."
echo -e "*   \`profile_cassandra_pfpt::manage_incremental_backups\` (Boolean): Enables the scheduled incremental backup script. Default: \`false\`."
echo -e "*   \`profile_cassandra_pfpt::backup_encryption_key\` (Sensitive[String]): The secret key used to encrypt all backup archives. ${RED}WARNING:${NC} This has an insecure default value to prevent Puppet runs from failing. You ${BOLD}MUST${NC} override this with a strong, unique secret in your production Hiera data. Default: \`'MustBeChanged-ChangeMe-ChangeMe!!'\`."
echo -e "*   \`profile_cassandra_pfpt::backup_backend\` (String): The storage backend to use for uploads. Set to \`'local'\` to disable uploads. Default: \`'s3'\`."
echo -e "*   \`profile_cassandra_pfpt::backup_s3_bucket\` (String): The name of the S3 bucket to use when \`backup_backend\` is \`'s3'\`. Default: \`'puppet-cassandra-backups'\`."
echo -e "*   \`profile_cassandra_pfpt::s3_retention_period\` (Integer): The number of days to keep backups in S3 before they are automatically deleted by a lifecycle policy. The policy is applied automatically by the backup script. Set to 0 to disable. Default: \`15\`."
echo -e "*   \`profile_cassandra_pfpt::clearsnapshot_keep_days\` (Integer): The number of days to keep local snapshots on the node before they are automatically deleted. Set to 0 to disable. Default: \`3\`."
echo -e "*   \`profile_cassandra_pfpt::upload_streaming\` (Boolean): Whether to use a direct streaming pipeline for backups (\`true\`) or a more robust method using temporary files (\`false\`). Streaming is faster but can hide errors. Default: \`false\`."
echo -e "*   \`profile_cassandra_pfpt::backup_parallelism\` (Integer): The number of concurrent tables to process during backup or restore operations. Default: \`4\`."
echo -e "*   \`profile_cassandra_pfpt::backup_exclude_keyspaces\` (Array[String]): A list of keyspace names to exclude from backups. Default: \`[]\`."
echo -e "*   \`profile_cassandra_pfpt::backup_exclude_tables\` (Array[String]): A list of specific tables to exclude, in \`'keyspace.table'\` format. Default: \`[]\`."
echo -e "*   \`profile_cassandra_pfpt::backup_include_only_keyspaces\` (Array[String]): If set, **only** these keyspaces will be backed up. All other tables will be ignored. Default: \`[]\`."
echo -e "*   \`profile_cassandra_pfpt::backup_include_only_tables\` (Array[String]): If set, **only** these specific tables will be backed up. This is the most granular option and takes precedence. Default: \`[]\`."
echo -e "*   \`profile_cassandra_pfpt::manage_stress_test\` (Boolean): Set to \`true\` to install the \`cassandra-stress\` tools and the \`/usr/local/bin/stress-test.sh\` wrapper script. Default: \`false\`."
) | less -R
}

show_all() {
    # This is intentionally left blank for now to avoid duplication.
    # The individual sections are more useful.
    # If a single-page view is needed, each function can be called here.
    echo "Viewing all sections is not implemented. Please select an individual section."
    sleep 2
}

# Main menu loop
while true; do
    clear
    echo -e "${BOLD}${BLUE}Cassandra Operations Manual${NC}"
    echo -e "${YELLOW}-----------------------------${NC}"
    echo ""
    echo -e "${GREEN}Select a section to view:${NC}"
    echo " 1) Description"
    echo " 2) Setup"
    echo " 3) Usage Examples"
    echo " 4) Operator's Quick Reference"
    echo " 5) Day-2 Operations Guide"
    echo " 6) Automated Maintenance Guide"
    echo " 7) Backup & Recovery Guide (Full)"
    echo " 8) Production Readiness Guide"
    echo " 9) Hiera Parameter Reference"
    echo " 10) Puppet Architecture Guide (Full)"
    echo ""
    echo " q) Quit"
    echo ""
    read -p "Enter your choice: " choice

    case $choice in
        1) show_description ;;
        2) show_setup ;;
        3) show_usage_examples ;;
        4) show_quick_reference ;;
        5) show_day2_ops ;;
        6) show_automated_maintenance ;;
        7) /usr/local/bin/cass-ops backup-guide ;;
        8) show_production_readiness ;;
        9) show_hiera_reference ;;
        10) /usr/local/bin/cass-ops puppet-guide ;;
        q|Q) break ;;
        *) echo -e "${RED}Invalid option. Please try again.${NC}"; sleep 1 ;;
    esac
done
