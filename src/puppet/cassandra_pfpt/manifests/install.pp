# @summary Manages Cassandra repository and package installation.
class cassandra_pfpt::install {
  if $cassandra_pfpt::manage_repo {
    yumrepo { 'cassandra':
      ensure              => 'present',
      baseurl             => $cassandra_pfpt::repo_baseurl,
      gpgkey              => $cassandra_pfpt::repo_gpgkey,
      gpgcheck            => $cassandra_pfpt::repo_gpgcheck,
      priority            => $cassandra_pfpt::repo_priority,
      enabled             => 1,
      skip_if_unavailable => $cassandra_pfpt::repo_skip_if_unavailable,
      sslverify           => $cassandra_pfpt::repo_sslverify,
    }
    # Ensure repo is configured before trying to install packages from it.
    Yumrepo['cassandra'] -> Package[$cassandra_pfpt::package_dependencies]
    Yumrepo['cassandra'] -> Package['cassandra']
  }

  package { $cassandra_pfpt::package_dependencies:
    ensure => installed,
  }

  package { 'cassandra':
    ensure  => $cassandra_pfpt::cassandra_version,
    require => Package[$cassandra_pfpt::package_dependencies],
  }
}
