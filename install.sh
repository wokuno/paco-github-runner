#!/bin/bash

# GitHub Runner Install Script
# This script configures and registers GitHub self-hosted runners

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
RUNNER_USER="github-runner"
RUNNER_HOME="/opt/github-runner"
POOL_NAME="paco"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}Starting GitHub Runner Installation...${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Check if config file exists
CONFIG_FILE="$RUNNER_HOME/config.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Configuration file not found: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Please run ./setup.sh first to create the configuration${NC}"
    echo -e "${YELLOW}Or manually copy config.template to config.env and fill in your details${NC}"
    exit 1
fi

echo -e "${YELLOW}Using configuration from: $CONFIG_FILE${NC}"

# Source configuration
source "$CONFIG_FILE"

# Set default values for optional variables
RUNNER_GROUP="${RUNNER_GROUP:-paco}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,Linux,X64,paco}"

# Get runner count from config or detect from existing directories
if [[ -n "$RUNNER_COUNT" ]]; then
    echo -e "${YELLOW}Using RUNNER_COUNT from config: $RUNNER_COUNT${NC}"
else
    # Count existing runner directories
    RUNNER_COUNT=$(find "$RUNNER_HOME" -maxdepth 1 -name "${POOL_NAME}-runner-*" -type d 2>/dev/null | wc -l)
    if [[ $RUNNER_COUNT -eq 0 ]]; then
        echo -e "${RED}No runner directories found and RUNNER_COUNT not set in config${NC}"
        echo -e "${YELLOW}Please run ./setup.sh first${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Detected $RUNNER_COUNT existing runner directories${NC}"
fi

# Validate required variables
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo -e "${RED}GITHUB_TOKEN is required in config.env${NC}"
    exit 1
fi

if [[ -z "$GITHUB_USER" && -z "$GITHUB_ORG" ]]; then
    echo -e "${RED}Either GITHUB_USER or GITHUB_ORG is required in config.env${NC}"
    exit 1
fi

# Determine registration URL
if [[ -n "$GITHUB_REPO_URL" ]]; then
    REGISTRATION_URL="$GITHUB_REPO_URL"
elif [[ -n "$GITHUB_ORG" ]]; then
    REGISTRATION_URL="https://github.com/$GITHUB_ORG"
else
    REGISTRATION_URL="https://github.com/$GITHUB_USER"
fi

echo -e "${YELLOW}Registration URL: $REGISTRATION_URL${NC}"

# Function to get registration token
get_registration_token() {
    local url="$1"
    local token_endpoint
    
    if [[ "$url" == *"/repos/"* ]]; then
        # Repository-level runner
        local repo_path=$(echo "$url" | sed 's|https://github.com/||')
        token_endpoint="https://api.github.com/repos/$repo_path/actions/runners/registration-token"
    elif [[ -n "$GITHUB_ORG" ]]; then
        # Organization-level runner
        token_endpoint="https://api.github.com/orgs/$GITHUB_ORG/actions/runners/registration-token"
    else
        # User-level runner (for personal repositories)
        echo -e "${RED}User-level runners are not supported through API${NC}"
        echo -e "${YELLOW}Please use organization or repository-level runners${NC}"
        exit 1
    fi
    
    local response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$token_endpoint")
    
    echo "$response" | jq -r '.token'
}

# Get registration token
echo -e "${YELLOW}Getting registration token...${NC}"
REG_TOKEN=$(get_registration_token "$REGISTRATION_URL")

if [[ "$REG_TOKEN" == "null" || -z "$REG_TOKEN" ]]; then
    echo -e "${RED}Failed to get registration token. Check your GitHub token permissions.${NC}"
    exit 1
fi

# Configure each runner
for i in $(seq 1 $RUNNER_COUNT); do
    RUNNER_DIR="$RUNNER_HOME/${POOL_NAME}-runner-$i"
    RUNNER_NAME="${POOL_NAME}-runner-$i"
    
    echo -e "${YELLOW}Configuring runner: $RUNNER_NAME${NC}"
    
    cd "$RUNNER_DIR"
    
    # Stop any running services for this runner first
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    echo -e "${YELLOW}Stopping any existing service: $SERVICE_NAME${NC}"
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl kill --signal=SIGKILL "$SERVICE_NAME" 2>/dev/null || true
    
    # Kill any remaining runner processes for this specific runner
    pkill -KILL -f "Runner.Listener.*$RUNNER_NAME" 2>/dev/null || true
    
    # Remove existing configuration if it exists
    if [[ -f ".runner" ]]; then
        echo -e "${YELLOW}Removing existing configuration for $RUNNER_NAME${NC}"
        # Try to remove gracefully first
        sudo -u "$RUNNER_USER" ./config.sh remove --token "$REG_TOKEN" 2>/dev/null || {
            echo -e "${YELLOW}Graceful removal failed, forcing cleanup for $RUNNER_NAME${NC}"
            # Force remove runner files if graceful removal fails
            sudo -u "$RUNNER_USER" rm -f .runner .credentials .credentials_rsaparams || true
            sudo -u "$RUNNER_USER" rm -rf _work || true
        }
    fi
    
    # Additional cleanup - remove any leftover state files
    sudo -u "$RUNNER_USER" rm -f .runner .credentials .credentials_rsaparams 2>/dev/null || true
    sudo -u "$RUNNER_USER" rm -rf _work 2>/dev/null || true
    
    # Wait a moment for any processes to fully terminate
    sleep 2
    
    # Configure the runner
    if [[ -n "$GITHUB_ORG" ]]; then
        # For organization runners, always use runnergroup
        sudo -u "$RUNNER_USER" ./config.sh \
            --url "$REGISTRATION_URL" \
            --token "$REG_TOKEN" \
            --name "$RUNNER_NAME" \
            --labels "$RUNNER_LABELS" \
            --runnergroup "$RUNNER_GROUP" \
            --work "_work" \
            --unattended \
            --replace
    else
        # For repository runners, don't use runnergroup
        sudo -u "$RUNNER_USER" ./config.sh \
            --url "$REGISTRATION_URL" \
            --token "$REG_TOKEN" \
            --name "$RUNNER_NAME" \
            --labels "$RUNNER_LABELS" \
            --work "_work" \
            --unattended \
            --replace
    fi
    
    echo -e "${GREEN}Successfully configured runner: $RUNNER_NAME${NC}"
done

# Create systemd service files
echo -e "${YELLOW}Creating systemd service files...${NC}"

for i in $(seq 1 $RUNNER_COUNT); do
    RUNNER_NAME="${POOL_NAME}-runner-$i"
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    RUNNER_DIR="$RUNNER_HOME/${POOL_NAME}-runner-$i"
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=GitHub Actions Runner (${RUNNER_NAME})
After=network.target
Wants=network.target
PartOf=github-runner-${POOL_NAME}.target

[Service]
Type=simple
User=${RUNNER_USER}
WorkingDirectory=${RUNNER_DIR}
ExecStart=${RUNNER_DIR}/run.sh
ExecStop=/bin/bash -c 'pid=\$(pgrep -f "Runner.Listener.*${RUNNER_NAME}"); if [ -n "\$pid" ]; then kill -TERM \$pid; sleep 10; kill -KILL \$pid 2>/dev/null || true; fi'
Restart=always
RestartSec=5
KillMode=mixed
KillSignal=SIGTERM
SendSIGKILL=yes
TimeoutStopSec=30
FinalKillSignal=SIGKILL

# Environment variables
Environment=RUNNER_ALLOW_RUNASROOT=false
Environment=DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=${RUNNER_DIR}
ReadWritePaths=${RUNNER_HOME}/logs

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
WantedBy=github-runner-${POOL_NAME}.target
EOF

    echo -e "${GREEN}Created service file: ${SERVICE_NAME}.service${NC}"
done

# Create systemd target file for managing all runners as a group
echo -e "${YELLOW}Creating systemd target file for runner pool...${NC}"
cat > "/etc/systemd/system/github-runner-${POOL_NAME}.target" << EOF
[Unit]
Description=GitHub Actions Runner Pool (${POOL_NAME})
Documentation=https://docs.github.com/en/actions/hosting-your-own-runners
After=multi-user.target
Wants=multi-user.target
EOF

# Add all runner services as requirements to the target
for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    echo "Wants=${SERVICE_NAME}.service" >> "/etc/systemd/system/github-runner-${POOL_NAME}.target"
done

cat >> "/etc/systemd/system/github-runner-${POOL_NAME}.target" << EOF

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}Created target file: github-runner-${POOL_NAME}.target${NC}"

