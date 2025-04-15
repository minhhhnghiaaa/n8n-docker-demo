#!/bin/bash
set -euo pipefail

# Helper function to run commands and check for errors
run_command() {
    local cmd_desc="$1"
    local cmd="$2"
    local suppress_output="${3:-true}" # Suppress output by default

    echo "INFO: Running: $cmd_desc"
    if [ "$suppress_output" = true ]; then
        if ! eval "$cmd" > /dev/null 2>&1; then
            echo "ERROR: Failed to $cmd_desc. Exiting." >&2
            exit 1
        fi
    else
        if ! eval "$cmd"; then
            echo "ERROR: Failed to $cmd_desc. Exiting." >&2
            exit 1
        fi
    fi
    echo "INFO: Successfully completed: $cmd_desc"
}


echo "==== Initial System Setup ===="
run_command "Update apt package list" "sudo apt update"
run_command "Install caffeine" "sudo apt install -y caffeine"

# --- Docker Setup ---
echo "INFO: Configuring Docker..."
run_command "Unmask docker service" "sudo systemctl unmask docker"
run_command "Unmask docker socket" "sudo systemctl unmask docker.socket"
run_command "Unmask containerd service" "sudo systemctl unmask containerd.service"
run_command "Start containerd service" "sudo systemctl start containerd.service"
run_command "Start docker service" "sudo systemctl start docker"
run_command "Start docker socket" "sudo systemctl start docker.socket" # Often started automatically with docker service, but explicit doesn't hurt

# --- Directory and Permissions Setup ---
echo "INFO: Creating required directories..."
DATA_DIR="docker-run"
N8N_DATA_DIR="$DATA_DIR/n8n_data"
POSTGRES_DATA_DIR="$DATA_DIR/postgres_data"

run_command "Create main data directory ($DATA_DIR)" "sudo mkdir -p $DATA_DIR"
run_command "Create n8n data directory ($N8N_DATA_DIR)" "sudo mkdir -p $N8N_DATA_DIR"
run_command "Create postgres data directory ($POSTGRES_DATA_DIR)" "sudo mkdir -p $POSTGRES_DATA_DIR"

echo "INFO: Setting directory permissions..."
# WARNING: 777 permissions are insecure. Consider more restrictive permissions if possible.
run_command "Set permissions for $DATA_DIR" "sudo chmod -R 777 $DATA_DIR"
# The following are redundant if the parent has 777, but kept for clarity if parent perms change
run_command "Set permissions for $N8N_DATA_DIR" "sudo chmod -R 777 $N8N_DATA_DIR"
run_command "Set permissions for $POSTGRES_DATA_DIR" "sudo chmod -R 777 $POSTGRES_DATA_DIR"

# --- Docker Compose Setup ---
echo "INFO: Setting up Docker Compose..."
DOCKER_COMPOSE_SRC="docker-compose.yml"
DOCKER_COMPOSE_DEST="$DATA_DIR/docker-compose.yml"

if [ ! -f "$DOCKER_COMPOSE_SRC" ]; then
    echo "ERROR: Source file '$DOCKER_COMPOSE_SRC' not found in the current directory." >&2
    exit 1
fi
run_command "Copy $DOCKER_COMPOSE_SRC to $DOCKER_COMPOSE_DEST" "cp '$DOCKER_COMPOSE_SRC' '$DOCKER_COMPOSE_DEST'"

run_command "Run docker compose up -d" "docker compose -f '$DOCKER_COMPOSE_DEST' up -d" false

# --- Keep Session Alive Setup ---
echo "==== Setting up Session Keep-Alive Script ===="

VNC_URL=""
while [ -z "$VNC_URL" ]; do
    read -p "Enter the remote URL (e.g., https://cloudworkstations.dev/vnc.html?autoconnect=true&resize=remote): " VNC_URL
    if [ -z "$VNC_URL" ]; then
        echo "ERROR: URL cannot be empty. Please try again."
    fi
done

MONITOR_SCRIPT_PATH="$HOME/monitor.sh"
LOG_FILE_PATH="$HOME/vnc_monitor.log"

echo "INFO: Creating monitor script at $MONITOR_SCRIPT_PATH..."
cat > "$MONITOR_SCRIPT_PATH" << EOL
#!/bin/bash
set -uo pipefail # Add safety flags to monitor script too

# URL to connect to
URL="$VNC_URL"
LOG_FILE="$LOG_FILE_PATH"

# Perform the connection attempt and log the result
# Using curl options:
# --fail: Return error on server errors (HTTP >= 400)
# -sS: Silent mode, but show errors
# -o /dev/null: Discard output body
# -L: Follow redirects
# --connect-timeout 10: Max time to connect
# --max-time 20: Max total time for operation
echo "INFO (monitor.sh): Attempting connection to \$URL" >> "\$LOG_FILE" # Log attempt
if curl --fail -sSL --connect-timeout 10 --max-time 20 "\$URL" -o /dev/null; then
    # Success
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: Connected to \$URL" >> "\$LOG_FILE"
else
    # Failure
    CURL_EXIT_CODE=\$?
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Failed to connect to \$URL (Curl Exit code: \$CURL_EXIT_CODE)" >> "\$LOG_FILE"
fi

# Trim log file (keep last 1000 lines)
# Use temporary file and atomic mv for safety
tail -n 1000 "\$LOG_FILE" > "\$LOG_FILE.tmp" && mv "\$LOG_FILE.tmp" "\$LOG_FILE"

EOL

run_command "Set execute permission for $MONITOR_SCRIPT_PATH" "chmod +x '$MONITOR_SCRIPT_PATH'"

echo "INFO: Adding monitor script to crontab..."
# Add job to run every minute, ensuring no duplicates
CRON_JOB="*/1 * * * * '$MONITOR_SCRIPT_PATH'"
(crontab -l 2>/dev/null | grep -Fv "$MONITOR_SCRIPT_PATH" ; echo "$CRON_JOB") | crontab -
run_command "Verify crontab update" "crontab -l | grep -Fq \"$MONITOR_SCRIPT_PATH\"" false # Don't suppress grep output

# --- Start Caffeine ---
echo "INFO: Starting Caffeine in background..."
# Check if caffeine is installed before running
if command -v caffeine &> /dev/null; then
    run_command "Start caffeine process" "caffeine & disown" true
else
    echo "WARNING: caffeine command not found. Skipping start."
fi


# --- Final Steps ---
echo "INFO: Displaying initial cloudflared logs (press Ctrl+C to stop)..."
# Added -f to follow logs, more useful than static snapshot
run_command "Follow cloudflared logs" "docker logs -f cloudflared" false

echo "==== Setup Complete ===="