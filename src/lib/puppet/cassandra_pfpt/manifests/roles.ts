
export const roles = `
# @summary Manages Cassandra user roles based on Hiera data.
class cassandra_pfpt::roles inherits cassandra_pfpt {

  if !empty($cassandra_roles) {
    $cassandra_roles.each |String $role_name, Hash $role_details| {
      # For each role defined in Hiera, create a temporary CQL file
      $cql_file_path = "/tmp/create_role_$role_name.cql"
      $password = $role_details['password']
      $is_superuser = $role_details['is_superuser']
      $can_login = $role_details['can_login']
      $role_options = "WITH SUPERUSER = $is_superuser AND LOGIN = $can_login AND PASSWORD = '$password'"
      $create_cql = "CREATE ROLE IF NOT EXISTS \\"$role_name\\" $role_options;"

      file { $cql_file_path:
        ensure  => 'file',
        content => $create_cql,
        owner   => 'root',
        group   => 'root',
        mode    => '0600',
      }

      # Define the command to check if the role exists.
      $unless_command_str = "DESCRIBE ROLE \\"$role_name\\";"
      $unless_command = "cqlsh $cqlsh_ssl_opt -u cassandra -p '$cassandra_password' $listen_address -e \\"$unless_command_str\\""


      # Execute the CQL file to create or update the role
      exec { "create_cassandra_role_$role_name":
        command     => "cqlsh $cqlsh_ssl_opt -u cassandra -p '$cassandra_password' $listen_address -f $cql_file_path",
        path        => ['/bin', '/usr/bin', $cqlsh_path_env],
        # Only run if the role doesn't exist. This isn't perfect for password updates but prevents rerunning CREATE ROLE.
        # A more robust check might query system_auth.roles.
        unless      => $unless_command,
        require     => [Exec['change_cassandra_password'], File[$cql_file_path]],
      }
    }
  }
}
`.trim();