# Create management scripts
cat > "$RUNNER_HOME/scripts/start-all.sh" << EOF
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT="$RUNNER_COUNT"

for i in \$(seq 1 \$RUNNER_COUNT); do
    SERVICE_NAME="github-runner-\${POOL_NAME}-\$i"
    echo "Starting \$SERVICE_NAME..."
    systemctl start "\$SERVICE_NAME"
done
EOF

cat > "$RUNNER_HOME/scripts/stop-all.sh" << EOF
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT="$RUNNER_COUNT"

echo "Stopping all GitHub runners forcefully..."

for i in \$(seq 1 \$RUNNER_COUNT); do
    SERVICE_NAME="github-runner-\${POOL_NAME}-\$i"
    RUNNER_NAME="\${POOL_NAME}-runner-\$i"
    
    echo "Stopping \$SERVICE_NAME..."
    
    # Try normal stop first
    systemctl stop "\$SERVICE_NAME" &
    STOP_PID=\$!
    
    # Wait up to 15 seconds for normal stop
    sleep 15
    
    # Check if stop is still running, if so kill it and force stop
    if kill -0 \$STOP_PID 2>/dev/null; then
        echo "Normal stop taking too long, forcing stop for \$SERVICE_NAME..."
        kill \$STOP_PID 2>/dev/null || true
        systemctl kill --signal=SIGKILL "\$SERVICE_NAME" 2>/dev/null || true
    fi
    
    # Double-check and kill any remaining runner processes
    RUNNER_PID=\$(pgrep -f "Runner.Listener.*\$RUNNER_NAME" 2>/dev/null || true)
    if [ -n "\$RUNNER_PID" ]; then
        echo "Killing remaining runner process \$RUNNER_PID for \$RUNNER_NAME..."
        kill -KILL \$RUNNER_PID 2>/dev/null || true
    fi
