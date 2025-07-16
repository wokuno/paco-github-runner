#!/bin/bash

# GitHub Runner Run Script
# This script starts all GitHub self-hosted runners

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
POOL_NAME="paco"
RUNNER_HOME="/opt/github-runner"

# Get runner count from config file
CONFIG_FILE="$RUNNER_HOME/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# If RUNNER_COUNT not set, detect from directories
if [[ -z "$RUNNER_COUNT" ]]; then
    RUNNER_COUNT=$(find "$RUNNER_HOME" -maxdepth 1 -name "${POOL_NAME}-runner-*" -type d 2>/dev/null | wc -l)
    if [[ $RUNNER_COUNT -eq 0 ]]; then
        echo -e "${RED}No runner directories found${NC}"
        echo -e "${YELLOW}Please run ./setup.sh first${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Starting GitHub Runners...${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Function to check service status
check_service_status() {
    local service_name="$1"
    if systemctl is-active --quiet "$service_name"; then
        echo -e "${GREEN}✓${NC}"
    elif systemctl is-failed --quiet "$service_name"; then
        echo -e "${RED}✗ (failed)${NC}"
    else
        echo -e "${YELLOW}○ (inactive)${NC}"
    fi
}

# Start all runner services
echo -e "${YELLOW}Starting runner services...${NC}"
for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    echo -n "Starting $SERVICE_NAME... "
    
    if systemctl start "$SERVICE_NAME"; then
        echo -e "${GREEN}Started${NC}"
    else
        echo -e "${RED}Failed${NC}"
        echo -e "${YELLOW}Check logs with: journalctl -u $SERVICE_NAME${NC}"
    fi
done

# Wait a moment for services to initialize
sleep 2

# Display status
echo ""
echo -e "${YELLOW}Service Status:${NC}"
echo "┌─────────────────────────────────┬────────┐"
echo "│ Service Name                    │ Status │"
echo "├─────────────────────────────────┼────────┤"

for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    STATUS=$(check_service_status "$SERVICE_NAME")
    printf "│ %-31s │ %-6s │\n" "$SERVICE_NAME" "$STATUS"
done

echo "└─────────────────────────────────┴────────┘"

# Check if any services failed
FAILED_SERVICES=()
for i in $(seq 1 $RUNNER_COUNT); do
    SERVICE_NAME="github-runner-${POOL_NAME}-$i"
    if systemctl is-failed --quiet "$SERVICE_NAME"; then
        FAILED_SERVICES+=("$SERVICE_NAME")
    fi
done

if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failed services detected:${NC}"
    for service in "${FAILED_SERVICES[@]}"; do
        echo -e "${RED}  - $service${NC}"
    done
    echo ""
    echo -e "${YELLOW}To troubleshoot:${NC}"
    echo "  journalctl -u <service-name> -f"
    echo "  systemctl status <service-name>"
    exit 1
fi

echo ""
echo -e "${GREEN}All runners started successfully!${NC}"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  View all logs:      journalctl -u 'github-runner-${POOL_NAME}-*' -f"
echo "  View single log:    journalctl -u github-runner-${POOL_NAME}-1 -f"
echo "  Check status:       systemctl status github-runner-${POOL_NAME}-1"
echo "  Stop all:           /opt/github-runner/scripts/stop-all.sh"
echo "  Restart service:    systemctl restart github-runner-${POOL_NAME}-1"
echo ""
echo -e "${YELLOW}Monitor runners at:${NC}"
echo "  https://github.com/settings/actions/runners (for user repos)"
echo "  https://github.com/your-org/settings/actions/runners (for org repos)"
