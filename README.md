# Automating `polkitd` Memory Leak Management on Linux Servers


<p align="center">
    <a href="https://github.com/kreee00/polkitd-memory-manager/blob/main/LICENSE" alt="License">
        <img src="https://img.shields.io/badge/License-MIT-green.svg" /></a>
    <a href="https://ubuntu.com" alt="Platform">
        <img src="https://img.shields.io/badge/Platform-Linux-important" /></a>
    <a href="https://ubuntu.com" alt="Ubuntu Compatible">
        <img src="https://img.shields.io/badge/Tested%20on-Ubuntu%2022.04%20|%2024.04-dd4814" /></a>
    <a href="https://github.com/kreee00/polkitd-memory-manager/releases" alt="Release Status">
        <img src="https://img.shields.io/badge/Status-Production%20Ready-brightgreen" /></a>
    <a href="https://systemd.io" alt="Systemd Requirement">
        <img src="https://img.shields.io/badge/Requires-systemd-critical" /></a>
    <a href="https://github.com/kreee00/polkitd-memory-manager/pulse" alt="Activity">
        <img src="https://img.shields.io/github/commit-activity/m/kreee00/polkitd-memory-manager" /></a>
    <a href="https://github.com/kreee00/polkitd-memory-manager/issues" alt="Open Issues">
        <img src="https://img.shields.io/github/issues/kreee00/polkitd-memory-manager" /></a>
    <a href="https://github.com/kreee00/polkitd-memory-manager/stargazers" alt="Stars">
        <img src="https://img.shields.io/github/stars/kreee00/polkitd-memory-manager" /></a>
    <a href="https://github.com/kreee00/polkitd-memory-manager/forks" alt="Forks">
        <img src="https://img.shields.io/github/forks/kreee00/polkitd-memory-manager" /></a>
</p>

## 🚨 Problem Statement

`polkitd` (PolicyKit daemon) is a critical Linux system service responsible for managing system-wide privileges. A known issue causes `polkitd` to experience **memory leaks**, where its memory consumption grows uncontrollably—sometimes exceeding 5GB—until it consumes most available system memory, leading to server instability, Docker container failures, and service disruptions.

## 🛡️ Solution Overview

This repository provides a **two-layer automated protection system**:

1. **Primary Defense**: `earlyoom` hook script that gracefully restarts `polkitd` when memory exceeds a configurable threshold (default: 12% of available memory)
2. **Fail-safe**: Systemd hard memory limit that forcibly contains `polkitd` if the hook fails

## 📋 Prerequisites

- Linux server with `systemd` (tested on Ubuntu 22.04/24.04)
- Root/sudo access
- `polkitd` version 124 or higher (check with `polkitd --version`)

## 🔧 Installation & Configuration

### Step 1: Clone and Prepare the Repository

```bash
# Clone this repository
git clone https://github.com/kreee00/polkitd-memory-manager.git
cd polkitd-memory-manager

# Make scripts executable
chmod +x polkitd-memory-hook.sh
```

### Step 2: Install Dependencies

```bash
# Install earlyoom if not present (Debian-based distro)
sudo apt update
sudo apt install earlyoom -y
```

### Step 3: Deploy the Hook Script

```bash
# Copy the hook script to system location
sudo cp polkitd-memory-hook.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/polkitd-memory-hook.sh
```

### Step 4: Configure `earlyoom` to Use Only Your Hook

```bash
# Edit the earlyoom service to avoid killing other processes:
sudo systemctl edit earlyoom
```

Add:

**Configuration details**
```ini
[Service]
Environment="EARLYOOM_ARGS=-m 50 --avoid '.*' --hook '/usr/local/bin/polkitd-memory-hook.sh'"
ExecStart=
ExecStart=/usr/bin/earlyoom $EARLYOOM_ARGS
```
Note: `-m 50` triggers when system free memory drops below 5%. Combined with `--avoid '.*'`, only your hook runs.

### Step 5: Set Systemd Fail-safe Limit

Apply a hard memory limit (1.5GB) as a fail-safe measure:

```bash
# Make it permanent (survives reboot)
sudo systemctl set-property polkit.service MemoryMax=1500M
```
#### Why 1500M? Your polkitd peaked at 5GB during leaks. 1.5GB:

- Allows normal operation (~100MB)
- Permits some leak growth for detection
- Prevents system-crashing runaway leaks
- Is below typical earlyoom trigger thresholds

### Step 6: Verify Configuration

```bash
# Verify earlyoom configuration
sudo systemctl cat earlyoom | grep -A2 ExecStart

# Verify systemd limit
systemctl show polkit.service -p MemoryMax

# Test hook manually (should do nothing if memory is low)
sudo /usr/local/bin/polkitd-memory-hook.sh
```

### Step 7: Enable & Start Services

```bash
# Reload systemd and restart services
sudo systemctl daemon-reload
sudo systemctl restart earlyoom polkit.service

# Enable to start at boot
sudo systemctl enable earlyoom
```

## 📊 The Hook Script Explained

The main script (`polkitd-memory-hook.sh`) implements intelligent monitoring:

### Key Features
- **Robust PID detection**: Uses `pgrep` and `/proc` filesystem for reliability
- **Memory calculation**: Monitors both RSS (Resident Set Size) and available system memory
- **Configurable threshold**: Default 12% threshold, easily adjustable
- **Graceful restart**: Uses `systemctl restart` instead of forceful killing
- **Comprehensive logging**: All actions logged for debugging

