# Paco GitHub Runner

A complete solution for setting up and managing GitHub self-hosted runners as systemd services. This project creates a configurable pool of runners named "paco" (1-10 runners) that can be used for GitHub Actions workflows.

## Features

- **Automated Setup**: Complete installation and configuration scripts
- **Systemd Integration**: Runners run as systemd services with automatic restart
- **Pool Management**: Creates a configurable pool of "paco" runners (1-10 runners)
- **Security**: Runs with dedicated user and proper permissions
- **Monitoring**: Built-in logging and status monitoring
- **Easy Management**: Scripts for start, stop, status, and log viewing

## Quick Start

### 0. System Check (Optional)

Before starting, you can run the system check script to verify compatibility:

```bash
sudo ./check-system.sh
```

This will check:
- OS distribution support
- Required tools availability
- systemd status
- Network connectivity
- Disk space
- Architecture compatibility

### Three-Step Process:

1. **Setup**: `sudo ./setup.sh` - Install dependencies and configure interactively
2. **Install**: `sudo ./install.sh` - Register runners with GitHub and create services
3. **Run**: `sudo ./run.sh` - Start all runners

The setup script will guide you through the configuration process, asking for your GitHub token, organization/user details, and runner preferences.

## Interactive Configuration

During setup, you'll be prompted for:

