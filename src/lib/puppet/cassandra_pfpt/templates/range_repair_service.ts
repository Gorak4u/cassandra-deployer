
export const range_repair_service = `
[Unit]
Description=Cassandra Range Repair Service
[Service]
Type=simple
User=cassandra
Group=cassandra
ExecStart=<%= @manage_bin_dir %>/range-repair.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
`.trim();
