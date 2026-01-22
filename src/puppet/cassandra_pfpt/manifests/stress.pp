class cassandra_pfpt::stress {
  package { 'cassandra-tools':
    ensure => installed,
  }

  file { '/usr/local/bin/stress-test.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/stress-test.sh',
  }

  file { '/etc/cassandra/stress-schema.yaml':
    ensure  => file,
    owner   => 'cassandra',
    group   => 'cassandra',
    mode    => '0644',
    source  => 'puppet:///modules/cassandra_pfpt/stress-schema.yaml',
    require => Package['cassandra'],
  }
}
