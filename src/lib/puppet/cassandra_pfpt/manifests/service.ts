
export const service = `
# @summary Manages the Cassandra service.
class cassandra_pfpt::service inherits cassandra_pfpt {
  service { 'cassandra':
    ensure     => running,
    enable     => true,
    hasstatus  => true,
    hasrestart => true,
    require    => [
      Package['cassandra'],
      File['/etc/cassandra/conf/cassandra.yaml'],
      File['/etc/cassandra/conf/cassandra-rackdc.properties'],
      File['/etc/cassandra/conf/jvm-server.options'],
    ],
  }
  file { $\\{change_password_cql}:
    ensure  => 'file',
    content => "ALTER USER cassandra WITH PASSWORD '$\\{cassandra_password}';",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
  }
  $cqlsh_ssl_opt = $\\{ssl_enabled} ? {
    true  => '--ssl',
    false => '',
  }
  # Change only if new password isn't already active
  exec { 'change_cassandra_password':
    command     => "cqlsh $\\{cqlsh_ssl_opt} -u cassandra -p cassandra -f $\\{change_password_cql} $\\{listen_address}",
    path        => ['/bin', '/usr/bin', $\\{cqlsh_path_env}],
    timeout     => 60,
    tries       => 2,
    try_sleep   => 10,
    logoutput   => on_failure,
    # If we can connect with the *new* password, skip running the ALTER
    unless      => "cqlsh $\\{cqlsh_ssl_opt} -u cassandra -p '$\\{cassandra_password}' -e \\"SELECT cluster_name FROM system.local;\\" $\\{listen_address} >/dev/null 2>&1",
    require     => [ Service['cassandra'], File[$\\{change_password_cql}] ],
  }
  if $\\{enable_range_repair} {
    $range_repair_ensure = $\\{enable_range_repair} ? { true => 'running', default => 'stopped' }
    $range_repair_enable = $\\{enable_range_repair} ? { true => true, default => false }
    file { '/etc/systemd/system/range-repair.service':
      ensure  => 'file',
      content => template('cassandra_pfpt/range-repair.service.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      notify  => Exec['systemctl_daemon_reload_range_repair'],
      require => File["$\\{manage_bin_dir}/range-repair.sh"],
    }
    exec { 'systemctl_daemon_reload_range_repair':
      command     => '/bin/systemctl daemon-reload',
      path        => ['/usr/bin', '/bin'],
      refreshonly => true,
    }
    service { 'range-repair':
      ensure    => $range_repair_ensure,
      enable    => $range_repair_enable,
      hasstatus => true,
      subscribe => File['/etc/systemd/system/range-repair.service'],
    }
  }
}
`.trim();
