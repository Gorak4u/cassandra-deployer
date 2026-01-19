
export const backup_timer = {
  full: `
# /etc/systemd/system/cassandra-full-backup.timer
# Managed by Puppet

[Unit]
Description=Timer to schedule Cassandra node full backups

[Timer]
OnCalendar=<%= @full_backup_schedule %>
Persistent=true
Unit=cassandra-full-backup.service

[Install]
WantedBy=timers.target
`.trim(),
  incremental: `
# /etc/systemd/system/cassandra-incremental-backup.timer
# Managed by Puppet

[Unit]
Description=Timer to schedule Cassandra node incremental backups

[Timer]
<% if @incremental_backup_schedule.is_a?(Array) -%>
<% @incremental_backup_schedule.each do |schedule| -%>
OnCalendar=<%= schedule %>
<% end -%>
<% else -%>
OnCalendar=<%= @incremental_backup_schedule %>
<% end -%>
Persistent=true
Unit=cassandra-incremental-backup.service

[Install]
WantedBy=timers.target
`.trim(),
};
