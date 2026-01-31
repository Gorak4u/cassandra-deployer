# Jenkins Setup Guide for Cassandra Operations

This guide provides step-by-step instructions for creating all the necessary Jenkins pipeline jobs to manage your Cassandra cluster using the provided orchestration scripts.

We will use a **seed job**. This is a special Jenkins job that automatically creates all the other jobs for you based on the `Jenkinsfile.*` templates in this directory.

## Prerequisites

1.  **Jenkins Instance**: A running Jenkins instance.
2.  **Job DSL Plugin**: The "Job DSL" plugin must be installed on your Jenkins instance.
    *   Go to `Manage Jenkins` > `Plugins` > `Available plugins`.
    *   Search for and install `Job DSL`.
3.  **Local Scripts**: The `cassandra-tools` directory, containing both the `scripts/` and `jenkins/` subdirectories, must be placed at the following absolute path on your Jenkins agent machine (in this case, your macOS machine):
    *   `/Users/ggonda/cassandra-tools/`

    Your directory structure must be:
    ```
    /Users/ggonda/cassandra-tools/
    ├── jenkins/
    │   ├── Jenkinsfile.command
    │   ├── Jenkinsfile.join
    │   └── seed.groovy
    └── scripts/
        ├── cassy.sh
        └── ...
    ```

---

## Step 1: Create the Seed Job

The seed job is a special job that will create all the other operational jobs. You only have to create this one job manually.

1.  From the Jenkins dashboard, click **New Item**.
2.  Enter a name for the job, for example, `Cassandra-Seed-Job`.
3.  Select **Freestyle project** and click **OK**.
4.  On the configuration page, scroll down to the **Build Steps** section.
5.  Click **Add build step** and select **Process Job DSLs**.
6.  Select the **Use the provided DSL script** radio button.
7.  Copy the entire content of the `jenkins/seed.groovy` file from this project and paste it into the **DSL Script** text area in Jenkins.
8.  Click **Save**.

---

## Step 2: Run the Seed Job

Now that the seed job is created, you can run it to generate all your Cassandra operation jobs.

1.  Go to the dashboard for your `Cassandra-Seed-Job`.
2.  Click **Build Now**.
3.  After the build completes (it should be very fast), go back to the main Jenkins dashboard.

You will now see a new folder (or a new set of jobs) on your dashboard, such as:
*   `Cassandra - Reboot`
*   `Cassandra - Restart`
*   `Cassandra - Join`
*   `Cassandra - Split`
*   `Cassandra - Rename`
*   `Cassandra - Puppet-run`
*   `Cassandra - Command`

---

## Step 3: Use the Operational Jobs

You can now use these newly created jobs to perform operations.

1.  Click on any of the generated jobs (e.g., `Cassandra - Restart`).
2.  Click **Build with Parameters**.
3.  Fill in the parameters relevant to the operation (e.g., the `QV_QUERY` for the nodes you want to restart).
4.  Click **Build**.

The Jenkins job will execute the corresponding script (`cassy.sh --rolling-op restart` in this case) on the Jenkins agent, orchestrating the operation across your cluster.
