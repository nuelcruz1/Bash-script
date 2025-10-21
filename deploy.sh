#!/bin/bash

#GLOBAL CONFIGURATION AND UTILITIES

# Exit immediately if a command exits with a non-zero status
set -e
# Exit immediately if a command in a pipeline fails
set -o pipefail

# Define the log file name
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

# Function to log messages to console and file
log_message() {
    local type="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Log to file
    echo "[$timestamp] [$type] $message" >> "$LOG_FILE"
    
    # Log to console with colors
    case "$type" in
        INFO)    echo -e "\e[34m[INFO]\e[0m $message";;
        SUCCESS) echo -e "\e[32m[SUCCESS]\e[0m $message";;
        WARN)    echo -e "\e[33m[WARN]\e[0m $message";;
        ERROR)   echo -e "\e[31m[ERROR]\e[0m $message" >&2;;
        *)       echo "$message";;
    esac
}

# Function to handle errors and cleanup gracefully
cleanup_on_error() {
    local line_num="$1"
    local exit_code="$?"
    
    # Redact the PAT from the command before logging to prevent secret leak
    local clean_command
    if [ -n "$PAT" ]; then
        clean_command=$(echo "$BASH_COMMAND" | sed "s/$PAT/[REDACTED_PAT]/g")
    else
        clean_command="$BASH_COMMAND"
    fi
    
    log_message ERROR "Deployment failed at line $line_num (Exit Code: $exit_code): $clean_command"
    log_message INFO "See $LOG_FILE for detailed log."
    exit 1
}

trap 'cleanup_on_error $LINENO' ERR


# TASK 1: COLLECT AND VALIDATE PARAMETERS

collect_parameters() {
    log_message INFO "Parameter Collection"
    
    read -r -p "Enter Git Repository URL (e.g., https://github.com/user/repo): " REPO_URL
    [ -z "$REPO_URL" ] && { log_message ERROR "Repository URL cannot be empty."; return 1; }

    read -r -s -p "Enter Git Personal Access Token (PAT): " PAT
    echo 
    [ -z "$PAT" ] && { log_message ERROR "PAT cannot be empty."; return 1; }
    
    read -r -p "Enter Branch Name (default: main): " BRANCH_NAME
    : "${BRANCH_NAME:=main}" 

    read -r -p "Enter Remote Server Username: " SSH_USER
    [ -z "$SSH_USER" ] && { log_message ERROR "SSH Username cannot be empty."; return 1; }

    read -r -p "Enter Remote Server IP Address/Host: " SSH_HOST
    [ -z "$SSH_HOST" ] && { log_message ERROR "SSH Host/IP cannot be empty."; return 1; }

    read -r -p "Enter Full Path to SSH Private Key: " SSH_KEY_PATH
    [ -z "$SSH_KEY_PATH" ] && { log_message ERROR "SSH Key Path cannot be empty."; return 1; }
    [ ! -f "$SSH_KEY_PATH" ] && { log_message ERROR "SSH Key file not found at: $SSH_KEY_PATH"; return 1; }

    log_message INFO "Setting SSH key permissions to 600 (required by ssh)..."
    chmod 600 "$SSH_KEY_PATH"

    read -r -p "Enter Internal Container Port (example 80): " APP_PORT
    if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
        log_message ERROR "Application port must be a number."
        return 1
    fi
    
    REPO_NAME=$(basename "$REPO_URL" .git)
    DEPLOY_DIR="/opt/$REPO_NAME"
    CONTAINER_NAME="${REPO_NAME}_app"
    
    SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -i $SSH_KEY_PATH"
    
    log_message SUCCESS "Parameters collected."
}

# SSH COMMAND HELPER 

ssh_exec() {
    local cmd="$1"
    log_message INFO "Executing remote command on $SSH_HOST: $cmd"
    # Use single quotes for the remote command to prevent local variable expansion
    ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" "sh -c '$cmd'"
}

# TASK 2: CLONE OR UPDATE REPO 

clone_or_update_repo() {
    log_message INFO "Starting Local Git Operations"
    
    local AUTH_REPO_URL
    AUTH_REPO_URL=$(echo "$REPO_URL" | sed "s/https:\/\//https:\/\/git:$PAT@/")
    local GIT_OPTS="-c credential.helper="

    if [ -d "$REPO_NAME" ]; then
        log_message WARN "Repository directory '$REPO_NAME' exists. Forcing pull with PAT."
        (
            cd "$REPO_NAME"
            log_message INFO "Updating git remote URL and disabling local credential helper."
            git $GIT_OPTS remote set-url origin "$AUTH_REPO_URL"
            git $GIT_OPTS fetch --all
            git $GIT_OPTS reset --hard "origin/$BRANCH_NAME"
        )
    else
        log_message INFO "Cloning repository $REPO_URL on branch $BRANCH_NAME..."
        git $GIT_OPTS clone --branch "$BRANCH_NAME" "$AUTH_REPO_URL" "$REPO_NAME"
    fi
    
    log_message SUCCESS "Repository is ready locally."
}

# TASK 3: INSTALL PREREQUISITES ON REMOTE (Ubuntu)

