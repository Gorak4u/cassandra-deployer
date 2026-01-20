# @summary Manages the Cassandra service.
class cassandra_pfpt::service {
  service { 'cassandra':
    ensure  => running,
    enable  => true,
    require => Class['cassandra_pfpt::config'],
  }

  # Add service override for startup timeout, which can be long on large nodes.
  $service_override_dir = '/etc/systemd/system/cassandra.service.d'
  file { $service_override_dir:
    ensure => directory,
  }
  file { "${service_override_dir}/override.conf":
    ensure  => file,
    content => "[Service]\nTimeoutStartSec=${cassandra_pfpt::service_timeout_start_sec}\n",
    notify  => Exec['systemctl-daemon-reload'],
  }
  exec { 'systemctl-daemon-reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
    notify      => Service['cassandra'],
  }
}
