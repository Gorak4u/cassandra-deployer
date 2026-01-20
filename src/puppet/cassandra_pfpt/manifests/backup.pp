# @summary Manages Cassandra backup configuration and cron jobs.
class cassandra_pfpt::backup inherits cassandra_pfpt {

  # Common directory for backup configurations
  file { '/etc/backup':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Create a JSON config file for backup scripts to consume
  # This avoids passing many arguments to cron jobs
  file { '/etc/backup/config.json':
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('cassandra_pfpt/backup.config.json.erb'),
  }

  # Manage full backup cron job
  if $manage_full_backups {
    cron { 'cassandra_full_backup':
      ensure      => 'present',
      command     => "${full_backup_script_path} > /dev/null 2>&1",
      user        => 'root',
      minute      => '0',
      hour        => '2',
      weekday     => $full_backup_schedule ? {
        'daily'   => '*',
        'weekly'  => '0',
        default   => fail("Invalid full backup schedule: ${full_backup_schedule}"),
      },
      require     => [
        File[$full_backup_script_path],
        File['/etc/backup/config.json'],
      ],
    }
  } else {
    cron { 'cassandra_full_backup':
      ensure => 'absent',
    }
  }

  # Manage incremental backup cron job
  if $manage_incremental_backups {
    cron { 'cassandra_incremental_backup':
      ensure      => 'present',
      command     => "${incremental_backup_script_path} > /dev/null 2>&1",
      user        => 'root',
      special     => $incremental_backup_schedule,
      require     => [
        File[$incremental_backup_script_path],
        File['/etc/backup/config.json'],
      ],
    }
  } else {
    cron { 'cassandra_incremental_backup':
      ensure => 'absent',
    }
  }
}
