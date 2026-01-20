# cassandra_pfpt

This is the main component module for installing, configuring, and managing Apache Cassandra. It is designed to be highly parameterized and should receive its configuration from a profile class.

## Description

This module handles the core technical implementation for a Cassandra node. Its responsibilities include:

- **Installation:** Manages the installation of the Cassandra package and its dependencies (like `jq`, `awscli`, and Java).
- **Configuration:** Manages all primary configuration files, such as `cassandra.yaml`, `jvm-server.options`, `cassandra-rackdc.properties`, and JMX access/password files. All settings are parameterized and intended to be passed in from a profile.
- **Service Management:** Manages the `cassandra` systemd service, including its lifecycle and restart behavior on config changes.
- **System-Level Tuning:** Applies necessary system tunings via `sysctl` and sets user limits (`ulimit`) required for production performance.
- **Script Deployment:** Deploys a suite of operational shell and Python scripts to `/usr/local/bin` to aid in day-2 operations.
- **Optional Agent Management:** Includes logic for optionally deploying and configuring the Prometheus JMX Exporter and the Coralogix agent.

## Usage

This class should **not be declared directly** in a node's classification. It is designed to be wrapped by a profile module (like `profile_cassandra_pfpt`) which provides its configuration data via Hiera. This separation of concerns ensures that the component module remains data-agnostic and reusable.
