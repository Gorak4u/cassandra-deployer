# @summary Manages Cassandra user roles.
class cassandra_pfpt::roles {
  if !empty($cassandra_pfpt::cassandra_roles) {
    $cassandra_pfpt::cassandra_roles.each |$role_name, $role_details| {
      $cql_command = "CREATE ROLE IF NOT EXISTS ${role_name} WITH password = '${role_details['password']}' AND LOGIN = ${role_details['login']} AND SUPERUSER = ${role_details['superuser']};"
      exec { "create-role-${role_name}":
        command   => "cqlsh -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e \"${cql_command}\"",
        path      => ['/bin', '/usr/bin'],
        unless    => "cqlsh -u cassandra -p '${cassandra_pfpt::cassandra_password}' -e 'LIST ROLES' | grep ${role_name}",
        require   => Exec['set-initial-cassandra-password'],
        logoutput => true,
      }
    }
  }
}
