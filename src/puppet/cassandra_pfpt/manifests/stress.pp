# @summary Manages the installation of Cassandra stress testing tools and configuration.
class cassandra_pfpt::stress (
  String $user,
  Sensitive[String] $password,
  Boolean $ssl_enabled,
) {
  # Ensure the cassandra-tools package is installed
  package { 'cassandra-tools':
    ensure => present,
  }

  # Create a secure configuration file for the stress test wrapper script
  file { '/etc/cassandra/conf/stress.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => template('cassandra_pfpt/stress.conf.erb'),
    require => Package['cassandra-tools'],
  }
}
