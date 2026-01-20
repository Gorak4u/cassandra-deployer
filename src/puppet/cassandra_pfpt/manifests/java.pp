# @summary Manages Java installation.
class cassandra_pfpt::java {
  if $cassandra_pfpt::java_package_name {
    package { $cassandra_pfpt::java_package_name:
      ensure => 'installed',
    }
  }
}
