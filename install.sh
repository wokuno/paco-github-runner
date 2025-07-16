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
RUNNER_COUNT=4
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
    
    # Remove existing configuration if it exists
    if [[ -f ".runner" ]]; then
        echo -e "${YELLOW}Removing existing configuration for $RUNNER_NAME${NC}"
        sudo -u "$RUNNER_USER" ./config.sh remove --token "$REG_TOKEN" || true
    fi
    
    # Configure the runner
    sudo -u "$RUNNER_USER" ./config.sh \
        --url "$REGISTRATION_URL" \
        --token "$REG_TOKEN" \
        --name "$RUNNER_NAME" \
        --labels "$RUNNER_LABELS" \
        --work "_work" \
        --unattended \
        --replace
    
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

[Service]
Type=simple
User=${RUNNER_USER}
WorkingDirectory=${RUNNER_DIR}
ExecStart=${RUNNER_DIR}/run.sh
Restart=always
RestartSec=5
KillMode=process
KillSignal=SIGINT
TimeoutStopSec=5min

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
EOF

    echo -e "${GREEN}Created service file: ${SERVICE_NAME}.service${NC}"
done

# Create management scripts
cat > "$RUNNER_HOME/scripts/start-all.sh" << 'EOF'
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT=4

for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    echo "Starting $SERVICE_NAME..."
    systemctl start "$SERVICE_NAME"
done
EOF

cat > "$RUNNER_HOME/scripts/stop-all.sh" << 'EOF'
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT=4

for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    echo "Stopping $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME"
done
EOF

cat > "$RUNNER_HOME/scripts/status-all.sh" << 'EOF'
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT=4

for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    echo "=== $SERVICE_NAME ==="
    systemctl status "$SERVICE_NAME" --no-pager -l
    echo
done
EOF

cat > "$RUNNER_HOME/scripts/logs-all.sh" << 'EOF'
#!/bin/bash
POOL_NAME="paco"
RUNNER_COUNT=4

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [runner_number] [journalctl_options]"
    echo "       $0 all [journalctl_options]"
    echo "Example: $0 1 -f"
    echo "Example: $0 all --since '1 hour ago'"
    exit 1
fi

if [[ "$1" == "all" ]]; then
    shift
    for i in $(seq 1 $RUNNER_COUNT); do
        SERVICE_NAME="github-runner-${POOL_NAME}-$i"
        echo "=== Logs for $SERVICE_NAME ==="
        journalctl -u "$SERVICE_NAME" "$@" --no-pager
        echo
    done
else
    RUNNER_NUM="$1"
    shift
    SERVICE_NAME="github-runner-${POOL_NAME}-$RUNNER_NUM"
    journalctl -u "$SERVICE_NAME" "$@"
fi
EOF

# Make scripts executable
chmod +x "$RUNNER_HOME/scripts/"*.sh
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/scripts"

# Reload systemd
systemctl daemon-reload

# Enable services
for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    systemctl enable "$SERVICE_NAME"
    echo -e "${GREEN}Enabled service: $SERVICE_NAME${NC}"
done

echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "${YELLOW}Management commands:${NC}"
echo "  Start all runners:  $RUNNER_HOME/scripts/start-all.sh"
echo "  Stop all runners:   $RUNNER_HOME/scripts/stop-all.sh"
echo "  Status all runners: $RUNNER_HOME/scripts/status-all.sh"
echo "  View logs:          $RUNNER_HOME/scripts/logs-all.sh [runner_number|all] [options]"
echo ""
echo -e "${YELLOW}Or use systemctl directly:${NC}"
echo "  systemctl start github-runner-${POOL_NAME}-1"
echo "  systemctl status github-runner-${POOL_NAME}-1"
echo "  journalctl -u github-runner-${POOL_NAME}-1 -f"
