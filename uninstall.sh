#!/bin/bash

# GitHub Runner Uninstall Script
# This script removes GitHub self-hosted runners and cleans up

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

# Get runner count from config file or detect from directories
CONFIG_FILE="$RUNNER_HOME/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# If RUNNER_COUNT not set, detect from directories
if [[ -z "$RUNNER_COUNT" ]]; then
    RUNNER_COUNT=$(find "$RUNNER_HOME" -maxdepth 1 -name "${POOL_NAME}-runner-*" -type d 2>/dev/null | wc -l)
    if [[ $RUNNER_COUNT -eq 0 ]]; then
        echo -e "${YELLOW}No runner directories found, will clean up services anyway${NC}"
        RUNNER_COUNT=10  # Check up to 10 services to be thorough
    fi
fi

echo -e "${YELLOW}Starting GitHub Runner Uninstall...${NC}"

# Detect distribution for user removal
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Stop and disable all services
echo -e "${YELLOW}Stopping and disabling services...${NC}"

# Stop and disable the target first
TARGET_NAME="github-runner-${POOL_NAME}.target"
if systemctl is-active --quiet "$TARGET_NAME"; then
    systemctl stop "$TARGET_NAME"
    echo -e "${GREEN}Stopped $TARGET_NAME${NC}"
fi

if systemctl is-enabled --quiet "$TARGET_NAME" 2>/dev/null; then
    systemctl disable "$TARGET_NAME"
    echo -e "${GREEN}Disabled $TARGET_NAME${NC}"
fi

# Remove target file
if [[ -f "/etc/systemd/system/${TARGET_NAME}" ]]; then
    rm "/etc/systemd/system/${TARGET_NAME}"
    echo -e "${GREEN}Removed target file for $TARGET_NAME${NC}"
fi

# Now handle individual services
for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    echo "Processing $SERVICE_NAME..."
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        systemctl stop "$SERVICE_NAME"
        echo -e "${GREEN}Stopped $SERVICE_NAME${NC}"
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME"
        echo -e "${GREEN}Disabled $SERVICE_NAME${NC}"
    fi
    
    # Remove service file
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        rm "/etc/systemd/system/${SERVICE_NAME}.service"
        echo -e "${GREEN}Removed service file for $SERVICE_NAME${NC}"
    fi
done

# Reload systemd
systemctl daemon-reload

# Check if config file exists and source it for unregistration
CONFIG_FILE="$RUNNER_HOME/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    
    # Function to get registration token for removal
    get_removal_token() {
        local url="$1"
        local token_endpoint
        
        if [[ "$url" == *"/repos/"* ]]; then
            local repo_path=$(echo "$url" | sed 's|https://github.com/||')
            token_endpoint="https://api.github.com/repos/$repo_path/actions/runners/remove-token"
        elif [[ -n "$GITHUB_ORG" ]]; then
            token_endpoint="https://api.github.com/orgs/$GITHUB_ORG/actions/runners/remove-token"
        else
            return 1
        fi
        
        local response=$(curl -s -X POST \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "$token_endpoint")
        
        echo "$response" | jq -r '.token'
    }
    
    # Determine registration URL
    if [[ -n "$GITHUB_REPO_URL" ]]; then
        REGISTRATION_URL="$GITHUB_REPO_URL"
    elif [[ -n "$GITHUB_ORG" ]]; then
        REGISTRATION_URL="https://github.com/$GITHUB_ORG"
    fi
    
    if [[ -n "$REGISTRATION_URL" && -n "$GITHUB_TOKEN" ]]; then
        echo -e "${YELLOW}Unregistering runners from GitHub...${NC}"
        REMOVAL_TOKEN=$(get_removal_token "$REGISTRATION_URL")
        
        if [[ "$REMOVAL_TOKEN" != "null" && -n "$REMOVAL_TOKEN" ]]; then
            for i in $(seq 1 $RUNNER_COUNT); do
                RUNNER_DIR="$RUNNER_HOME/${POOL_NAME}-runner-$i"
                if [[ -d "$RUNNER_DIR" && -f "$RUNNER_DIR/config.sh" ]]; then
                    echo "Unregistering runner $i..."
                    cd "$RUNNER_DIR"
                    sudo -u "$RUNNER_USER" ./config.sh remove --token "$REMOVAL_TOKEN" || true
                fi
            done
        else
            echo -e "${YELLOW}Could not get removal token, skipping GitHub unregistration${NC}"
        fi
    fi
fi

# Remove runner directories
if [[ -d "$RUNNER_HOME" ]]; then
    echo -e "${YELLOW}Removing runner directories...${NC}"
    rm -rf "$RUNNER_HOME"
    echo -e "${GREEN}Removed $RUNNER_HOME${NC}"
fi

# Remove runner user
if id "$RUNNER_USER" &>/dev/null; then
    echo -e "${YELLOW}Removing runner user...${NC}"
    case $OS in
        ubuntu|debian|rhel|centos|fedora|almalinux|rocky|opensuse*|sles)
            userdel -r "$RUNNER_USER" 2>/dev/null || userdel "$RUNNER_USER"
            ;;
        *)
            # Fallback for unknown distributions
            userdel -r "$RUNNER_USER" 2>/dev/null || userdel "$RUNNER_USER"
            ;;
    esac
    echo -e "${GREEN}Removed user: $RUNNER_USER${NC}"
fi

echo -e "${GREEN}Uninstall completed successfully!${NC}"
echo -e "${YELLOW}Note: You may want to manually remove any remaining runners from GitHub's web interface${NC}"
