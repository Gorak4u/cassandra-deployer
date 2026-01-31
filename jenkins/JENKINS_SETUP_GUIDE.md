# Jenkins Setup Guide for Cassandra Operations

This guide provides step-by-step instructions for creating all the necessary Jenkins pipeline jobs to manage your Cassandra cluster using the orchestration scripts in this repository.

We will use a **seed job**. This is a special Jenkins job that automatically creates all the other jobs for you based on the `seed.groovy.txt` script. This approach is powerful because it keeps all your job definitions in one place and ensures they are "Pipeline as Code".

## Prerequisites

1.  **Jenkins Instance**: A running Jenkins instance.
2.  **Job DSL Plugin**: The "Job DSL" plugin must be installed on your Jenkins instance.
    *   Go to `Manage Jenkins` > `Plugins` > `Available plugins`.
    *   Search for and install `Job DSL`.
3.  **Git Repository**: This project must be available in a Git repository that your Jenkins instance can access.
4.  **SSH Key Access**: The Jenkins agent must have passwordless SSH access to the Cassandra nodes.

---

## Step 1: Create the Seed Job

The seed job is a special job that will create all the other operational jobs. You only have to create this one job manually.

1.  From the Jenkins dashboard, click **New Item**.
2.  Enter a name for the job, for example, `Cassandra-Seed-Job`.
3.  Select **Freestyle project** and click **OK**.
4.  On the configuration page, scroll down to the **Build Steps** section.
5.  Click **Add build step** and select **Process Job DSLs**.
6.  Select the **Use the provided DSL script** radio button.
7.  Copy the entire content of the `jenkins/seed.groovy.txt` file from this project and paste it into the **DSL Script** text area in Jenkins.
8.  Click **Save**.

---

## Step 2: Approve the Script Signature (Security Step)

For security reasons, Jenkins requires an administrator to approve any new Groovy script that is run directly in the UI.

1.  Run the `Cassandra-Seed-Job` once. **It is expected to fail** with an error message like `script not yet approved for use`.
2.  Go to **Manage Jenkins** > **In-process Script Approval**.
3.  You will see the signature of the `seed.groovy.txt` script listed. Click the **Approve** button.

This tells Jenkins that you trust this specific script to be run within your environment.

> **Note:** If you ever modify the contents of the `seed.groovy.txt` script in the Jenkins job configuration, you will need to repeat this approval step for the new script signature.

---

## Step 3: Run the Seed Job

Now that the script is approved, you can run the seed job to generate all your Cassandra operation jobs.

1.  Go to the dashboard for your `Cassandra-Seed-Job`.
2.  Click **Build Now**.
3.  After the build completes (it should be very fast and marked as successful), go back to the main Jenkins dashboard and refresh the page.

You will now see a new folder on your dashboard named `Cassandra`. Inside this folder are all the generated pipeline jobs.

---

## Step 4: Configure SCM for the Generated Jobs

The generated jobs are pipeline jobs that need to check out the code from your Git repository. You need to configure this for each job.

1.  Click on the `Cassandra` folder.
2.  Click on a job (e.g., `Cassandra - Restart`), and then click **Configure**.
3.  Go to the **Pipeline** section.
4.  Under **Definition**, select **Pipeline script from SCM**.
5.  Select **Git** from the SCM dropdown.
6.  Enter your repository URL (e.g., `https://github.com/your-org/cassandra-tools.git`) and configure any necessary credentials.
7.  Ensure the **Script Path** is `Jenkinsfile` (this is the default).
8.  Click **Save**.

> **Note:** The seed job generates jobs that reference a `Jenkinsfile`. You will need to create this `Jenkinsfile` at the root of your repository with the pipeline definition provided by the seed job. A more advanced setup would have the seed job create the jobs with the script source inline, but this approach keeps the job definitions version-controlled with your code.

---

## Step 5: Use the Operational Jobs

The jobs are now ready to use.

1.  Go to a configured job (e.g., `Cassandra - Restart`).
2.  Click **Build with Parameters**.
3.  Fill in the parameters relevant to the operation.
4.  Click **Build**.

The Jenkins job will now check out your repository and execute the corresponding script, orchestrating the operation across your cluster.
