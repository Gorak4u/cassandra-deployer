# profile_cassandra_pfpt

This module is a Puppet profile that wraps the `cassandra_pfpt` component module. Its purpose is to provide configuration data to the component module via Hiera lookups.

## Description

This profile class defines the "what" for a Cassandra node. It looks up all the necessary parameters using `lookup()` and passes them to the `cassandra_pfpt` class. This separates the logic of *how* to manage Cassandra (the component module) from *what* configuration to apply (the profile).

## Usage

This class is typically included by a role class (`role_cassandra_pfpt`). You can customize the behavior of the Cassandra installation by setting values in your Hiera data, prefixed with `profile_cassandra_pfpt::`.
