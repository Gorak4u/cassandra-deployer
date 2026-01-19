
# @summary Manages scheduled backups for Cassandra using DIY scripts.
class cassandra_pfpt::backup(
  String $full_backup_schedule,
  String $incremental_backup_schedule,
  String $backup_s3_bucket,
  String $full_backup_script_path,
  String $incremental_backup_script_path,
) {
  # This class assumes the backup scripts themselves are managed by the main config class.

  # --- Full Backup Service & Timer ---
  file { '/etc/systemd/system/cassandra-full-backup.service':
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('cassandra_pfpt/cassandra-full-backup.service.erb'),
    notify  => Exec['cassandra-backup-systemd-reload'],
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

  # --- Incremental Backup Service & Timer ---
  file { '/etc/systemd/system/cassandra-incremental-backup.service':
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('cassandra_pfpt/cassandra-incremental-backup.service.erb'),
    notify  => Exec['cassandra-backup-systemd-reload'],
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

  # --- Shared Systemd Reload ---
  exec { 'cassandra-backup-systemd-reload':
    command     => 'systemctl daemon-reload',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
  }
}