done

echo "All runners stopped."
EOF

cat > "$RUNNER_HOME/scripts/status-all.sh" << EOF
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT="$RUNNER_COUNT"

for i in \$(seq 1 \$RUNNER_COUNT); do
    SERVICE_NAME="github-runner-\${POOL_NAME}-\$i"
    echo "=== \$SERVICE_NAME ==="
    systemctl status "\$SERVICE_NAME" --no-pager -l
    echo
done
EOF

cat > "$RUNNER_HOME/scripts/logs-all.sh" << EOF
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT="$RUNNER_COUNT"

if [[ \$# -eq 0 ]]; then
    echo "Usage: \$0 [runner_number] [journalctl_options]"
    echo "       \$0 all [journalctl_options]"
    echo "Example: \$0 1 -f"
    echo "Example: \$0 all --since '1 hour ago'"
    exit 1
fi

if [[ "\$1" == "all" ]]; then
    shift
    for i in \$(seq 1 \$RUNNER_COUNT); do
        SERVICE_NAME="github-runner-\${POOL_NAME}-\$i"
        echo "=== Logs for \$SERVICE_NAME ==="
        journalctl -u "\$SERVICE_NAME" "\$@" --no-pager
        echo
    done
else
    RUNNER_NUM="\$1"
    shift
    SERVICE_NAME="github-runner-\${POOL_NAME}-\$RUNNER_NUM"
    journalctl -u "\$SERVICE_NAME" "\$@"
fi
EOF

cat > "$RUNNER_HOME/scripts/kill-all.sh" << EOF
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT="$RUNNER_COUNT"

echo "Emergency stop: Killing all GitHub runners forcefully..."

# First, kill systemd services
for i in \$(seq 1 \$RUNNER_COUNT); do
    SERVICE_NAME="github-runner-\${POOL_NAME}-\$i"
    echo "Force killing service \$SERVICE_NAME..."
    systemctl kill --signal=SIGKILL "\$SERVICE_NAME" 2>/dev/null || true
done

# Then kill any remaining runner processes by name
echo "Killing any remaining runner processes..."
pkill -KILL -f "Runner.Listener" 2>/dev/null || true
pkill -KILL -f "Runner.Worker" 2>/dev/null || true

# Kill dotnet processes that might be stuck
echo "Killing any stuck dotnet processes..."
pkill -KILL -f "dotnet.*Runner" 2>/dev/null || true

echo "Emergency stop completed. All runner processes should be terminated."
echo "You may need to restart the services: systemctl start github-runner-paco.target"
EOF

cat > "$RUNNER_HOME/scripts/stop-target.sh" << EOF
#!/bin/bash
POOL_NAME="paco"

echo "Stopping github-runner-\$POOL_NAME.target..."

# Try normal stop first
timeout 30 systemctl stop "github-runner-\$POOL_NAME.target" || {
    echo "Normal stop failed or timed out, using kill method..."
    systemctl kill --signal=SIGKILL "github-runner-\$POOL_NAME.target"
}

echo "Target stopped."
EOF

cat > "$RUNNER_HOME/scripts/cleanup-all.sh" << EOF
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT="$RUNNER_COUNT"

echo "Cleaning up all GitHub runners..."

# Stop all services first
echo "Stopping all services..."
for i in \$(seq 1 \$RUNNER_COUNT); do
    SERVICE_NAME="github-runner-\${POOL_NAME}-\$i"
    echo "Stopping \$SERVICE_NAME..."
    systemctl stop "\$SERVICE_NAME" 2>/dev/null || true
    systemctl kill --signal=SIGKILL "\$SERVICE_NAME" 2>/dev/null || true
done

# Kill any remaining processes
echo "Killing any remaining runner processes..."
pkill -KILL -f "Runner.Listener" 2>/dev/null || true
pkill -KILL -f "Runner.Worker" 2>/dev/null || true
pkill -KILL -f "dotnet.*Runner" 2>/dev/null || true

# Clean up runner state files
echo "Cleaning up runner state files..."
for i in \$(seq 1 \$RUNNER_COUNT); do
    RUNNER_DIR="$RUNNER_HOME/\${POOL_NAME}-runner-\$i"
    if [ -d "\$RUNNER_DIR" ]; then
        echo "Cleaning up \$RUNNER_DIR..."
        sudo -u $RUNNER_USER rm -f "\$RUNNER_DIR/.runner" 2>/dev/null || true
        sudo -u $RUNNER_USER rm -f "\$RUNNER_DIR/.credentials" 2>/dev/null || true
        sudo -u $RUNNER_USER rm -f "\$RUNNER_DIR/.credentials_rsaparams" 2>/dev/null || true
        sudo -u $RUNNER_USER rm -rf "\$RUNNER_DIR/_work" 2>/dev/null || true
    fi
done

echo "Cleanup completed. You can now run './install.sh' to re-register runners."
EOF

# Make scripts executable
chmod +x "$RUNNER_HOME/scripts/"*.sh
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/scripts"

# Reload systemd
systemctl daemon-reload

# Enable the target and all services
echo -e "${YELLOW}Enabling systemd target and services...${NC}"
systemctl enable "github-runner-${POOL_NAME}.target"
echo -e "${GREEN}Enabled target: github-runner-${POOL_NAME}.target${NC}"

for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    systemctl enable "$SERVICE_NAME"
    echo -e "${GREEN}Enabled service: $SERVICE_NAME${NC}"
done

echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "${YELLOW}Management commands:${NC}"
echo ""
echo -e "${BLUE}=== Systemd Target Management (Recommended) ===${NC}"
echo "  Start all runners:   systemctl start github-runner-${POOL_NAME}.target"
echo "  Stop all runners:    systemctl stop github-runner-${POOL_NAME}.target"
echo "  Force stop (if needed): $RUNNER_HOME/scripts/stop-target.sh"
echo "  Restart all runners: systemctl restart github-runner-${POOL_NAME}.target"
echo "  Status all runners:  systemctl status github-runner-${POOL_NAME}.target"
echo "  Enable on boot:      systemctl enable github-runner-${POOL_NAME}.target"
echo ""
echo -e "${BLUE}=== Script Management ===${NC}"
echo "  Start all runners:   $RUNNER_HOME/scripts/start-all.sh"
echo "  Stop all runners:    $RUNNER_HOME/scripts/stop-all.sh (enhanced with kill)"
echo "  Emergency stop:      $RUNNER_HOME/scripts/kill-all.sh"
echo "  Cleanup runners:     $RUNNER_HOME/scripts/cleanup-all.sh"
echo "  Status all runners:  $RUNNER_HOME/scripts/status-all.sh"
echo "  View logs:           $RUNNER_HOME/scripts/logs-all.sh [runner_number|all] [options]"
echo ""
echo -e "${BLUE}=== Individual Service Management ===${NC}"
echo "  systemctl start github-runner-${POOL_NAME}-1"
echo "  systemctl status github-runner-${POOL_NAME}-1"
echo "  journalctl -u github-runner-${POOL_NAME}-1 -f"
