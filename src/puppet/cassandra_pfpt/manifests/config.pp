# Class: cassandra_pfpt::config
#
# This class manages all Cassandra configuration files.
#
class cassandra_pfpt::config {
  file { '/etc/cassandra/cassandra.yaml':
    ensure  => file,
    owner   => 'cassandra',
    group   => 'cassandra',
    mode    => '0644',
    content => template('cassandra_pfpt/cassandra.yaml.erb'),
    require => Class['cassandra_pfpt::install'],
    notify  => Class['cassandra_pfpt::service'],
  }

  file { '/etc/cassandra/cassandra-env.sh':
    ensure  => file,
    owner   => 'cassandra',
    group   => 'cassandra',
    mode    => '0644',
    content => template('cassandra_pfpt/cassandra-env.sh.erb'),
    require => Class['cassandra_pfpt::install'],
    notify  => Class['cassandra_pfpt::service'],
  }

  file { '/etc/cassandra/jvm-server.options':
    ensure  => file,
    owner   => 'cassandra',
    group   => 'cassandra',
    mode    => '0644',
    content => template('cassandra_pfpt/jvm-server.options.erb'),
    require => Class['cassandra_pfpt::install'],
    notify  => Class['cassandra_pfpt::service'],
  }

  file { '/etc/cassandra/cassandra-rackdc.properties':
    ensure  => file,
    owner   => 'cassandra',
    group   => 'cassandra',
    mode    => '0644',
    content => template('cassandra_pfpt/cassandra-rackdc.properties.erb'),
    require => Class['cassandra_pfpt::install'],
    notify  => Class['cassandra_pfpt::service'],
  }

  file { '/root/.cassandra/cqlshrc':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => template('cassandra_pfpt/cqlshrc.erb'),
    require => Class['cassandra_pfpt::install'],
  }
}
