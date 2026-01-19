
# @summary Manages scheduled backups for Cassandra using a DIY script.
class cassandra_pfpt::backup inherits cassandra_pfpt {
  # This class is responsible for creating the backup configuration and
  # scheduling the execution of the backup scripts.

  # Create the backup configuration directory and file
  file { '/etc/backup':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }
  file { '/etc/backup/config.json':
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('cassandra_pfpt/backup.config.json.erb'),
    require => File['/etc/backup'],
  }

  if $manage_full_backups {
    # Full Backup Service and Timer
    file { '/etc/systemd/system/cassandra-full-backup.service':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/cassandra-full-backup.service.erb'),
      notify  => Exec['cassandra-backup-systemd-reload'],
      require => File['/etc/backup/config.json'],
    }
    file { '/etc/systemd/system/cassandra-full-backup.timer':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/cassandra-full-backup.timer.erb'),
      notify  => Service['cassandra-full-backup.timer'],
    }
    service { 'cassandra-full-backup.timer':
      ensure  => 'running',
      enable  => true,
      require => [
        File['/etc/systemd/system/cassandra-full-backup.service'],
        File['/etc/systemd/system/cassandra-full-backup.timer'],
      ],
    }
  }

  if $manage_incremental_backups {
    # Incremental Backup Service and Timer
    file { '/etc/systemd/system/cassandra-incremental-backup.service':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/cassandra-incremental-backup.service.erb'),
      notify  => Exec['cassandra-backup-systemd-reload'],
      require => File['/etc/backup/config.json'],
    }
    file { '/etc/systemd/system/cassandra-incremental-backup.timer':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/cassandra-incremental-backup.timer.erb'),
      notify  => Service['cassandra-incremental-backup.timer'],
    }
    service { 'cassandra-incremental-backup.timer':
      ensure  => 'running',
      enable  => true,
      require => [
        File['/etc/systemd/system/cassandra-incremental-backup.service'],
        File['/etc/systemd/system/cassandra-incremental-backup.timer'],
      ],
    }
  }

  # Common daemon-reload exec, triggered by any service file change.
  # This only runs if at least one of the backup types is enabled.
  exec { 'cassandra-backup-systemd-reload':
    command     => 'systemctl daemon-reload',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
  }
}
