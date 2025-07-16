#!/bin/bash

# GitHub Runner Setup Script
# This script sets up the environment for GitHub self-hosted runners

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RUNNER_USER="github-runner"
RUNNER_HOME="/opt/github-runner"
POOL_NAME="paco"

echo -e "${GREEN}Starting GitHub Runner Setup...${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo -e "${RED}Cannot detect OS distribution${NC}"
    exit 1
fi

echo -e "${YELLOW}Detected OS: $OS $VER${NC}"

# Ask for number of runners
echo ""
echo -e "${BLUE}Runner Configuration:${NC}"
echo "How many GitHub runners would you like to set up?"
echo "• Recommended: 2-4 runners for most use cases"
echo "• More runners = higher concurrency but more resource usage"
echo "• You can always modify this later by re-running the setup"
echo ""

while true; do
    read -p "Number of runners (1-10): " RUNNER_COUNT
    
    # Validate input
    if [[ "$RUNNER_COUNT" =~ ^[0-9]+$ ]] && [ "$RUNNER_COUNT" -ge 1 ] && [ "$RUNNER_COUNT" -le 10 ]; then
        break
    else
        echo -e "${RED}Please enter a number between 1 and 10${NC}"
    fi
done

echo -e "${GREEN}Setting up $RUNNER_COUNT runners in the '$POOL_NAME' pool${NC}"
echo ""

# Update system packages and install dependencies based on distribution
case $OS in
    ubuntu|debian)
        echo -e "${YELLOW}Updating system packages (Debian/Ubuntu)...${NC}"
        apt-get update && apt-get upgrade -y
        
        echo -e "${YELLOW}Installing required packages...${NC}"
        apt-get install -y \
            curl \
            wget \
            jq \
            tar \
            sudo \
            systemd \
            git \
            build-essential \
            libssl-dev \
            libffi-dev \
            python3-dev \
            python3-pip
        ;;
    rhel|centos|fedora|almalinux|rocky)
        echo -e "${YELLOW}Updating system packages (RHEL/CentOS/Fedora)...${NC}"
        if command -v dnf >/dev/null 2>&1; then
            PKG_MGR="dnf"
        else
            PKG_MGR="yum"
        fi
        
        $PKG_MGR update -y
        
        echo -e "${YELLOW}Installing required packages...${NC}"
        $PKG_MGR install -y \
            curl \
            wget \
            jq \
            tar \
            sudo \
            systemd \
            git \
            gcc \
            gcc-c++ \
            make \
            openssl-devel \
            libffi-devel \
            python3-devel \
            python3-pip
        
        # Enable and start systemd if not already running
        systemctl enable systemd-resolved 2>/dev/null || true
        ;;
    opensuse*|sles)
        echo -e "${YELLOW}Updating system packages (openSUSE/SLES)...${NC}"
        zypper refresh
        zypper update -y
        
        echo -e "${YELLOW}Installing required packages...${NC}"
        zypper install -y \
            curl \
            wget \
            jq \
            tar \
            sudo \
            systemd \
            git \
            gcc \
            gcc-c++ \
            make \
            libopenssl-devel \
            libffi-devel \
            python3-devel \
            python3-pip \
            zlib-devel \
            krb5-devel \
            libicu-devel \
            glibc-locale \
            ca-certificates
        
        # Try to install .NET Core dependencies for openSUSE
        echo -e "${YELLOW}Installing additional .NET dependencies for openSUSE...${NC}"
        zypper install -y \
            libssl1_1 \
            libicu \
            liblttng-ust0 \
            libunwind \
            libuuid1 \
            zlib \
            libstdc++6 || echo -e "${YELLOW}Some .NET dependencies may not be available on this version${NC}"
        ;;
    *)
        echo -e "${RED}Unsupported OS: $OS${NC}"
        echo -e "${YELLOW}Supported distributions: Ubuntu, Debian, RHEL, CentOS, Fedora, AlmaLinux, Rocky Linux, openSUSE, SLES${NC}"
        exit 1
        ;;
