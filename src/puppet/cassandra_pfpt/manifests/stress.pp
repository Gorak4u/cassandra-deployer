class cassandra_pfpt::stress (
  String $user,
  Sensitive[String] $password,
  Boolean $ssl_enabled,
) {
  ensure_packages(['cassandra-tools'])

  file { '/etc/cassandra/conf/stress.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => template('cassandra_pfpt/stress.conf.erb'),
  }

  file { '/usr/local/bin/stress-test.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/stress-test.sh',
  }
}
