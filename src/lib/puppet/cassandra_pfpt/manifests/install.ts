
export const install = `
# @summary Handles package installation for Cassandra and dependencies.
class cassandra_pfpt::install inherits cassandra_pfpt {
  user { $user:
    ensure     => 'present',
    system     => true,
  }
  group { $group:
    ensure => 'present',
    system => true,
  }
  if $manage_repo {
    if $facts['os']['family'] == 'RedHat' {
      $os_release_major = regsubst($facts['os']['release']['full'], '^(\\\\d+).*$', '\\\\1')
      yumrepo { 'cassandra':
        descr               => "Apache Cassandra \\\${cassandra_version} for EL\\\${os_release_major}",
        baseurl             => $repo_baseurl,
        enabled             => 1,
        gpgcheck            => $repo_gpgcheck,
        gpgkey              => $repo_gpgkey,
        priority            => $repo_priority,
        skip_if_unavailable => $repo_skip_if_unavailable,
        sslverify           => $repo_sslverify,
        require             => Group[$group],
      }
    }
    # Add logic for other OS families like Debian if needed
  }
  package { $package_dependencies:
    ensure  => 'present',
    require => Class['cassandra_pfpt::java'],
  }
  $cassandra_ensure = $cassandra_version ? {
    undef   => 'present',
    default => $cassandra_version,
  }
  package { 'cassandra':
    ensure  => $cassandra_ensure,
    require => [ Class['cassandra_pfpt::java'], User[$user], Group[$group], Yumrepo['cassandra'] ],
    before  => Class['cassandra_pfpt::config'],
  }
  package { 'cassandra-tools':
    ensure  => $cassandra_ensure,
    require => Package['cassandra'],
  }
}
`.trim();
