# Jenkins Setup Guide: Creating the Cassandra Operations Pipeline

This guide explains how to use the `Jenkinsfile` in this project to create a parameterized pipeline job in your Jenkins instance.

## Prerequisites

1.  **Jenkins Instance**: A running Jenkins server.
2.  **Required Plugins**:
    *   `Pipeline`: This is the core plugin for running `Jenkinsfile` scripts.
    *   `SSH Agent`: Required for securely managing the SSH key that connects to your Cassandra nodes.
3.  **Jenkins Agent**: A configured Jenkins agent (worker node) that can connect to your Cassandra cluster. It must have **passwordless SSH access** to all Cassandra nodes.
4.  **Scripts on Agent (for non-SCM method)**: If you are not using the Git SCM method, you must ensure the `scripts` directory from this project is manually placed on the Jenkins agent at a known path (e.g., `/opt/cassandra-tools/scripts`).

---

## Method 1: Pipeline from SCM (Recommended)

This is the standard and best-practice approach. It links your Jenkins job directly to your Git repository, so any updates to the `Jenkinsfile` in Git are automatically used by the job.

1.  **Create a New Job**:
    *   From the Jenkins dashboard, click **New Item**.
    *   Enter a name for your job (e.g., `Cassandra-Operations`).
    *   Select **Pipeline** as the job type and click **OK**.

2.  **Configure the Pipeline**:
    *   On the configuration page, scroll down to the **Pipeline** section.
    *   From the **Definition** dropdown, select **Pipeline script from SCM**.
    *   In the **SCM** section that appears, select **Git**.
    *   **Repository URL**: Enter the URL of your Git repository (e.g., `https://github.com/your-org/your-repo.git`).
    *   **Credentials**: Select the appropriate credentials if your repository is private.
    *   **Branch Specifier**: Ensure this is set to the correct branch (e.g., `*/main`).
    *   **Script Path**: This should be `Jenkinsfile` by default, which is correct for our project structure.

3.  **Save the Job**:
    *   Click the **Save** button at the bottom of the page.

Your job is now configured. When you run it, Jenkins will pull the code from your repository, read the `Jenkinsfile`, and execute the pipeline.

---

## Method 2: Direct Pipeline Script (Without SCM)

Use this method if you are not using a Git repository or if you prefer to manage the pipeline script directly in the Jenkins UI.

1.  **Create a New Job**:
    *   From the Jenkins dashboard, click **New Item**.
    *   Enter a name for your job (e.g., `Cassandra-Operations-Manual`).
    *   Select **Pipeline** as the job type and click **OK**.

2.  **Configure the Pipeline**:
    *   On the configuration page, scroll down to the **Pipeline** section.
    *   The **Definition** dropdown should already be set to **Pipeline script**.
    *   **Copy and Paste**: Open the `Jenkinsfile` from this project in a text editor, copy its entire content, and paste it into the **Script** text area in the Jenkins UI.
    *   **Important**: If you are using this method, remember to update the `SCRIPTS_PATH` variable at the top of the `Jenkinsfile` script to match the location where you've manually placed the `scripts` directory on your Jenkins agent.

3.  **Save the Job**:
    *   Click the **Save** button at the bottom of the page.

---

## Running the Job

Once the job is created, you can run it:

1.  Go to the job's main page in Jenkins.
2.  Click on **Build with Parameters** in the left-hand sidebar.
3.  You will see the parameters defined in the `Jenkinsfile`:
    *   `OPERATION`: A dropdown menu to select the action (`ROLLING_RESTART`, `JOIN_DCS`, etc.).
    *   `QV_QUERY`, `OLD_DC_NAME`, etc.: Text fields for the operation's arguments.
4.  Choose the desired operation from the dropdown and fill in **only the parameters relevant to that operation**.
5.  Click the **Build** button.

The pipeline will start, and you can monitor its progress in the "Build History" and view the detailed logs in the "Console Output".
