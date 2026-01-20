# role_cassandra_pfpt

This module is a Puppet role that defines a complete Cassandra server.

## Description

This is a simple role class that includes the `profile_cassandra_pfpt` class. Its purpose is to define a machine as a "Cassandra Server".

## Usage

To apply this role to a node, you would typically classify the node with this class in your node classifier (e.g., Puppet Enterprise Console, Foreman) or in a `nodes.pp` file.

```puppet
node 'cassandra-node-01.example.com' {
  include role_cassandra_pfpt
}
```
