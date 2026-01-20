class profile_cassandra_pfpt {
  # This profile wraps the component module and provides data via Hiera.
  # The actual parameters would be looked up from Hiera data.
  class { 'cassandra_pfpt':
    # Parameters would be supplied by Hiera, e.g.:
    # package_name => hiera('cassandra_pfpt::package_name', 'cassandra'),
    # service_name => hiera('cassandra_pfpt::service_name', 'cassandra'),
  }
}
