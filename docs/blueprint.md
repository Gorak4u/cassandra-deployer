# **App Name**: Cassandra Deployer

## Core Features:

- OS-Agnostic Package Installation: Install Cassandra using package manager that's specific to the underlying operating system.
- Java installation: Installation of Java JRE/JDK to enable running cassandra in the machine.
- Dynamic Configuration: Apply configurations to cassandra instances from pre-existing templates. This setup shall also be dynamically customisable, depending on system parameters (OS distribution and version) using hiera.
- Manage Cassandra Service: Start, stop, restart, and check the status of the Cassandra service.  Includes logic to handle different service management tools (e.g., systemd, init.d).

## Style Guidelines:

- Primary color: Deep Indigo (#3F51B5), representing stability and reliability, core characteristics of Cassandra.
- Background color: Light Gray (#F5F5F5), a neutral backdrop to ensure readability and focus.
- Accent color: Cyan (#00BCD4), providing a modern, tech-centric highlight for interactive elements and key information.
- Font: 'Inter', a grotesque-style sans-serif providing a modern, machined, objective look; suitable for headlines and body text.