
export const roles = `
# @summary Manages Cassandra user roles based on Hiera data.
class cassandra_pfpt::roles inherits cassandra_pfpt {

  if !empty($cassandra_roles) {
    $cassandra_roles.each |$role_name, $role_details| {
      # For each role defined in Hiera, create a temporary CQL file
      $cql_file_path = "/tmp/create_role_\${role_name}.cql"
      $role_options = "WITH SUPERUSER = \${role_details['is_superuser']} AND LOGIN = \${role_details['can_login']} AND PASSWORD = '\${role_details['password']}'"
      $create_cql = "CREATE ROLE IF NOT EXISTS \\"\${role_name}\\" \${role_options};"

      file { $cql_file_path:
        ensure  => 'file',
        content => $create_cql,
        owner   => 'root',
        group   => 'root',
        mode    => '0600',
      }

      # Define the command to check if the role exists.
      # We build the command in a variable to handle quoting safely.
      $unless_command = "cqlsh \${cqlsh_ssl_opt} -u cassandra -p '\${cassandra_password}' -e \\"DESCRIBE ROLE \\\\"\${role_name}\\\\"\\" \${listen_address}"

      # Execute the CQL file to create or update the role
      exec { "create_cassandra_role_\${role_name}":
        command     => "cqlsh \${cqlsh_ssl_opt} -u cassandra -p '\${cassandra_password}' -f \${cql_file_path} \${listen_address}",
        path        => ['/bin', '/usr/bin', $cqlsh_path_env],
        unless      => $unless_command,
        require     => [Exec['change_cassandra_password'], File[$cql_file_path]],
      }
    }
  }
}
`.trim();
