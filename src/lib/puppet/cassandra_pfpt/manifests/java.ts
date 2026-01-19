
export const java = `
# @summary Manages Java installation for Cassandra.
class cassandra_pfpt::java inherits cassandra_pfpt {
  if $java_package_name and $java_package_name != '' {
    $actual_java_package = $java_package_name
  } else {
    $actual_java_package = $java_version ? {
      '8'     => 'java-1.8.0-openjdk-headless',
      '11'    => 'java-11-openjdk-headless',
      '17'    => 'java-17-openjdk-headless',
      default => "java-\\\${java_version}-openjdk-headless",
    }
  }
  package { $actual_java_package:
    ensure  => 'present',
  }
}
`.trim();
