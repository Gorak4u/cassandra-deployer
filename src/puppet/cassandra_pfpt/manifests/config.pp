# @summary Manages all Cassandra configuration files and helper scripts.
class cassandra_pfpt::config {
  # Directories
  file {
    [
      $cassandra_pfpt::data_dir,
      $cassandra_pfpt::commitlog_dir,
      $cassandra_pfpt::saved_caches_dir,
      $cassandra_pfpt::hints_directory,
      $cassandra_pfpt::cdc_raw_directory,
      $cassandra_pfpt::manage_bin_dir,
      '/var/log/cassandra',
    ]:
      ensure => directory,
      owner  => $cassandra_pfpt::user,
      group  => $cassandra_pfpt::group,
      mode   => '0755',
    }
  }

  # Main config file from template
  file { '/etc/cassandra/conf/cassandra.yaml':
    ensure  => file,
    content => template('cassandra_pfpt/cassandra.yaml.erb'),
    owner   => $cassandra_pfpt::user,
    group   => $cassandra_pfpt::group,
    mode    => '0644',
    require => Class['cassandra_pfpt::install'],
  }

  # JVM options from template
  file { '/etc/cassandra/conf/jvm-server.options':
    ensure  => file,
    content => template('cassandra_pfpt/jvm-server.options.erb'),
    owner   => $cassandra_pfpt::user,
    group   => $cassandra_pfpt::group,
    mode    => '0644',
    require => Class['cassandra_pfpt::install'],
  }

  # Rack and DC properties
  file { '/etc/cassandra/conf/cassandra-rackdc.properties':
    ensure  => file,
    content => template('cassandra_pfpt/cassandra-rackdc.properties.erb'),
    owner   => $cassandra_pfpt::user,
    group   => $cassandra_pfpt::group,
    mode    => '0644',
    require => Class['cassandra_pfpt::install'],
  }

  # JMX Security
  if $cassandra_pfpt::manage_jmx_security {
    file { $cassandra_pfpt::jmx_password_file_path:
      ensure  => file,
      content => $cassandra_pfpt::jmx_password_file_content,
      owner   => $cassandra_pfpt::user,
      group   => $cassandra_pfpt::group,
      mode    => '0600',
      require => Class['cassandra_pfpt::install'],
    }
    file { $cassandra_pfpt::jmx_access_file_path:
      ensure  => file,
      content => $cassandra_pfpt::jmx_access_file_content,
      owner   => $cassandra_pfpt::user,
      group   => $cassandra_pfpt::group,
      mode    => '0644',
      require => Class['cassandra_pfpt::install'],
    }
  }
  
  # Deploy helper scripts
  $scripts = [
    'assassinate-node.sh',
    'cassandra-upgrade-precheck.sh',
    'cassandra_range_repair.py',
    'cleanup-node.sh',
    'cluster-health.sh',
    'compaction-manager.sh',
    'decommission-node.sh',
    'disk-health-check.sh',
    'drain-node.sh',
    'full-backup-to-s3.sh',
    'garbage-collect.sh',
    'incremental-backup-to-s3.sh'
  ]

  $scripts.each |String $script_name| {
    file { "${cassandra_pfpt::manage_bin_dir}/${script_name}":
      ensure => file,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      source => "puppet:///modules/cassandra_pfpt/files/${script_name}",
    }
  }
}