### How It Works
1. **Check if `polkitd` is running** - Exit cleanly if not
2. **Read memory usage** - From `/proc/[PID]/status` (most reliable method)
3. **Calculate percentage** - `(polkitd memory / available memory) × 100`
4. **Compare to threshold** - Default 12% of available memory
5. **Restart if exceeded** - Graceful `systemctl restart polkit.service`

## 🎛️ Configuration Options

### Adjusting the Memory Threshold
Edit `/usr/local/bin/polkitd-memory-hook.sh`:

```bash
# Change this value (default: 12)
THRESHOLD_PERCENT=12
```

### Systemd Memory Limit Adjustment
To change the fail-safe limit:

```bash
# Set to 15% of total memory instead of 12%
sudo systemctl set-property polkit.service MemoryMax=$(( $(grep MemTotal /proc/meminfo | awk '{print $2/1024*0.15}') | awk '{printf "%.0fM", $1}'))
```

## 📈 Monitoring & Verification

### Real-time Monitoring Commands

```bash
# Monitor polkitd memory usage
watch -n 5 'echo "polkitd: $(grep VmRSS /proc/$(pgrep polkitd)/status | awk "{print \$2/1024\" MB\"}") / $(systemctl show polkit.service -p MemoryMax | cut -d= -f2) limit"'

# Check earlyoom logs
sudo journalctl -u earlyoom -f

# Monitor polkitd service restarts
sudo journalctl -u polkit.service -f | grep -E "(Started|Restarting)"
```

Expected output:
```
✅ polkitd is running (PID: 671013)
✅ Memory usage: 114.7 MB / 1843.2 MB limit (6.2%)
✅ earlyoom is active and using hook script
✅ Systemd memory limit is configured
```

## 🚨 Troubleshooting Guide

### Common Issues and Solutions

| Problem | Symptoms | Solution |
|---------|----------|----------|
| **Hook script not triggering** | No logs in `journalctl -u earlyoom` | Check earlyoom status: `sudo systemctl status earlyoom` |
| **polkitd still leaking** | Memory grows despite hook | Lower threshold or adjust systemd limit |
| **Permission errors** | Script can't restart polkitd | Ensure script runs as root via earlyoom |
| **Service disruptions** | Docker/web apps failing after restart | Check for orphaned ssh-agent processes |

### Diagnostic Commands

```bash
# Check for orphaned ssh-agent processes
ps -ef | grep ssh-agent | grep -v grep

# Verify systemd session state
loginctl list-sessions
loginctl show-session [SESSION_ID]

# Check polkitd version and status
polkitd --version 2>/dev/null || echo "Check /usr/lib/polkit-1/polkitd"
systemctl status polkit.service --no-pager -l
```

## 🔄 Manual Intervention (When Needed)

### Immediate Cleanup of Orphaned Processes

```bash
# Clear systemd-logind session state
sudo systemctl restart systemd-logind polkit.service

# Apply the service ordering workaround
sudo systemctl edit polkit.service
# Add: [Unit]\nBefore=systemd-logind.service
```

### Emergency Memory Release

```bash
# Manual restart of polkitd
sudo systemctl restart polkit.service

# Force earlyoom to trigger
sudo pkill -USR1 earlyoom  # Send test signal
```

## 📝 Logging and Alerting

### Log Locations
- **Hook script logs**: `journalctl -u earlyoom | grep polkitd-hook`
- **polkitd service logs**: `journalctl -u polkit.service`
- **System logs**: `journalctl -xe --since "1 hour ago"`

### Setting Up Alerts
Add to your monitoring system:

```bash
# Alert when polkitd is restarted
journalctl -u polkit.service --since "5 minutes ago" | grep -q "Started polkit.service" && send-alert "polkitd restarted"

# Alert when memory threshold exceeded
journalctl -u earlyoom --since "5 minutes ago" | grep -q "Threshold exceeded" && send-alert "polkitd memory threshold breached"
```

## 🔍 Advanced: Root Cause Analysis

For persistent leaks, investigate deeper:

```bash
# Monitor systemd-logind interactions
sudo journalctl -u systemd-logind -f

# Trace polkitd system calls (advanced)
sudo strace -p $(pgrep polkitd) -e trace=all -s 100 2>&1 | grep -v ENOENT

# Check D-Bus connections to polkitd
sudo busctl tree org.freedesktop.PolicyKit1
```

## 📚 References & Resources

### Related Issues
- [Ubuntu Launchpad Bug #1449478](https://bugs.launchpad.net/ubuntu/+source/policykit-1/+bug/1449478)
- [Red Hat Bugzilla #1189631](https://bugzilla.redhat.com/show_bug.cgi?id=1189631)
- [Arch Linux Wiki - Polkit Memory Leak](https://wiki.archlinux.org/title/Polkit#Memory_leak)
- [GitHub Issues - Polkit Memory Leak Mitigation using Systemd](https://github.com/polkit-org/polkit/pull/606)

### Key Concepts
- **RSS (Resident Set Size)**: Physical memory actually held in RAM
- **systemd resource control**: `MemoryMax`, `MemorySwapMax` properties
- **earlyoom**: Early Out Of Memory daemon for proactive memory management

## 🤝 Contributing

Found an issue or improvement?
1. Fork the repository
2. Create a feature branch
3. Submit a pull request with detailed explanation

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This solution provides automated management for a known `polkitd` memory leak issue. While tested on Ubuntu servers, test thoroughly in your environment before deployment in production. The maintainers are not responsible for any service disruptions or data loss.

---

**Maintainer**: Akram Faisal  
**Last Updated**: December 2024  
**Tested On**: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS

*For support, open an issue on GitHub or check the troubleshooting section above.*