### GitHub Token
Create a token at [https://github.com/settings/tokens](https://github.com/settings/tokens) with:

**For Organization Runners:**
- `admin:org` - Manage organization runners
- `repo` - Access repositories

**For Repository Runners:**
- `repo` - Full repository access

### Registration Target
Choose one of:
1. **Organization** - Register runners at the organization level (recommended for teams)
2. **User Account** - Register runners for your personal repositories
3. **Specific Repository** - Register runners for a single repository

### Runner Configuration
- **Number of Runners**: Choose how many runners to create (1-10)
- **Labels**: Auto-detected based on your system (OS, architecture) + "paco" pool identifier
- **Group**: Runner group for organization (default: "paco")
  - Create the "paco" group in your GitHub organization settings if it doesn't exist
  - This allows you to organize and manage runners by teams or projects
  - Repository-level runners don't use groups

### 1. Setup

First, run the setup script to install dependencies and create the runner environment:

```bash
sudo ./setup.sh
```

This script will:
- Detect your Linux distribution automatically
- Install required packages using the appropriate package manager
- Create a dedicated `github-runner` user
- Download and extract GitHub Actions Runner
- Set up directory structure
- **Interactively configure your GitHub settings**
- Create the configuration file

During setup, you'll be prompted for:
- **Number of Runners**: How many runners to create (1-10, recommended: 2-4)
- **GitHub Token**: Personal access token with appropriate permissions
- **Registration Target**: Organization, user account, or specific repository
- **Runner Labels**: Tags to identify your runners (auto-detected based on OS/architecture)
- **Runner Group**: For organization runners

#### Distribution-Specific Setup Notes

**RHEL/CentOS 7:**
```bash
# Enable EPEL repository first (if not already enabled)
sudo yum install epel-release
sudo ./setup.sh
```

**openSUSE:**
```bash
# Refresh repositories first
sudo zypper refresh
sudo ./setup.sh
```

**Fedora:**
```bash
# No additional steps needed
sudo ./setup.sh
```

### 2. Install

Configure and register the runners with GitHub:

```bash
sudo ./install.sh
```

This will:
- Use the configuration created during setup
- Register the specified number of runners with GitHub
- Create systemd service files for each runner
- Enable services for auto-start
- Create management scripts

### 3. Run

Start all runners:

```bash
sudo ./run.sh
```

## Manual Configuration (Optional)

If you need to modify the configuration after setup, edit:

```bash
sudo nano /opt/github-runner/config.env
```

Then re-run the install script:

```bash
sudo ./install.sh
```

## Configuration

The configuration is created interactively during setup, but you can review or modify it later:

```bash
sudo nano /opt/github-runner/config.env
```

Example configuration file:

```bash
# GitHub Token (required)
GITHUB_TOKEN="ghp_your_token_here"

# For organization runners
GITHUB_ORG="your-org-name"

# For user repositories
GITHUB_USER="your-username"

# For repository-specific runners (optional)
GITHUB_REPO_URL="https://github.com/user/repo"

# Runner labels (auto-detected + custom)
RUNNER_LABELS="self-hosted,Linux,X64,paco,ubuntu"

# Runner group (for organizations)
RUNNER_GROUP="paco"
```

After modifying the configuration, re-run:
```bash
sudo ./install.sh
```

## Management Commands

### Systemd Target Management (Recommended)

The easiest way to manage all runners as a group:

```bash
# Start all runners
sudo systemctl start github-runner-paco.target

# Stop all runners
sudo systemctl stop github-runner-paco.target

# Stop all runners (forceful if needed)
sudo /opt/github-runner/scripts/stop-target.sh

# Restart all runners
sudo systemctl restart github-runner-paco.target

# Check status of all runners
sudo systemctl status github-runner-paco.target

# Enable auto-start on boot
sudo systemctl enable github-runner-paco.target
```

### Script Management

Alternative management using provided scripts:

```bash
# Start all runners
sudo /opt/github-runner/scripts/start-all.sh

# Stop all runners
sudo /opt/github-runner/scripts/stop-all.sh

# Emergency stop (kill all runners forcefully)
sudo /opt/github-runner/scripts/kill-all.sh

# Check status of all runners
sudo /opt/github-runner/scripts/status-all.sh
```

### Individual Service Management

For managing specific runners:

```bash
# Manage individual runners
sudo systemctl start github-runner-paco-1
sudo systemctl stop github-runner-paco-1
sudo systemctl restart github-runner-paco-1
sudo systemctl status github-runner-paco-1
```

### Viewing Logs

```bash
# View logs for all runners
sudo /opt/github-runner/scripts/logs-all.sh all -f

# View logs for specific runner
sudo /opt/github-runner/scripts/logs-all.sh 1 -f

# Or use journalctl directly
sudo journalctl -u github-runner-paco-1 -f
sudo journalctl -u 'github-runner-paco-*' -f
```

## Directory Structure

```
/opt/github-runner/
├── paco-runner-1/          # Runner 1 directory
├── paco-runner-2/          # Runner 2 directory
├── paco-runner-N/          # Additional runners based on your selection
├── logs/                   # Log directory
├── scripts/                # Management scripts
│   ├── start-all.sh
│   ├── stop-all.sh
│   ├── status-all.sh
│   └── logs-all.sh
├── config.env             # Your configuration
└── config.template        # Configuration template
```

## Systemd Services

The installation creates systemd services for each runner plus a target for managing them as a group:

**Individual Services:**
- `github-runner-paco-1.service`
- `github-runner-paco-2.service`
- `github-runner-paco-N.service` (based on your selection)

**Group Target:**
- `github-runner-paco.target` - Controls all runners as a single unit

Services are configured with:
- Automatic restart on failure
- Proper security settings
- Logging to systemd journal
- User isolation

## Using in GitHub Actions

Once runners are registered, use them in your workflows:

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: [self-hosted, paco]
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          echo "Running on paco runner pool"
          # Your build/test commands here
```

## Troubleshooting

### Check Runner Status

```bash
# View service status
sudo systemctl status github-runner-paco-1

# View recent logs
sudo journalctl -u github-runner-paco-1 --since "1 hour ago"

# Follow logs in real-time
sudo journalctl -u github-runner-paco-1 -f
```

### Common Issues

1. **Registration fails**: Check GitHub token permissions
2. **Service won't start**: Check logs with `journalctl`
3. **Runner offline**: Restart service with `systemctl restart`
4. **Permission issues**: Ensure proper ownership of runner directories

### Distribution-Specific Issues

**RHEL/CentOS 7:**
- May need to enable systemd services: `systemctl enable systemd-resolved`
- Ensure EPEL repository is available for `jq`: `yum install epel-release`

**openSUSE:**
- If `jq` is not found, install from official repositories: `zypper ar -f https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/ utilities`

**Fedora:**
- Uses `dnf` by default, but the script will fall back to `yum` if needed
- SELinux may need configuration for custom services

### Firewall Configuration

If you have a firewall enabled, you may need to configure it:

**Ubuntu/Debian (ufw):**
```bash
# Usually no additional config needed for outbound connections
```

**RHEL/CentOS/Fedora/AlmaLinux/Rocky (firewalld):**
```bash
# Usually no additional config needed for outbound connections
# If using custom ports, open them:
# firewall-cmd --permanent --add-port=8080/tcp
# firewall-cmd --reload
```

**openSUSE (SuSEfirewall2/firewalld):**
```bash
# Usually no additional config needed for outbound connections
```

### Re-register Runners

If you need to re-register runners:

```bash
# Stop services
sudo /opt/github-runner/scripts/stop-all.sh

# Run install again
sudo ./install.sh

# Start services
sudo ./run.sh
```

### Stopping Issues

If runners don't stop properly with normal systemctl commands:

```bash
# Try the enhanced stop script (includes timeout and kill)
sudo /opt/github-runner/scripts/stop-all.sh

# For systemd target with enhanced stopping
sudo /opt/github-runner/scripts/stop-target.sh

# Emergency stop - kills all runner processes immediately
sudo /opt/github-runner/scripts/kill-all.sh

# After emergency stop, restart normally
sudo systemctl start github-runner-paco.target
```

**Why this happens:**
- GitHub Actions runners sometimes don't respond to SIGTERM signals
- Runners may be stuck waiting for jobs to complete
- The enhanced scripts use SIGKILL after timeout for reliable stopping

## Uninstall

To completely remove the runners:

```bash
sudo ./uninstall.sh
```

This will:
- Stop and disable all services
- Unregister runners from GitHub
- Remove all files and directories
- Delete the runner user

## Requirements

- Linux system with systemd (Ubuntu, Debian, RHEL, CentOS, Fedora, AlmaLinux, Rocky Linux, openSUSE, SLES)
- Root/sudo access
- Internet connection
- GitHub account with appropriate permissions

## Supported Distributions

The scripts automatically detect your Linux distribution and use the appropriate package manager:

- **Debian/Ubuntu**: Uses `apt-get`
- **RHEL/CentOS/Fedora/AlmaLinux/Rocky**: Uses `dnf` or `yum` 
- **openSUSE/SLES**: Uses `zypper`

Package mappings:
- Build tools: `build-essential` (Debian) → `gcc gcc-c++ make` (RHEL/openSUSE)
- SSL development: `libssl-dev` (Debian) → `openssl-devel` (RHEL) → `libopenssl-devel` (openSUSE)
- FFI development: `libffi-dev` (Debian) → `libffi-devel` (RHEL/openSUSE)
- Python development: `python3-dev` (Debian) → `python3-devel` (RHEL/openSUSE)

## Security Notes

- Runners run as dedicated `github-runner` user
- Services use security restrictions (NoNewPrivileges, PrivateTmp, etc.)
- Limited filesystem access
- Token should have minimal required permissions

## License

MIT License - see LICENSE file for details.