
export const system_keyspaces = `
# @summary Manages system keyspace replication for multi-DC clusters.
class cassandra_pfpt::system_keyspaces inherits cassandra_pfpt {
  # Only proceed if a replication strategy is defined.
  if !empty($\\
{system_keyspaces_replication}) {
    # The system_keyspaces_replication is a hash like {'dc1' => 3, 'dc2' => 3}
    # We need to convert it to a string like "'dc1': '3', 'dc2': '3'"
    $replication_map_parts = $\\{system_keyspaces_replication}.map |$dc, $rf| {
      "'$\\{dc}':'$\\{rf}'"
    }
    $replication_map_string = join($replication_map_parts, ', ')
    # Define the command to alter keyspaces
    $replication_cql_string = "{'class': 'NetworkTopologyStrategy', $\\{replication_map_string}}"
    $alter_auth_cql = "ALTER KEYSPACE system_auth WITH replication = $\\{replication_cql_string}"
    $alter_dist_cql = "ALTER KEYSPACE system_distributed WITH replication = $\\{replication_cql_string}"
    $alter_traces_cql = "ALTER KEYSPACE system_traces WITH replication = $\\{replication_cql_string}"
    # Use a single check for idempotency. This isn't perfect but is simpler.
    # It checks if the string for system_auth's replication is what we expect.
    $check_command = "cqlsh $\\{cqlsh_ssl_opt} -u cassandra -p '$\\{cassandra_password}' $\\{listen_address} -e \\"DESCRIBE KEYSPACE system_auth;\\" | grep -q \\"replication = $\\{replication_cql_string}\\""
    exec { 'update_system_keyspace_replication':
      command   => "cqlsh $\\{cqlsh_ssl_opt} -u cassandra -p '$\\{cassandra_password}' $\\{listen_address} -e \\"$\\{alter_auth_cql}; $\\{alter_dist_cql}; $\\{alter_traces_cql};\\"",
      path      => ['/bin', '/usr/bin', $\\{cqlsh_path_env}],
      unless    => $check_command,
      logoutput => on_failure,
      require   => Exec['change_cassandra_password'], # Ensure password is set first
    }
  }
}
`.trim();
