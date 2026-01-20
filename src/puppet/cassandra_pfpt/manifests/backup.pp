# Class: cassandra_pfpt::backup
#
# This class manages backup scripts and schedules.
#
class cassandra_pfpt::backup {
  # This class is only active if backups are enabled
  if $cassandra_pfpt::backup_enabled {
    file { '/etc/backup':
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }

    file { '/etc/backup/config.json':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('cassandra_pfpt/backup.json.erb'),
      require => File['/etc/backup'],
    }

    $backup_scripts = [
      'full-backup-to-s3.sh',
      'incremental-backup-to-s3.sh',
    ]

    $backup_scripts.each |String $script| {
      file { "/usr/local/bin/${script}":
        ensure => file,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
        source => "puppet:///modules/cassandra_pfpt/${script}",
      }
    }

    cron { 'cassandra-full-backup':
      command => '/usr/local/bin/full-backup-to-s3.sh',
      user    => 'root',
      hour    => $cassandra_pfpt::full_backup_hour,
      minute  => $cassandra_pfpt::full_backup_minute,
      require => File['/usr/local/bin/full-backup-to-s3.sh'],
    }

    cron { 'cassandra-incremental-backup':
      command => '/usr/local/bin/incremental-backup-to-s3.sh',
      user    => 'root',
      minute  => $cassandra_pfpt::incremental_backup_minute,
      require => File['/usr/local/bin/incremental-backup-to-s3.sh'],
    }
  }
}
