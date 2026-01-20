# @summary Manages all Cassandra configuration files and helper scripts.
class cassandra_pfpt::config {
  $conf_dir = '/etc/cassandra/conf'
  $bin_dir = $cassandra_pfpt::manage_bin_dir

  # Main cassandra.yaml config file
  file { "${conf_dir}/cassandra.yaml":
    ensure  => file,
    owner   => $cassandra_pfpt::user,
    group   => $cassandra_pfpt::group,
    mode    => '0644',
    content => template('cassandra_pfpt/cassandra.yaml.erb'),
    notify  => Class['cassandra_pfpt::service'],
  }

  # JVM options file
  file { "${conf_dir}/jvm-server.options":
    ensure  => file,
    owner   => $cassandra_pfpt::user,
    group   => $cassandra_pfpt::group,
    mode    => '0644',
    content => template('cassandra_pfpt/jvm-server.options.erb'),
    notify  => Class['cassandra_pfpt::service'],
  }

  # Snitch properties files
  file { "${conf_dir}/cassandra-rackdc.properties":
    ensure  => file,
    owner   => $cassandra_pfpt::user,
    group   => $cassandra_pfpt::group,
    mode    => '0644',
    content => template('cassandra_pfpt/cassandra-rackdc.properties.erb'),
    notify  => Class['cassandra_pfpt::service'],
  }

  if $cassandra_pfpt::endpoint_snitch == 'GossipingPropertyFileSnitch' {
    file { "${conf_dir}/cassandra-topology.properties":
      ensure  => file,
      owner   => $cassandra_pfpt::user,
      group   => $cassandra_pfpt::group,
      mode    => '0644',
      content => template('cassandra_pfpt/cassandra-topology.properties.erb'),
      notify  => Class['cassandra_pfpt::service'],
    }
  }

  # cqlshrc for passwordless cqlsh for root/puppet
  file { '/root/.cassandra':
    ensure => directory,
    mode   => '0700',
  }
  file { '/root/.cassandra/cqlshrc':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => template('cassandra_pfpt/cqlshrc.erb'),
  }

  # JMX security files
  if $cassandra_pfpt::manage_jmx_security {
    file { $cassandra_pfpt::jmx_password_file_path:
      ensure  => file,
      owner   => $cassandra_pfpt::user,
      group   => $cassandra_pfpt::group,
      mode    => '0600',
      content => $cassandra_pfpt::jmx_password_file_content,
      notify  => Class['cassandra_pfpt::service'],
    }
    file { $cassandra_pfpt::jmx_access_file_path:
      ensure  => file,
      owner   => $cassandra_pfpt::user,
      group   => $cassandra_pfpt::group,
      mode    => '0600',
      content => $cassandra_pfpt::jmx_access_file_content,
      notify  => Class['cassandra_pfpt::service'],
    }
  }

  # Manage data directories
  $dirs = [$cassandra_pfpt::data_dir, $cassandra_pfpt::saved_caches_dir, $cassandra_pfpt::commitlog_dir, $cassandra_pfpt::hints_directory]
  file { $dirs:
    ensure => directory,
    owner  => $cassandra_pfpt::user,
    group  => $cassandra_pfpt::group,
    mode   => '0755',
  }

  # Disable swap if requested
  if $cassandra_pfpt::disable_swap {
    exec { 'disable-swap':
      command => 'swapoff -a',
      onlyif  => 'swapon -s | grep -q "."'
    }
    # And prevent it from coming back on reboot
    exec { 'remove-swap-from-fstab':
        command => 'sed -i "/swap/d" /etc/fstab',
        onlyif  => 'grep -q swap /etc/fstab'
    }
  }

  # Manage sysctl and limits
  $cassandra_pfpt::sysctl_settings.each |$key, $value| {
    sysctl { $key:
      ensure => present,
      value  => $value,
    }
  }

  $cassandra_pfpt::limits_settings.each |$item, $values| {
    file { "/etc/security/limits.d/cassandra-${item}.conf":
      ensure  => file,
      content => "cassandra - ${item} ${values['soft']}\ncassandra - ${item} ${values['hard']}\n",
    }
  }

  # Place all helper scripts
  $scripts = [
    'assassinate-node.sh', 'cassandra-upgrade-precheck.sh', 'cassandra_range_repair.py',
    'cleanup-node.sh', 'cluster-health.sh', 'compaction-manager.sh',
    'decommission-node.sh', 'disk-health-check.sh', 'drain-node.sh',
    'full-backup-to-s3.sh', 'garbage-collect.sh', 'incremental-backup-to-s3.sh',
  ]
  $scripts.each |$script| {
    file { "${bin_dir}/${script}":
      ensure => file,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      source => "puppet:///modules/cassandra_pfpt/${script}",
    }
  }

  # Place jamm.jar
  file { $cassandra_pfpt::jamm_target:
    ensure => file,
    source => $cassandra_pfpt::jamm_source,
    mode   => '0644',
  }

  # Initial password change after first startup
  exec { 'set-initial-cassandra-password':
    command     => "${cassandra_pfpt::cqlsh_path_env} cqlsh ${cassandra_pfpt::listen_address} -u cassandra -p cassandra -e \"${cassandra_pfpt::change_password_cql}\"",
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
    tries       => 5,
    try_sleep   => 10,
    subscribe   => Class['cassandra_pfpt::service'],
    unless      => "${cassandra_pfpt::cqlsh_path_env} cqlsh ${cassandra_pfpt::listen_address} -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e 'SHOW HOST'",
  }
}
