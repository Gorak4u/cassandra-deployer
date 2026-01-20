# Class: profile_cassandra_pfpt
#
# This profile class configures the cassandra_pfpt component module
# using data from Hiera.
#
class profile_cassandra_pfpt {
  class { 'cassandra_pfpt':
    cassandra_version         => hiera('cassandra_pfpt::cassandra_version', '3.11.10'),
    cluster_name              => hiera('cassandra_pfpt::cluster_name', 'MyCassandraCluster'),
    dc                        => hiera('cassandra_pfpt::dc', 'dc1'),
    rack                      => hiera('cassandra_pfpt::rack', 'rack1'),
    listen_address            => hiera('cassandra_pfpt::listen_address', $facts['networking']['ip']),
    rpc_address               => hiera('cassandra_pfpt::rpc_address', '0.0.0.0'),
    seeds                     => hiera('cassandra_pfpt::seeds', $facts['networking']['ip']),
    backup_enabled            => hiera('cassandra_pfpt::backup_enabled', true),
    s3_bucket_name            => hiera('cassandra_pfpt::s3_bucket_name', 'my-cassandra-backups'),
    full_backup_hour          => hiera('cassandra_pfpt::full_backup_hour', 2),
    full_backup_minute        => hiera('cassandra_pfpt::full_backup_minute', 0),
    incremental_backup_minute => hiera('cassandra_pfpt::incremental_backup_minute', '*/30'),
    clearsnapshot_keep_days   => hiera('cassandra_pfpt::clearsnapshot_keep_days', 7),
    backup_backend            => hiera('cassandra_pfpt::backup_backend', 's3'),
  }
}
