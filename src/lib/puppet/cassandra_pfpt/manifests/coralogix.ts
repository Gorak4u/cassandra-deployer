
export const coralogix = `
# @summary Manages Coralogix agent installation and configuration.
class cassandra_pfpt::coralogix inherits cassandra_pfpt {
  if \$facts['os']['family'] == 'RedHat' {
    \$repo_url = \$coralogix_baseurl ? {
      undef   => 'https://yum.coralogix.com/coralogix-el8-x86_64',
      default => \$coralogix_baseurl,
    }
    yumrepo { 'coralogix':
      ensure   => 'present',
      baseurl  => \$repo_url,
      descr    => 'coralogix repo',
      enabled  => 1,
      gpgcheck => 0,
    }
    package { 'coralogix-agent':
      ensure  => 'installed',
      require => Yumrepo['coralogix'],
    }
    file { '/etc/coralogix/agent.conf':
      ensure  => 'file',
      content => template('cassandra_pfpt/coralogix-agent.conf.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0640',
      require => Package['coralogix-agent'],
      notify  => Service['coralogix-agent'],
    }
    service { 'coralogix-agent':
      ensure    => 'running',
      enable    => true,
      hasstatus => true,
      require   => File['/etc/coralogix/agent.conf'],
    }
  }
}
`.trim();