esac

# Create runner user
echo -e "${YELLOW}Creating runner user...${NC}"
if ! id "$RUNNER_USER" &>/dev/null; then
    case $OS in
        ubuntu|debian)
            useradd -r -m -d "$RUNNER_HOME" -s /bin/bash "$RUNNER_USER"
            ;;
        rhel|centos|fedora|almalinux|rocky)
            useradd -r -m -d "$RUNNER_HOME" -s /bin/bash "$RUNNER_USER"
            ;;
        opensuse*|sles)
            useradd -r -m -d "$RUNNER_HOME" -s /bin/bash "$RUNNER_USER"
            ;;
    esac
    echo -e "${GREEN}Created user: $RUNNER_USER${NC}"
else
    echo -e "${YELLOW}User $RUNNER_USER already exists${NC}"
fi

# Create runner directories
echo -e "${YELLOW}Creating runner directories...${NC}"
for i in $(seq 1 $RUNNER_COUNT); do
    RUNNER_DIR="$RUNNER_HOME/${POOL_NAME}-runner-$i"
    mkdir -p "$RUNNER_DIR"
    chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"
    echo -e "${GREEN}Created directory: $RUNNER_DIR${NC}"
done

# Create logs directory
mkdir -p "$RUNNER_HOME/logs"
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/logs"

# Create scripts directory
mkdir -p "$RUNNER_HOME/scripts"
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/scripts"

# Download and extract GitHub Actions Runner
echo -e "${YELLOW}Downloading GitHub Actions Runner...${NC}"
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
RUNNER_ARCH="x64"

# Detect architecture
if [[ $(uname -m) == "aarch64" ]]; then
    RUNNER_ARCH="arm64"
fi

RUNNER_DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

cd "$RUNNER_HOME"
wget -O actions-runner.tar.gz "$RUNNER_DOWNLOAD_URL"

# Extract runner to each directory
for i in $(seq 1 $RUNNER_COUNT); do
    RUNNER_DIR="$RUNNER_HOME/${POOL_NAME}-runner-$i"
    echo -e "${YELLOW}Extracting runner to $RUNNER_DIR...${NC}"
    tar -xzf actions-runner.tar.gz -C "$RUNNER_DIR"
    chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"
done

# Clean up downloaded archive
rm actions-runner.tar.gz

# Install runner dependencies
echo -e "${YELLOW}Installing runner dependencies...${NC}"
for i in $(seq 1 $RUNNER_COUNT); do
    RUNNER_DIR="$RUNNER_HOME/${POOL_NAME}-runner-$i"
    cd "$RUNNER_DIR"
    
    echo -e "${YELLOW}Installing dependencies for runner $i...${NC}"
    
    # Run dependency installation as root, but don't fail if some deps are missing
    if ./bin/installdependencies.sh; then
        echo -e "${GREEN}Dependencies installed successfully for runner $i${NC}"
    else
        echo -e "${YELLOW}Warning: Some dependencies may not be available for this distribution${NC}"
        echo -e "${YELLOW}This is common on newer distributions like openSUSE Leap 16.0 Beta${NC}"
        echo -e "${YELLOW}The runner should still work for most use cases${NC}"
    fi
    
    chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"
done

# Additional manual dependency installation for problematic distributions
if [[ "$OS" == opensuse* && "$VER" == "16.0" ]]; then
    echo -e "${YELLOW}Applying workarounds for openSUSE Leap 16.0 Beta...${NC}"
    
    # Try to install missing ICU library with different name
    zypper install -y libicu-devel libicu70 || true
    
    # Create symlinks for commonly missing libraries
    if [ -f /usr/lib64/libssl.so.3 ] && [ ! -f /usr/lib64/libssl.so.1.1 ]; then
        ln -sf /usr/lib64/libssl.so.3 /usr/lib64/libssl.so.1.1 || true
    fi
    
    if [ -f /usr/lib64/libcrypto.so.3 ] && [ ! -f /usr/lib64/libcrypto.so.1.1 ]; then
        ln -sf /usr/lib64/libcrypto.so.3 /usr/lib64/libcrypto.so.1.1 || true
    fi
    
    echo -e "${GREEN}Applied openSUSE-specific workarounds${NC}"
