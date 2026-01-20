# Configures a Cassandra node using data from Hiera and passes it to the component module.
class profile_cassandra_pfpt (
  # This parameter gets the encryption key from Hiera.
  # It is Sensitive to prevent it from showing up in logs.
  Sensitive[String] $backup_encryption_key = lookup('profile_cassandra_pfpt::backup_encryption_key'),

  # These parameters are here as placeholders for a complete profile.
  # They are populated from Hiera with sensible defaults.
  String $cluster_name = lookup('profile_cassandra_pfpt::cluster_name', { 'default_value' => 'MyCluster' }),
  String $cassandra_data_dir = lookup('profile_cassandra_pfpt::cassandra_data_dir', { 'default_value' => '/var/lib/cassandra/data' }),
  String $full_backup_log_file = lookup('profile_cassandra_pfpt::full_backup_log_file', { 'default_value' => '/var/log/cassandra/full-backup.log' }),
  String $incremental_backup_log_file = lookup('profile_cassandra_pfpt::incremental_backup_log_file', { 'default_value' => '/var/log/cassandra/incremental-backup.log' }),
  String $listen_address = lookup('profile_cassandra_pfpt::listen_address', { 'default_value' => $facts['networking']['ip'] }),
  Integer $clearsnapshot_keep_days = lookup('profile_cassandra_pfpt::clearsnapshot_keep_days', { 'default_value' => 7 }),
  String $s3_bucket_name = lookup('profile_cassandra_pfpt::s3_bucket_name', { 'default_value' => 'cassandra-backups' })
) {

  # This hash will be converted to JSON for the config file.
  $backup_config = {
    's3_bucket_name'              => $s3_bucket_name,
    'backup_backend'              => 's3',
    'cassandra_data_dir'          => $cassandra_data_dir,
    'full_backup_log_file'        => $full_backup_log_file,
    'incremental_backup_log_file' => $incremental_backup_log_file,
    'listen_address'              => $listen_address,
    'clearsnapshot_keep_days'     => $clearsnapshot_keep_days,
    # The sensitive key is unwrapped just before being put into the JSON.
    'encryption_key'              => $backup_encryption_key.unwrap,
  }

  # Convert the hash to a pretty-printed JSON string.
  $backup_config_json = to_json_pretty($backup_config)

  # Include the component class, passing it the config content.
  # Other parameters for Cassandra itself would be passed here as well.
  class { 'cassandra_pfpt':
    backup_config_content => $backup_config_json,
  }
}
