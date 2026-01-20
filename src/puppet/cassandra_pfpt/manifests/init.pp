class cassandra_pfpt (
  String $package_name              = 'cassandra',
  String $service_name              = 'cassandra',
  String $config_file_path          = '/etc/cassandra/cassandra.yaml',
  String $data_directory_path       = '/var/lib/cassandra/data',
  String $log_directory_path        = '/var/log/cassandra',
  String $user                      = 'cassandra',
  String $group                     = 'cassandra',
  Array[String] $seed_nodes         = [],
  String $cluster_name              = 'MyCassandraCluster',
  String $listen_address            = $facts['networking']['ip'],
  Optional[String] $broadcast_address = undef,
) {

  package { $package_name:
    ensure => installed,
  }

  service { $service_name:
    ensure  => running,
    enable  => true,
    require => Package[$package_name],
  }

  file { '/usr/local/bin/assassinate-node.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/assassinate-node.sh',
  }

  file { '/usr/local/bin/cassandra-upgrade-precheck.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/cassandra-upgrade-precheck.sh',
  }

  file { '/usr/local/bin/cassandra_range_repair.py':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/cassandra_range_repair.py',
  }

  file { '/usr/local/bin/cleanup-node.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/cleanup-node.sh',
  }

  file { '/usr/local/bin/cluster-health.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/cluster-health.sh',
  }

  file { '/usr/local/bin/compaction-manager.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/compaction-manager.sh',
  }

  file { '/usr/local/bin/decommission-node.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/decommission-node.sh',
  }

  file { '/usr/local/bin/disk-health-check.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/disk-health-check.sh',
  }

  file { '/usr/local/bin/drain-node.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/drain-node.sh',
  }

  file { '/usr/local/bin/full-backup-to-s3.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/full-backup-to-s3.sh',
  }

  file { '/usr/local/bin/garbage-collect.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/garbage-collect.sh',
  }

  file { '/usr/local/bin/incremental-backup-to-s3.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/incremental-backup-to-s3.sh',
  }
}
