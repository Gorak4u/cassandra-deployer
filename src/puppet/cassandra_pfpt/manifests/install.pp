# @summary Manages Cassandra repository and package installation.
class cassandra_pfpt::install {
  if $cassandra_pfpt::manage_repo {
    yumrepo { 'cassandra':
      ensure   => 'present',
      baseurl  => $cassandra_pfpt::repo_baseurl,
      descr    => "Apache Cassandra",
      enabled  => 1,
      gpgcheck => $cassandra_pfpt::repo_gpgcheck ? 1 : 0,
      gpgkey   => $cassandra_pfpt::repo_gpgkey,
      priority => $cassandra_pfpt::repo_priority,
      skip_if_unavailable => $cassandra_pfpt::repo_skip_if_unavailable,
      sslverify => $cassandra_pfpt::repo_sslverify,
    }
  }

  if ! empty($cassandra_pfpt::package_dependencies) {
    package { $cassandra_pfpt::package_dependencies:
      ensure => 'installed',
    }
  }

  $repo_require = $cassandra_pfpt::manage_repo ? {
    true    => [Yumrepo['cassandra']],
    default => [],
  }

  package { 'cassandra':
    ensure  => $cassandra_pfpt::cassandra_version,
    require => Class['cassandra_pfpt::java'] + Package[$cassandra_pfpt::package_dependencies] + $repo_require,
  }
}
