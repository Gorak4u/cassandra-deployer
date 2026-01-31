# Jenkins Setup Guide: Creating Granular Cassandra Operations Jobs

This guide explains how to use the individual `Jenkinsfile` scripts in the `jenkins/` directory to create separate, dedicated pipeline jobs for each major Cassandra operation in your Jenkins instance.

This approach ensures that each job only displays the parameters relevant to its specific task, making the process cleaner and less error-prone for operators.

## Prerequisites

1.  **Jenkins Instance**: A running Jenkins server.
2.  **Required Plugins**:
    *   `Pipeline`: This is the core plugin for running `Jenkinsfile` scripts.
    *   `SSH Agent`: Required for securely managing the SSH key that connects to your Cassandra nodes.
3.  **Jenkins Agent**: A configured Jenkins agent (worker node) that can connect to your Cassandra cluster.
4.  **Scripts on Agent**: You must ensure the `scripts` directory from this project is manually placed on the Jenkins agent at a known path. All provided `Jenkinsfile` scripts assume the path is `/Users/ggonda/cassandra-tools/scripts`.

---

## Setting Up the Jobs

You will repeat the following process for each operation you want to create a job for (e.g., "Cassandra-Rolling-Restart", "Cassandra-Join-DCs", etc.).

### Step 1: Create a New Job

1.  From the Jenkins dashboard, click **New Item**.
2.  Enter a descriptive name for the job (e.g., `Cassandra-Rolling-Restart`).
3.  Select **Pipeline** as the job type and click **OK**.

### Step 2: Configure the Pipeline Script

This guide assumes you are **not** using a Git repository and will paste the script content directly.

1.  On the configuration page, scroll down to the **Pipeline** section.
2.  The **Definition** dropdown should be set to **Pipeline script**.
3.  In the `jenkins/` directory of this project, open the `Jenkinsfile` that corresponds to the job you are creating (e.g., for "Cassandra-Rolling-Restart", open `Jenkinsfile.rolling_restart`).
4.  Copy the entire content of that file.
5.  Paste the copied content into the **Script** text area in the Jenkins UI.

### Step 3: Verify the Script Path

Double-check the `SCRIPTS_PATH` variable at the top of the script you just pasted. Ensure it matches the location where your `cassy.sh` and other scripts are located on the Jenkins agent machine.

```groovy
// At the top of the Jenkinsfile
def SCRIPTS_PATH = '/Users/ggonda/cassandra-tools/scripts' // <-- VERIFY THIS PATH
```

### Step 4: Save the Job

*   Click the **Save** button at the bottom of the page.

### Step 5: Repeat for Other Operations

Repeat steps 1-4 for each of the following operations, using the corresponding `Jenkinsfile` from the `jenkins/` directory:

| Jenkins Job Name (Suggestion) | Jenkinsfile to Use | Description |
|---|---|---|
| `Cassandra-Rolling-Restart` | `Jenkinsfile.rolling_restart` | Performs a safe, rolling restart of the Cassandra service. |
| `Cassandra-Rolling-Reboot` | `Jenkinsfile.rolling_reboot` | Performs a safe, rolling reboot of the nodes. |
| `Cassandra-Rolling-Puppet` | `Jenkinsfile.rolling_puppet_run`| Performs a rolling Puppet agent run. |
| `Cassandra-Join-DCs` | `Jenkinsfile.join_dcs` | Orchestrates joining a new datacenter to an existing cluster. |
| `Cassandra-Split-DCs` | `Jenkinsfile.split_dcs` | Orchestrates splitting a multi-DC cluster into two. |
| `Cassandra-Rename-Cluster` | `Jenkinsfile.rename_cluster` | Orchestrates a full cluster rename (requires downtime). |
| `Cassandra-Generic-Command`| `Jenkinsfile.generic_command` | Runs any ad-hoc `cass-ops` command. |

---

## Running a Job

Once a job is created, running it is straightforward:

1.  Go to the job's main page in Jenkins (e.g., `Cassandra-Rolling-Restart`).
2.  Click on **Build with Parameters** in the left-hand sidebar.
3.  You will now see a concise list of parameters relevant **only to that specific operation**.
4.  Fill in the parameters as needed and click the **Build** button.

The pipeline will start, and you can monitor its progress in the "Build History" and view detailed logs in the "Console Output".
