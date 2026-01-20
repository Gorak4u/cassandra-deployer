#
# @summary This profile configures a complete Cassandra node, including backups and operational scripts.
#
# @param cluster_name The name of the Cassandra cluster.
# @param seeds An array of seed node IP addresses for the cluster.
# @param backup_s3_bucket The S3 bucket where backups will be stored.
# @param backup_encryption_key The secret key used to encrypt and decrypt backups.
#
class profile_cassandra_pfpt (
  String                $cluster_name            = lookup('profile_cassandra_pfpt::cluster_name', { default_value => 'pfpt-cassandra-cluster' }),
  Array[String]         $seeds                   = lookup('profile_cassandra_pfpt::seeds', { default_value => [] }),
  String                $backup_s3_bucket        = lookup('profile_cassandra_pfpt::backup_s3_bucket', { default_value => 'puppet-cassandra-backups' }),
  Sensitive[String]     $backup_encryption_key   = lookup('profile_cassandra_pfpt::backup_encryption_key'),
) {

  # This hash constructs the configuration that will be written to /etc/backup/config.json
  # The component module cassandra_pfpt will handle the file creation.
  $backup_config_hash = {
    's3_bucket_name'                => $backup_s3_bucket,
    'cassandra_data_dir'            => '/var/lib/cassandra/data',
    'commitlog_dir'                 => '/var/lib/cassandra/commitlog',
    'saved_caches_dir'              => '/var/lib/cassandra/saved_caches',
    'full_backup_log_file'          => '/var/log/cassandra/full-backup.log',
    'incremental_backup_log_file'   => '/var/log/cassandra/incremental-backup.log',
    'listen_address'                => $facts['networking']['ip'],
    'seeds_list'                    => $seeds,
    'encryption_key'                => $backup_encryption_key.unwrap,
  }

  # Convert the hash to a JSON string
  $backup_config_json = to_json_pretty($backup_config_hash)

  # Include the component module, passing down all necessary data.
  class { 'cassandra_pfpt':
    cluster_name          => $cluster_name,
    seeds                 => $seeds,
    backup_config_content => $backup_config_json,
    # Pass other necessary parameters from Hiera to the component module below
  }
}
