# @summary Manages Cassandra roles and users.
class cassandra_pfpt::roles {

  # Always ensure default cassandra user password is set
  exec { 'set_default_cassandra_password':
    command   => "${cassandra_pfpt::cqlsh_path_env} -u cassandra -p cassandra \"${cassandra_pfpt::change_password_cql}\"",
    path      => ['/bin', '/usr/bin'],
    unless    => "${cassandra_pfpt::cqlsh_path_env} -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e 'select * from system.local limit 1;'",
    tries     => 10,
    try_sleep => 10,
    require   => Class['cassandra_pfpt::service'],
  }

  # Manage additional roles from Hiera
  if !empty($cassandra_pfpt::cassandra_roles) {
    $cassandra_pfpt::cassandra_roles.each |$role, $attributes| {
      $password = $attributes['password']
      $superuser = $attributes.get('superuser', false) ? {
        true    => 'SUPERUSER',
        default => 'NOSUPERUSER'
      }
      $login = $attributes.get('login', true) ? {
        true    => 'LOGIN',
        default => 'NOLOGIN'
      }

      $create_cql = "CREATE ROLE IF NOT EXISTS ${role} WITH password = '${password}' AND ${login} = true AND ${superuser} = true;"

      exec { "create_cassandra_role_${role}":
        command   => "${cassandra_pfpt::cqlsh_path_env} -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e \"${create_cql}\"",
        path      => ['/bin', '/usr/bin'],
        unless    => "${cassandra_pfpt::cqlsh_path_env} -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e 'DESCRIBE ROLE ${role};' | grep '${role}'",
        require   => Exec['set_default_cassandra_password'],
      }
    }
  }
}
