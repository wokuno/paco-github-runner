#!/bin/bash

# GitHub Runner Cleanup Script
# This script cleans up existing runner sessions and state files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
RUNNER_HOME="/opt/github-runner"
POOL_NAME="paco"

echo -e "${GREEN}GitHub Runner Cleanup Script${NC}"
echo "This script will clean up existing runner sessions and state files."
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Check if config file exists to get runner count
CONFIG_FILE="$RUNNER_HOME/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    RUNNER_COUNT="${RUNNER_COUNT:-4}"
else
    # Try to detect from existing directories
    RUNNER_COUNT=$(find "$RUNNER_HOME" -maxdepth 1 -name "${POOL_NAME}-runner-*" -type d 2>/dev/null | wc -l)
    if [[ $RUNNER_COUNT -eq 0 ]]; then
        RUNNER_COUNT=4  # Default fallback
    fi
fi

echo -e "${YELLOW}Detected $RUNNER_COUNT runners to clean up${NC}"
echo ""

# Stop all services first
echo -e "${YELLOW}Stopping all runner services...${NC}"
for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    echo "Stopping $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl kill --signal=SIGKILL "$SERVICE_NAME" 2>/dev/null || true
done

# Stop the target
echo "Stopping github-runner-${POOL_NAME}.target..."
systemctl stop "github-runner-${POOL_NAME}.target" 2>/dev/null || true

# Kill any remaining processes
echo -e "${YELLOW}Killing any remaining runner processes...${NC}"
pkill -KILL -f "Runner.Listener" 2>/dev/null || true
pkill -KILL -f "Runner.Worker" 2>/dev/null || true
pkill -KILL -f "dotnet.*Runner" 2>/dev/null || true

# Clean up runner state files
echo -e "${YELLOW}Cleaning up runner state files...${NC}"
for i in $(seq 1 $RUNNER_COUNT); do
    RUNNER_DIR="$RUNNER_HOME/${POOL_NAME}-runner-$i"
    if [ -d "$RUNNER_DIR" ]; then
        echo "Cleaning up $RUNNER_DIR..."
        sudo -u github-runner rm -f "$RUNNER_DIR/.runner" 2>/dev/null || true
        sudo -u github-runner rm -f "$RUNNER_DIR/.credentials" 2>/dev/null || true
        sudo -u github-runner rm -f "$RUNNER_DIR/.credentials_rsaparams" 2>/dev/null || true
        sudo -u github-runner rm -rf "$RUNNER_DIR/_work" 2>/dev/null || true
        echo -e "${GREEN}Cleaned up $RUNNER_DIR${NC}"
    fi
done

echo ""
echo -e "${GREEN}Cleanup completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run: sudo ./install.sh   (to re-register runners)"
echo "2. Run: sudo ./run.sh       (to start runners)"
echo ""
echo "Or use systemd directly:"
echo "  sudo systemctl start github-runner-paco.target"
