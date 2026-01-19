
export const backup_service = {
  full: `
# /etc/systemd/system/cassandra-full-backup.service
# Managed by Puppet

[Unit]
Description=Cassandra Node Full Backup Service
Wants=cassandra.service
After=cassandra.service

[Service]
Type=oneshot
User=root
Group=root
ExecStart=<%= @full_backup_script_path %>
`.trim(),
  incremental: `
# /etc/systemd/system/cassandra-incremental-backup.service
# Managed by Puppet

[Unit]
Description=Cassandra Node Incremental Backup Service
Wants=cassandra.service
After=cassandra.service

[Service]
Type=oneshot
User=root
Group=root
ExecStart=<%= @incremental_backup_script_path %>
`.trim(),
};
