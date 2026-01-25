# Puppet Architecture: A Deep Dive into Cassandra Automation

This document provides a comprehensive overview of the Puppet architecture used to deploy, configure, and manage your Cassandra cluster. Understanding this structure is key to extending the automation, troubleshooting issues, and managing configuration effectively.

---

## Table of Contents

1.  [**Core Philosophy: Roles and Profiles**](#1-core-philosophy-roles-and-profiles)
2.  [**The Layered Architecture**](#2-the-layered-architecture)
    - [Layer 1: The Role (`role_cassandra_pfpt`) - The "What"](#layer-1-the-role-role_cassandra_pfpt---the-what)
    - [Layer 2: The Profile (`profile_cassandra_pfpt`) - The "How"](#layer-2-the-profile-profile_cassandra_pfpt---the-how)
    - [Layer 3: The Component (`cassandra_pfpt`) - The "Technical Implementation"](#layer-3-the-component-cassandra_pfpt---the-technical-implementation)
3.  [**Hiera: The Data Layer**](#3-hiera-the-data-layer)
4.  [**Operational Tooling: The `files` Directory**](#4-operational-tooling-the-files-directory)
5.  [**Architecture Diagram**](#5-architecture-diagram)

---

## 1. Core Philosophy: Roles and Profiles

This repository follows the standard Puppet **"Roles and Profiles"** design pattern. This pattern separates the concerns of what a machine *is* (its role) from *how* that role is implemented (its profile), and the technical details of the implementation (the component modules).

This results in a system that is highly modular, reusable, and easy to maintain.

## 2. The Layered Architecture

Our setup consists of three distinct Puppet modules, each with a specific responsibility.

### Layer 1: The Role (`role_cassandra_pfpt`) - The "What"

This is the simplest and highest-level module. Its **only job** is to declare what a server's function is.

-   **Purpose**: To classify a node. It answers the question, "What is this server?" The answer is, "It's a Cassandra server."
-   **Implementation**: The `init.pp` in this module contains a single line: `include profile_cassandra_pfpt`.
-   **Usage**: In your node classifier (like the Puppet Enterprise Console or a `nodes.pp` file), you assign `role_cassandra_pfpt` to a machine. You never assign a profile or component module directly.

### Layer 2: The Profile (`profile_cassandra_pfpt`) - The "How"

The profile module acts as the crucial intermediary layer. It defines *how* to build a Cassandra server within your specific environment.

-   **Purpose**: To compose one or more component modules and provide them with data from Hiera. It bridges the gap between your business requirements (e.g., "all Cassandra nodes must have backups enabled") and the technical implementation.
-   **Implementation**:
    -   The `init.pp` of this module uses `lookup()` functions to pull all configuration values from your Hiera data.
    -   It then declares the `class { 'cassandra_pfpt': ... }`, passing all the looked-up values as parameters.
    -   It acts as an "API" for your infrastructure, exposing a clean, prefixed set of Hiera keys (e.g., `profile_cassandra_pfpt::cluster_name`).

### Layer 3: The Component (`cassandra_pfpt`) - The "Technical Implementation"

This is the "engine" of the automation. It contains all the detailed Puppet code that manages the resources on the server.

-   **Purpose**: To perform the low-level technical tasks required to manage a piece of software, completely independent of your specific environment's data. It is reusable and could be used to manage Cassandra in a different company with a different Hiera structure by simply writing a new profile.
-   **Implementation**:
    -   It defines parameters for every configurable option (e.g., `String $cluster_name`). It **never** contains a `lookup()` function.
    -   The `manifests/` directory contains all the Puppet classes that manage packages, files, and services (`install.pp`, `config.pp`, `service.pp`).
    -   The `templates/` directory contains all the `.erb` files used to generate configuration files (`cassandra.yaml.erb`, `jvm-server.options.erb`).
    -   The `files/` directory contains all the static files and operational scripts (`cass-ops`, backup scripts, documentation) that are deployed to the node.

## 3. Hiera: The Data Layer

Hiera is the source of truth for all configuration data. The "Roles and Profiles" pattern relies on Hiera to inject data at the profile layer.

This provides a powerful separation of code from data. To change a setting—like the cluster name or the JVM heap size—you **never edit the Puppet code**. You only edit a YAML file in your Hiera data hierarchy.

**Example Data Flow:**

1.  **Hiera Data (`common.yaml`)**:
    ```yaml
    profile_cassandra_pfpt::max_heap_size: '12G'
    ```
2.  **Profile Module (`profile_cassandra_pfpt/manifests/init.pp`)**:
    ```puppet
    $max_heap_size = lookup('profile_cassandra_pfpt::max_heap_size', { 'default_value' => '3G' })
    
    class { 'cassandra_pfpt':
      max_heap_size => $max_heap_size,
      # ... other parameters
    }
    ```
3.  **Component Module (`cassandra_pfpt/templates/jvm-server.options.erb`)**:
    ```erb
    # Heap size
    -Xms<%= @max_heap_size %>
    -Xmx<%= @max_heap_size %>
    ```
4.  **Resulting File on Node (`/etc/cassandra/conf/jvm-server.options`)**:
    ```
    # Heap size
    -Xms12G
    -Xmx12G
    ```

## 4. Operational Tooling: The `files` Directory

The `files/` directory within the `cassandra_pfpt` component module is where all the operational shell scripts, Python scripts, and static configuration files are stored.

-   The **component** module (`cassandra_pfpt`) is responsible for *deploying* these files to the correct location on the server (e.g., `/usr/local/bin`).
-   The **profile** module (`profile_cassandra_pfpt`) is responsible for *integrating* them into the system by, for example, creating `cron` jobs or `systemd` timers that call these scripts.

## 5. Architecture Diagram

This diagram illustrates the flow of control and data:

```
      +----------------------------+
      | Node Classification (e.g.,|
      | Puppet Enterprise Console) |
      +-------------+--------------+
                    |
                    | Assigns Role
                    v
      +-------------+--------------+      +--------------------------+
      |     Role Module            |      |      Hiera Data          |
      |   (role_cassandra_pfpt)    |      | (e.g., common.yaml)      |
      +-------------+--------------+      +------------+-------------+
                    |                                  |
                    | includes                         | supplies data via lookup()
                    v                                  v
      +-------------+--------------+      +------------+-------------+
      |    Profile Module          |------>|      Parameter Hash      |
      | (profile_cassandra_pfpt)   |      +--------------------------+
      +-------------+--------------+
                    |
                    | declares class with parameters
                    v
      +-------------+--------------+
      |   Component Module         |
      |     (cassandra_pfpt)       |
      | (manages files, pkgs, svcs)|
      +----------------------------+
```
