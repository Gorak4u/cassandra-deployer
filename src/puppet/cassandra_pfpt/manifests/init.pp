# Manages the core components of Cassandra, including packages, config, and service.
class cassandra_pfpt (
  # This parameter receives the JSON content for the backup config file.
  # It's marked as Sensitive because it contains the key.
  Sensitive[String] $backup_config_content,
) {

  # This is a placeholder for all the other resources this module would manage,
  # like packages, the main cassandra.yaml config, the service, etc.

  # Ensure the /etc/backup directory exists
  file { '/etc/backup':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Manage the backup configuration file itself
  file { '/etc/backup/config.json':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600', # Restrictive permissions as it contains the key
    content => $backup_config_content,
    require => File['/etc/backup'],
  }
}
