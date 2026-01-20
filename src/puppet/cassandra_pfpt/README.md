# cassandra_pfpt

This is the main component module for installing, configuring, and managing Apache Cassandra. It is designed to be highly parameterized and should receive its configuration from a profile class.

## Description

This module handles:
- Installation of the Cassandra package and its dependencies.
- Management of all configuration files (`cassandra.yaml`, `jvm-server.options`, etc.).
- Management of the Cassandra service.
- System-level tuning (`sysctl`, `limits`).
- Deployment of operational scripts for backups, repairs, and health checks.
- Optional management of JMX exporter and Coralogix agents.

## Usage

This class should not be declared directly. Instead, use the `profile_cassandra_pfpt` class to configure and apply it.
