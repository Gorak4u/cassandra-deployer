# @summary Manages Java installation for Cassandra.
class cassandra_pfpt::java {
  if $cassandra_pfpt::java_package_name {
    package { $cassandra_pfpt::java_package_name:
      ensure => installed,
    }
  } else {
    # Basic logic for OpenJDK, assumes RedHat family OS.
    $java_pkg = $cassandra_pfpt::java_version ? {
      '11'    => 'java-11-openjdk-devel',
      '8'     => 'java-1.8.0-openjdk-devel',
      default => fail("Unsupported Java version for automatic package selection: ${cassandra_pfpt::java_version}"),
    }
    package { $java_pkg:
      ensure => installed,
    }
  }
}