fi

# Interactive configuration
echo ""
echo -e "${GREEN}=== GitHub Runner Configuration ===${NC}"
echo -e "${YELLOW}Please provide the following information to configure your runners:${NC}"
echo ""

# Function to read input with default value
read_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [[ -n "$default" ]]; then
        echo -n -e "${prompt} [${default}]: "
    else
        echo -n -e "${prompt}: "
    fi
    
    read -r input
    if [[ -z "$input" && -n "$default" ]]; then
        eval "$var_name=\"$default\""
    else
        eval "$var_name=\"$input\""
    fi
}

# Detect architecture for default labels
ARCH_LABEL="X64"
if [[ $(uname -m) == "aarch64" ]]; then
    ARCH_LABEL="ARM64"
fi

# Add OS-specific label based on detected distribution
OS_LABEL=""
case $OS in
    ubuntu) OS_LABEL="ubuntu" ;;
    debian) OS_LABEL="debian" ;;
    rhel) OS_LABEL="rhel" ;;
    centos) OS_LABEL="centos" ;;
    fedora) OS_LABEL="fedora" ;;
    almalinux) OS_LABEL="almalinux" ;;
    rocky) OS_LABEL="rocky" ;;
    opensuse*) OS_LABEL="opensuse" ;;
    sles) OS_LABEL="sles" ;;
esac

DEFAULT_LABELS="self-hosted,Linux,$ARCH_LABEL,paco"
if [[ -n "$OS_LABEL" ]]; then
    DEFAULT_LABELS="$DEFAULT_LABELS,$OS_LABEL"
fi

# GitHub Token
echo -e "${BLUE}GitHub Token Information:${NC}"
echo "• Go to: https://github.com/settings/tokens"
echo "• For organization runners: admin:org, repo permissions"
echo "• For repository runners: repo permission"
echo ""
read_with_default "${YELLOW}GitHub Token (ghp_...)" "" "GITHUB_TOKEN"

if [[ -z "$GITHUB_TOKEN" ]]; then
    echo -e "${RED}Error: GitHub token is required${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Runner Registration Target:${NC}"
echo "Choose where to register your runners:"
echo "1) Organization (recommended for teams)"
echo "2) User account (for personal repositories)"
echo "3) Specific repository"
echo ""
read -p "Select option (1-3): " REGISTRATION_TYPE

case $REGISTRATION_TYPE in
    1)
        echo ""
        read_with_default "${YELLOW}GitHub Organization name" "" "GITHUB_ORG"
        if [[ -z "$GITHUB_ORG" ]]; then
            echo -e "${RED}Error: Organization name is required${NC}"
            exit 1
        fi
        GITHUB_USER=""
        GITHUB_REPO_URL=""
        ;;
    2)
        echo ""
        read_with_default "${YELLOW}GitHub Username" "" "GITHUB_USER"
        if [[ -z "$GITHUB_USER" ]]; then
            echo -e "${RED}Error: Username is required${NC}"
            exit 1
        fi
        GITHUB_ORG=""
        GITHUB_REPO_URL=""
        ;;
    3)
        echo ""
        echo "Format: https://github.com/user/repo or https://github.com/org/repo"
        read_with_default "${YELLOW}Repository URL" "" "GITHUB_REPO_URL"
        if [[ -z "$GITHUB_REPO_URL" ]]; then
            echo -e "${RED}Error: Repository URL is required${NC}"
            exit 1
        fi
        GITHUB_ORG=""
        GITHUB_USER=""
        ;;
    *)
        echo -e "${RED}Invalid option selected${NC}"
        exit 1
        ;;
