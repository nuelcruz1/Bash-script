This robust Bash script automates the full deployment lifecycle of a web application: cloning a Git repository, installing prerequisites (Docker, Docker Compose, Nginx) on a remote Ubuntu server, building a Docker image, running the container, and setting up an Nginx reverse proxy.

---

Features

Secure Authentication: Uses SSH private keys for remote server access and Git Personal Access Tokens (PAT) for repository cloning/pulling.

Idempotency: Checks for existing prerequisites and services (Docker, Nginx) before installation.
Logging: Comprehensive timestamped logging to both the console and a dedicated log file (`deploy_<timestamp>.log`).
Error Trapping:Graceful failure handling and cleanup using `trap 'cleanup_on_error $LINENO' ERR`, providing line number and command context upon failure.
Secret Redaction:Automatically redacts the Git PAT from error logs to prevent secret leakage.
Nginx Reverse Proxy:Configures Nginx to proxy external traffic (default port 80) to the application container (internal port 8080).


Prerequisites

Local Machine (where you run the script)

Bash(Standard on Linux/macOS)
Git
SSH Client (for remote connection)
rsync (for fast file synchronization)

Remote Server (the target machine)

Ubuntu operating system (required for the `apt-get` commands in the installation script).
sudoaccess for the specified `SSH_USER` to install packages (Docker, Nginx).
Inbound access allowed for SSH (port 22) and the desired Nginx port (default 80).

---

How to Use

 Setup

1.Generate an SSH Key: Ensure you have an SSH private key (`id_rsa` or similar) that is trusted by your remote server.
2.Create a Git PAT: Generate a Personal Access Token (PAT) from your Git hosting provider (GitHub, GitLab, etc.) with read access to the repository.
3.Make the script executable:**
    ```bash
    chmod +x deploy.sh
    ```

Execution

Run the script and follow the prompts. The script will ask for all necessary configuration details interactively.

```bash
./deploy.sh
````

 Required Inputs

The script will prompt you for the following information:

| Parameter | Example | Description |
| :--- | :--- | :--- |
| **Git Repository URL** | `https://github.com/nuelcruz1/hng13-stage1-devops.git` | The full HTTPS URL of your repository. |
| **Git Personal Access Token (PAT)** | `ghp_xxxxxxxxxxxxxxxxxxxxxx` | Your token (input is hidden/masked). |
| **Branch Name** | `main` | The branch to deploy. Defaults to `main`. |
| **Remote Server Username** | `ubuntu` | The user name to SSH into the remote host. |
| **Remote Server IP/Host** | `54.159.24.51` | The IP address or DNS hostname of the target server. |
| **Full Path to SSH Private Key** | `/home/user/.ssh/id_rsa` | The local path to the private key file. |
| **Internal Container Port** | `3000` | The port your application *inside* the Docker container listens on (80). |



Deployment Flow

1.  Collect Parameters:Gathers all necessary Git, SSH, and application ports.
2.  Clone/Update Repository:** Clones or updates the local repository using the provided PAT.
3.  Install Prerequisites (Remote):** SSHs into the remote host to install Docker, Docker Compose Plugin, and Nginx.
4.  Sync Files: Uses `rsync` to securely transfer the repository contents (excluding the `.git` directory) to the    remote deployment directory (`/opt/your-repo-name`).
5.  Build & Deploy (Remote):
       Navigates to the deployment directory.
       Builds the Docker image (`<repo_name>_app:latest`).
       Stops and removes any existing container with the same name.
       Starts a new container, mapping its internal port (`$APP_PORT`) to the host's port 8080.
6.  Configure Nginx (Remote):**
       Writes a new Nginx configuration file.
       Enables the configuration, linking the site to `/etc/nginx/sites-enabled/`.
       Reloads Nginx. All incoming traffic on host port 80 is reverse-proxied to `127.0.0.1:8080` (your Docker container).



Troubleshooting

  Authentication Failure:** If the script fails during the first `ssh_exec`, ensure:
       The `SSH_KEY_PATH` is correct and has permissions `600` (the script sets this automatically).
       The `SSH_USER` is correct and has access to the remote host.
  Git Clone Failure:** If the script fails during `clone_or_update_repo`, ensure the PAT has the correct scopes (at least `repo` or read-only access for private repos).

  Application Not Accessible:If the script succeeds but the application doesn't load:
    1.  SSH into the remote server.
    2.  Check the Docker container status: `sudo docker ps -a`. Ensure the container is running and port mapping is correct.
    3.  Check Nginx status: `sudo systemctl status nginx` and configuration validity: `sudo nginx -t`.
    4.  Check application logs: `sudo docker logs <container_name>`.
  See the Log File: Always consult the automatically generated log file (e.g., `deploy_20241021_144500.log`) for detailed command outputs and specific error messages.

<!-- end list -->

```
```