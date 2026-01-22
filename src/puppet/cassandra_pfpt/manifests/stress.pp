# @summary Manages cassandra-stress tool and wrapper script.
class cassandra_pfpt::stress (
  String $user,
  String $config_dir_path,
  String $cassandra_user,
  Sensitive[String] $cassandra_pass,
  Boolean $ssl_enabled,
) {
  # Ensure the cassandra-tools package is installed
  ensure_packages(['cassandra-tools'])

  # Deploy the stress schema file
  file { "${config_dir_path}/stress-schema.yaml":
    ensure => file,
    owner  => $user,
    group  => $user,
    mode   => '0644',
    source => 'puppet:///modules/cassandra_pfpt/stress-schema.yaml',
  }

  # Deploy the wrapper script
  file { '/usr/local/bin/stress-test.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/cassandra_pfpt/stress-test.sh',
  }

  # Deploy the configuration for the wrapper script
  file { "${config_dir_path}/stress.conf":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600', # Secure, contains password
    content => epp('cassandra_pfpt/stress.conf.epp', {
      'cassandra_user' => $cassandra_user,
      'cassandra_pass' => $cassandra_pass.unwrap,
      'use_ssl'        => $ssl_enabled,
    }),
  }
}