esac

echo ""
read_with_default "${YELLOW}Runner Labels (comma-separated)" "$DEFAULT_LABELS" "RUNNER_LABELS"
read_with_default "${YELLOW}Runner Group (for organizations)" "default" "RUNNER_GROUP"

# Create configuration file
echo ""
echo -e "${YELLOW}Creating configuration file...${NC}"
cat > "$RUNNER_HOME/config.env" << EOF
# GitHub Runner Configuration
# Generated by setup script on $(date)

# Number of runners in the pool
RUNNER_COUNT="$RUNNER_COUNT"

# GitHub Token (with repo and admin:org permissions)
GITHUB_TOKEN="$GITHUB_TOKEN"

# GitHub User or Organization
GITHUB_USER="$GITHUB_USER"

# GitHub Organization (if registering to org, leave empty for user repos)
GITHUB_ORG="$GITHUB_ORG"

# Repository URL (optional, for repo-specific runners)
# Format: https://github.com/user/repo or https://github.com/org/repo
GITHUB_REPO_URL="$GITHUB_REPO_URL"

# Runner Labels (comma-separated)
RUNNER_LABELS="$RUNNER_LABELS"

# Runner Group (for organizations)
RUNNER_GROUP="$RUNNER_GROUP"
EOF

# Set proper permissions
chown "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/config.env"
chmod 600 "$RUNNER_HOME/config.env"  # Restrict access to config file

# Also create template for reference
cat > "$RUNNER_HOME/config.template" << 'EOF'
# GitHub Runner Configuration Template
# Copy this file to config.env and fill in your values

# GitHub Token (with repo and admin:org permissions)
GITHUB_TOKEN=""

# GitHub User or Organization
GITHUB_USER=""

# GitHub Organization (if registering to org, leave empty for user repos)
GITHUB_ORG=""

# Repository URL (optional, for repo-specific runners)
# Format: https://github.com/user/repo or https://github.com/org/repo
GITHUB_REPO_URL=""

# Runner Labels (comma-separated)
RUNNER_LABELS="self-hosted,Linux,X64,paco"

# Runner Group (for organizations)
RUNNER_GROUP="default"
EOF

chown "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/config.template"

echo -e "${GREEN}Configuration saved to: $RUNNER_HOME/config.env${NC}"
echo -e "${YELLOW}Template saved to: $RUNNER_HOME/config.template${NC}"

# Display configuration summary
echo ""
echo -e "${GREEN}=== Configuration Summary ===${NC}"
if [[ -n "$GITHUB_ORG" ]]; then
    echo -e "${BLUE}Registration Type:${NC} Organization"
    echo -e "${BLUE}Organization:${NC} $GITHUB_ORG"
elif [[ -n "$GITHUB_USER" ]]; then
    echo -e "${BLUE}Registration Type:${NC} User Account"
    echo -e "${BLUE}Username:${NC} $GITHUB_USER"
else
    echo -e "${BLUE}Registration Type:${NC} Repository"
    echo -e "${BLUE}Repository:${NC} $GITHUB_REPO_URL"
fi
echo -e "${BLUE}Runner Labels:${NC} $RUNNER_LABELS"
echo -e "${BLUE}Runner Group:${NC} $RUNNER_GROUP"
echo -e "${BLUE}Pool Name:${NC} $POOL_NAME"
echo -e "${BLUE}Runner Count:${NC} $RUNNER_COUNT"

echo -e "${GREEN}Setup completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review configuration in: $RUNNER_HOME/config.env"
echo "2. Run ./install.sh to configure and register the runners"
echo "3. Run ./run.sh to start the runners as systemd services"
echo ""
echo -e "${BLUE}Configuration can be modified later by editing:${NC}"
echo "  $RUNNER_HOME/config.env"
echo ""
echo -e "${YELLOW}Ready to proceed with installation!${NC}"
