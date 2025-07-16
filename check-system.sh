#!/bin/bash

# System Check Script for GitHub Runner Setup
# This script checks if your system is compatible and shows detected configuration

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GitHub Runner System Check ===${NC}"
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} Running as root"
else
    echo -e "${YELLOW}!${NC} Not running as root (required for setup)"
fi

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    PRETTY=$PRETTY_NAME
    echo -e "${GREEN}✓${NC} OS detected: $PRETTY"
    
    # Check if distribution is supported
    case $OS in
        ubuntu|debian)
            echo -e "${GREEN}✓${NC} Supported distribution (Debian-based)"
            PKG_MGR="apt-get"
            ;;
        rhel|centos|fedora|almalinux|rocky)
            echo -e "${GREEN}✓${NC} Supported distribution (RHEL-based)"
            if command -v dnf >/dev/null 2>&1; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            ;;
        opensuse*|sles)
            echo -e "${GREEN}✓${NC} Supported distribution (SUSE-based)"
            PKG_MGR="zypper"
            ;;
        *)
            echo -e "${RED}✗${NC} Unsupported distribution"
            echo -e "${YELLOW}  Supported: Ubuntu, Debian, RHEL, CentOS, Fedora, AlmaLinux, Rocky Linux, openSUSE, SLES${NC}"
            ;;
    esac
    echo -e "${BLUE}  Package manager: $PKG_MGR${NC}"
else
    echo -e "${RED}✗${NC} Cannot detect OS distribution"
fi

# Check systemd
if command -v systemctl >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} systemd available"
    if systemctl is-system-running >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} systemd is running"
    else
        echo -e "${YELLOW}!${NC} systemd may not be fully operational"
    fi
else
    echo -e "${RED}✗${NC} systemd not found (required)"
fi

# Check internet connectivity
if curl -s --max-time 5 https://api.github.com >/dev/null; then
    echo -e "${GREEN}✓${NC} Internet connectivity to GitHub"
else
    echo -e "${RED}✗${NC} Cannot reach GitHub API"
fi

# Check for existing installation
if [ -d "/opt/github-runner" ]; then
    echo -e "${YELLOW}!${NC} Existing installation found at /opt/github-runner"
else
    echo -e "${GREEN}✓${NC} No existing installation detected"
fi

# Check for existing user
if id "github-runner" &>/dev/null; then
    echo -e "${YELLOW}!${NC} User 'github-runner' already exists"
else
    echo -e "${GREEN}✓${NC} User 'github-runner' available"
fi

# Check disk space
AVAILABLE=$(df /opt 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
if [ "$AVAILABLE" -gt 1048576 ]; then  # 1GB in KB
    echo -e "${GREEN}✓${NC} Sufficient disk space available"
else
    echo -e "${YELLOW}!${NC} Low disk space (less than 1GB available)"
fi

# Check architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        echo -e "${GREEN}✓${NC} Architecture: x64 (supported)"
        ;;
    aarch64|arm64)
        echo -e "${GREEN}✓${NC} Architecture: arm64 (supported)"
        ;;
    *)
        echo -e "${YELLOW}!${NC} Architecture: $ARCH (may not be supported)"
        ;;
esac

# Check required commands
echo ""
echo -e "${BLUE}=== Required Tools Check ===${NC}"

TOOLS=("curl" "wget" "tar" "sudo" "git")
for tool in "${TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $tool"
    else
        echo -e "${RED}✗${NC} $tool (will be installed)"
    fi
done

# Check for jq (critical for GitHub API)
if command -v jq >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} jq"
else
    echo -e "${RED}✗${NC} jq (will be installed)"
fi

echo ""
echo -e "${BLUE}=== Network Configuration ===${NC}"

# Check if firewall is active
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo -e "${YELLOW}!${NC} UFW firewall is active"
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    echo -e "${YELLOW}!${NC} firewalld is active"
else
    echo -e "${GREEN}✓${NC} No active firewall detected"
fi

# Check DNS resolution
if nslookup github.com >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} DNS resolution working"
else
    echo -e "${RED}✗${NC} DNS resolution issues"
fi

echo ""
echo -e "${BLUE}=== Recommendations ===${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}•${NC} Run this script with sudo to perform setup"
fi

case $OS in
    rhel|centos)
        if [ ! -f /etc/yum.repos.d/epel.repo ]; then
            echo -e "${YELLOW}•${NC} Consider installing EPEL repository: sudo yum install epel-release"
        fi
        ;;
    opensuse*)
        echo -e "${YELLOW}•${NC} Ensure repositories are up to date: sudo zypper refresh"
        ;;
esac

echo ""
echo -e "${GREEN}System check complete!${NC}"
