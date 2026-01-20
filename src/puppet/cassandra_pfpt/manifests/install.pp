# @summary Manages the installation of Cassandra and its dependencies.
class cassandra_pfpt::install inherits cassandra_pfpt {

  # Ensure dependencies are installed
  if !empty($package_dependencies) {
    package { $package_dependencies:
      ensure => 'installed',
    }
  }

  if $manage_repo {
    if $facts['os']['family'] == 'RedHat' {
      yumrepo { 'cassandra':
        ensure   => 'present',
        baseurl  => $repo_baseurl,
        descr    => 'Apache Cassandra',
        enabled  => 1,
        gpgcheck => $repo_gpgcheck ? 1 : 0,
        gpgkey   => $repo_gpgkey,
        priority => $repo_priority,
        skip_if_unavailable => $repo_skip_if_unavailable ? 1 : 0,
        sslverify => $repo_sslverify ? 1 : 0,
      }
      $repo_require = Yumrepo['cassandra']
    } elsif $facts['os']['family'] == 'Debian' {
      # Placeholder for Debian/Ubuntu repo management
      # You would use apt::source and apt::key here
      $repo_require = undef
    } else {
      fail("Unsupported OS family: ${facts['os']['family']}")
    }
  } else {
    $repo_require = undef
  }

  package { 'cassandra':
    ensure  => $cassandra_version,
    require => $repo_require,
    before  => Class['cassandra_pfpt::config'],
  }
}