install_prerequisites_remote() {
    log_message INFO "Installing/Verifying Prerequisites (Docker, Compose, Nginx) on $SSH_HOST ---"
    
    local install_script=$(cat <<-EOF
set -e
export DEBIAN_FRONTEND=noninteractive

# --- Shared Setup for all installations ---
if ! command -v apt-get > /dev/null 2>&1; then
    echo "ERROR: apt-get not found. This script requires a Debian/Ubuntu system." >&2
    exit 1
fi
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# --- Docker Installation ---
if ! command -v docker > /dev/null 2>&1; then
    echo "--> Docker not found. Installing Docker..."

    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    fi

    echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        \$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    echo "--> Adding user '$SSH_USER' to the docker group"
    sudo usermod -aG docker "$SSH_USER"
    sudo systemctl enable docker
    sudo systemctl start docker
    echo "--> Docker installed and started."
else
    echo "--> Docker already installed."
fi

# --- Docker Compose Installation ---
if ! command -v docker-compose > /dev/null 2>&1 && ! command -v docker compose > /dev/null 2>&1; then
    echo "--> Docker Compose not found. Installing plugin..."
    sudo apt-get install -y docker-compose-plugin
else
    echo "--> Docker Compose already installed."
fi

# --- Nginx Installation ---
if ! command -v nginx > /dev/null 2>&1; then
    echo "--> Nginx not found. Installing Nginx..."
    sudo apt-get install -y nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx
    echo "--> Nginx installed and started."
else
    echo "--> Nginx already installed."
fi

EOF
)
    ssh_exec "$install_script"
    
    log_message SUCCESS "Prerequisites verified/installed and services started on remote server."
}

# TASK 4: SYNC FILES TO REMOTE

sync_files_to_remote() {
    log_message INFO "Syncing repository files to $SSH_HOST:$DEPLOY_DIR "
    
    # Use 'sudo' to create the directory and change ownership for rsync
    ssh_exec "sudo mkdir -p $DEPLOY_DIR && sudo chown -R $SSH_USER:$SSH_USER $DEPLOY_DIR"
    
    log_message INFO "Starting rsync"
    rsync -avz -e "ssh $SSH_OPTS" --exclude=".git" "$REPO_NAME/" "$SSH_USER@$SSH_HOST:$DEPLOY_DIR/"
    
    log_message SUCCESS "Files synced to remote."
}


# TASK 5: BUILD AND DEPLOY ON REMOTE

build_and_deploy_remote() {
    log_message INFO "Building and Deploying on Remote Server"
    
    local remote_script=$(cat <<-EOF
set -e
echo "--> Changed directory to $DEPLOY_DIR"
cd "$DEPLOY_DIR"

echo "--> Building Docker image $CONTAINER_NAME:latest"
sudo docker build -t "$CONTAINER_NAME:latest" .

# Reliable way to stop and remove containers by name
echo "--> Stopping and removing old container (if any exists)"
sudo docker stop "$CONTAINER_NAME" 2> /dev/null || true
sudo docker rm "$CONTAINER_NAME" 2> /dev/null || true

echo "--> Starting new container"
# FIX: Map container port (\$APP_PORT) to host port 8080 to avoid Nginx conflict
sudo docker run -d --name "$CONTAINER_NAME" -p "8080:$APP_PORT" --restart always "$CONTAINER_NAME:latest"

echo "--> Remote deployment complete. Verifying..."
sudo docker ps -f name=$CONTAINER_NAME
EOF
)
    ssh_exec "$remote_script"
    
    log_message SUCCESS "Remote deployment finished successfully."
}

# TASK 6: CONFIGURE NGINX REVERSE PROXY


configure_nginx_remote() {
    log_message INFO "Configuring Nginx Reverse Proxy on $SSH_HOST "

    # Define the Nginx config block using an UNQUOTED Here Document (EOF)
    # and DOUBLE-ESCAPE Nginx variables (e.g., $$host) to protect them from 
    # the local shell's expansion, allowing the remote shell to see the single $.
    local nginx_config=$(cat <<-EOF
server {
    listen 80;
    listen [::]:80;
    server_name _; # Listen on all hostnames

    location / {
        # Proxy traffic to the container running on host port 8080
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $$host;
        proxy_set_header X-Real-IP $$remote_addr;
        proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $$scheme;
    }
}
EOF
)
    # The remote script uses a remote 'cat' command to write the configuration
    local config_script=$(cat <<-EOF
set -e
echo "--> Writing Nginx configuration file..."
# Use cat with an EOF delimiter to write the config safely, and pipe it to sudo tee
cat <<NGINX_END | sudo tee /etc/nginx/sites-available/$CONTAINER_NAME > /dev/null
$nginx_config
NGINX_END

echo "--> Enabling new Nginx site and testing config..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/$CONTAINER_NAME /etc/nginx/sites-enabled/

sudo nginx -t

echo "--> Reloading Nginx service..."
sudo systemctl reload nginx
EOF
)
    # Execute the remote script
    ssh_exec "$config_script"

    log_message SUCCESS "Nginx configured and reloaded successfully (Proxying host port 80 to container port 8080)."
}
# MAIN EXECUTION

main() {
    log_message INFO "Starting New Deployment"
    log_message INFO "Log file: $LOG_FILE"
    
    declare -g REPO_URL PAT BRANCH_NAME SSH_USER SSH_HOST SSH_KEY_PATH APP_PORT
    declare -g REPO_NAME DEPLOY_DIR CONTAINER_NAME SSH_OPTS

    collect_parameters
    clone_or_update_repo
    install_prerequisites_remote
    sync_files_to_remote
    build_and_deploy_remote # Now binds container port to host port 8080
    configure_nginx_remote # NEW STEP: Configures Nginx to proxy 80 -> 8080
    

    log_message SUCCESS "Deployment Succeeded!"
    log_message SUCCESS "Access your application on http://$SSH_HOST/"

}

# Run the main function
main