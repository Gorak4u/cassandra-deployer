
export const backup_config = `
{
  "s3_bucket_name": "<%= @backup_s3_bucket %>",
  "backup_backend": "<%= @backup_backend %>",
  "cassandra_data_dir": "<%= @data_dir %>",
  "commitlog_dir": "<%= @commitlog_dir %>",
  "saved_caches_dir": "<%= @saved_caches_dir %>",
  "full_backup_log_file": "<%= @full_backup_log_file %>",
  "incremental_backup_log_file": "<%= @incremental_backup_log_file %>",
  "listen_address": "<%= @listen_address %>",
  "seeds_list": <%= @seeds.to_json %>
}
`.trim();
