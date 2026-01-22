# @summary Manages Cassandra stress testing tools and their configuration.
class cassandra_pfpt::stress(
  String $user,
  Sensitive[String] $password,
  Boolean $ssl_enabled,
  String $config_path = '/etc/cassandra/conf/stress.conf',
){
  package { 'cassandra-tools':
    ensure => installed,
  }

  file { '/usr/local/bin/stress-test.sh':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    source  => 'puppet:///modules/cassandra_pfpt/stress-test.sh',
    require => Package['cassandra-tools'],
  }

  # Create a secure configuration file for the stress test wrapper
  file { $config_path:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600', # Secure: only root can read
    content => epp('cassandra_pfpt/stress.conf.epp', {
      'user'     => $user,
      'password' => $password.unwrap,
      'ssl'      => $ssl_enabled,
    }),
    require => Package['cassandra-tools'],
  }
}
