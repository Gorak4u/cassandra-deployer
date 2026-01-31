# Jenkins Setup Guide: Automated Job Creation with a Seed Job

This guide explains how to use a **seed job** to automatically create all the necessary Jenkins pipeline jobs for managing your Cassandra cluster. This is the recommended "Pipeline as Code" approach, as it allows you to manage all your job definitions in one place.

## Prerequisites

1.  **Jenkins Instance**: A running Jenkins server.
2.  **Required Plugins**:
    *   `Pipeline`: This is the core plugin for running `Jenkinsfile` scripts.
    *   `SSH Agent`: Required for securely managing the SSH key that connects to your Cassandra nodes.
    *   **`Job DSL`**: This is the most important one. You must install it from the "Manage Jenkins" > "Plugins" section of your Jenkins instance. It provides the ability to run Groovy scripts to create jobs.
3.  **Scripts on Agent**: You must ensure the entire `cassandra-tools` project directory is placed on your Jenkins agent at `/Users/ggonda/cassandra-tools`.

---

## Setting Up the Seed Job

You will create **only one job** manually. This "seed job" will then automatically create all the other operational jobs for you.

### Step 1: Create the Seed Job

1.  From the Jenkins dashboard, click **New Item**.
2.  Enter a name for the seed job, for example, `Cassandra-Jobs-Seed`.
3.  Select **Freestyle project** as the job type and click **OK**. Do **not** select "Pipeline".

### Step 2: Configure the Workspace

Since you are not using Git, we need to tell the seed job where to find the scripts on the agent machine.

1.  On the job configuration page, under the **General** tab, click the **Advanced...** button.
2.  Check the box for **Use custom workspace**.
3.  In the **Directory** field, enter the absolute path to your project folder: `/Users/ggonda/cassandra-tools`.

This tells Jenkins to run this job from within that directory, allowing it to find the `jenkins/seed.groovy` script.

### Step 3: Configure the DSL Build Step

1.  Scroll down to the **Build Steps** section.
2.  Click **Add build step** and select **Process Job DSLs**.
3.  In the DSL configuration that appears, select the radio button for **Use the provided DSL script**.
4.  A text box will appear. Copy the entire content of the `jenkins/seed.groovy` file from this project and paste it into that text box.

### Step 4: Save and Run the Seed Job

1.  Click the **Save** button at the bottom of the page.
2.  You will be taken to the `Cassandra-Jobs-Seed` job page. Click **Build Now** in the left-hand sidebar.
3.  The job will run quickly. After it succeeds, go back to your main Jenkins dashboard.

You will now see a set of new pipeline jobs, such as `Cassandra-Rolling-Restart`, `Cassandra-Join-DCs`, etc., all created and configured automatically.

---

## Running an Operational Job

Once the seed job has run, using the generated jobs is straightforward:

1.  Go to the job's main page in Jenkins (e.g., `Cassandra-Rolling-Restart`).
2.  Click on **Build with Parameters** in the left-hand sidebar.
3.  You will now see a concise list of parameters relevant **only to that specific operation**.
4.  Fill in the parameters as needed and click the **Build** button.
