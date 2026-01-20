# Class: cassandra_pfpt
#
# This is the main class of the cassandra_pfpt module.
# It orchestrates the entire Cassandra node setup.
#
class cassandra_pfpt (
  String $cassandra_version,
  String $cluster_name,
  String $dc,
  String $rack,
  String $listen_address,
  String $rpc_address,
  String $seeds,
  Boolean $backup_enabled,
  String $s3_bucket_name,
  Integer $full_backup_hour,
  Integer $full_backup_minute,
  Integer $incremental_backup_minute,
  Integer $clearsnapshot_keep_days,
  String $backup_backend,
) {

  contain cassandra_pfpt::install
  contain cassandra_pfpt::config
  contain cassandra_pfpt::service
  contain cassandra_pfpt::health
  contain cassandra_pfpt::maintenance
  contain cassandra_pfpt::management
  contain cassandra_pfpt::backup

  Class['cassandra_pfpt::install']
  -> Class['cassandra_pfpt::config']
  ~> Class['cassandra_pfpt::service']
  -> Class['cassandra_pfpt::health']
  -> Class['cassandra_pfpt::maintenance']
  -> Class['cassandra_pfpt::management']
  -> Class['cassandra_pfpt::backup']
}
