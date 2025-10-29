# CRC Clock Synchronization Troubleshooting Guide

This document provides comprehensive guidance for resolving clock synchronization issues in OpenShift Local (CRC) environments, specifically addressing `NodeClockNotSynchronising` alerts.

## Overview

Clock synchronization is critical for OpenShift cluster stability. When the CRC VM's clock drifts out of sync with the host system, it can cause:

- Pod scheduling failures
- Certificate validation errors
- etcd consistency issues
- Build timeouts and failures
- Authentication problems

## Common Symptoms

### NodeClockNotSynchronising Alert

```
NodeClockNotSynchronising
Critical
Clock at crc is not synchronising. Ensure NTP is configured on this host.
```

### Other Indicators

- Build pods stuck in "Pending" status
- Intermittent authentication failures
- Certificate errors in logs
- etcd warnings about clock skew
- Unpredictable pod behavior

## Root Causes

1. **Host System Sleep/Hibernation**: VM clock doesn't catch up after host wakes
2. **chronyd Service Issues**: NTP daemon not running or misconfigured
3. **Network Connectivity**: Unable to reach NTP servers
4. **VM Pausing**: CRC VM was paused/suspended for extended periods
5. **Time Zone Mismatches**: Incorrect time zone configuration

## Quick Fixes

### 1. Immediate Fix - Restart CRC

```bash
# Simplest but takes 5-10 minutes
crc stop
crc start
```

### 2. Fast Fix - Restart chronyd in VM

```bash
# SSH into CRC VM and restart chronyd
ssh -i ~/.crc/machines/crc/id_ecdsa -o StrictHostKeyChecking=no core@$(crc ip) \
  "sudo systemctl restart chronyd && sudo chronyc makestep"
```

### 3. Automated Fix - Use Provided Script

```bash
# Use the dedicated fix script
./scripts/rhos/fix-crc-clock.sh
```

## Detailed Troubleshooting

### Step 1: Check CRC Status

```bash
crc status
```

Expected output for running cluster:

```
CRC VM:          Running
OpenShift:       Running (v4.x.x)
Disk Usage:      XXGiB of XXGiB (Inside the CRC VM)
Cache Usage:     XXGiB
Cache Directory: /Users/username/.crc/cache
```

### Step 2: Check for Clock Alerts

```bash
oc get events --all-namespaces --field-selector reason=NodeClockNotSynchronising
```

If you see events, clock synchronization is problematic.

### Step 3: SSH into CRC VM

```bash
# Get CRC VM IP
CRC_IP=$(crc ip)

# SSH into VM
ssh -i ~/.crc/machines/crc/id_ecdsa -o StrictHostKeyChecking=no core@$CRC_IP
```

### Step 4: Check chronyd Status in VM

```bash
# Check if chronyd is running
sudo systemctl status chronyd

# Check time synchronization status
sudo chronyc tracking

# Check NTP sources
sudo chronyc sources -v

# Check system time vs hardware clock
timedatectl status
```

### Step 5: Fix chronyd Issues

```bash
# Restart chronyd service
sudo systemctl restart chronyd

# Force immediate time sync
sudo chronyc makestep

# Bring sources online
sudo chronyc online

# Wait a moment, then check tracking again
sleep 10
sudo chronyc tracking
```

## Advanced Troubleshooting

### Check chronyd Logs

```bash
# View recent chronyd logs
sudo journalctl -u chronyd --since "1 hour ago"

# Follow chronyd logs in real-time
sudo journalctl -u chronyd -f
```

### Manual Time Sync

```bash
# If chronyd isn't working, try manual sync
sudo systemctl stop chronyd
sudo ntpdate -s time.nist.gov
sudo systemctl start chronyd
```

### Check Network Connectivity

```bash
# Test connectivity to NTP servers
ping -c 3 time.nist.gov
ping -c 3 pool.ntp.org

# Check if VM can resolve DNS
nslookup pool.ntp.org
```

### chronyd Configuration

```bash
# View chronyd configuration
cat /etc/chrony.conf

# Check allowed NTP servers
sudo chronyc sources
```

## Prevention Strategies

### 1. Host System NTP

Ensure your host system has proper NTP configuration:

**macOS:**

```bash
sudo sntp -sS time.apple.com
```

**Linux:**

```bash
sudo ntpdate -s time.nist.gov
# or
sudo chrony sources
```

### 2. Avoid System Sleep

- Don't let your laptop sleep while CRC is running
- Use caffeinate on macOS: `caffeinate -i`
- Configure power settings to prevent sleep

### 3. Regular CRC Restarts

- Restart CRC periodically: `crc stop && crc start`
- Especially after host system sleep/hibernation

### 4. Automated Clock Fix Service

The provided fix script can install an automatic clock sync service:

```bash
./scripts/rhos/fix-crc-clock.sh --enable-auto-sync
```

## Using the Automated Fix Script

### Basic Usage

```bash
# Interactive mode - will prompt for actions
./scripts/rhos/fix-crc-clock.sh

# Automatic mode - minimal prompts
./scripts/rhos/fix-crc-clock.sh --auto

# Install auto-sync service in CRC VM
./scripts/rhos/fix-crc-clock.sh --enable-auto-sync
```

### Script Features

- Detects CRC status and connectivity
- Checks current clock synchronization
- Restarts chronyd service
- Forces time synchronization
- Verifies the fix worked
- Can install auto-sync service
- Provides detailed logging

## Integration with Setup Scripts

The setup scripts now include automatic clock checking:

### start-openshift.sh

- Checks for clock issues when connecting to cluster
- Offers to run automatic fix
- Warns about potential issues

### setup.sh

- Includes clock sync check as Phase 2
- Will halt setup if clock issues detected
- Offers automatic fix before proceeding

## Monitoring Clock Health

### Manual Checks

```bash
# Check for clock alerts
oc get events --all-namespaces --field-selector reason=NodeClockNotSynchronising

# Check node status
oc get nodes

# Check time in CRC VM
ssh -i ~/.crc/machines/crc/id_ecdsa -o StrictHostKeyChecking=no core@$(crc ip) date

# Compare with host time
date
```

### Continuous Monitoring

Add to your shell profile for regular checks:

```bash
# Add to ~/.bashrc or ~/.zshrc
alias crc-clock-check='oc get events --all-namespaces --field-selector reason=NodeClockNotSynchronising'
```

## Troubleshooting Specific Scenarios

### After System Sleep/Hibernation

1. Check if CRC is still running: `crc status`
2. If running, fix clock: `./scripts/rhos/fix-crc-clock.sh --auto`
3. If stopped, restart: `crc start`

### After Time Zone Changes

1. Restart CRC completely: `crc stop && crc start`
2. Verify time zone in VM matches host
3. Run clock fix if needed

### During CI/CD or Automated Testing

1. Always check clock sync before deploying
2. Use automated fix script in scripts
3. Consider CRC restart for critical deployments

## Error Messages and Solutions

### "Cannot connect to CRC VM"

- Check if CRC is running: `crc status`
- Verify SSH key exists: `~/.crc/machines/crc/id_ecdsa`
- Try CRC restart: `crc stop && crc start`

### "chronyd service not active"

```bash
ssh -i ~/.crc/machines/crc/id_ecdsa -o StrictHostKeyChecking=no core@$(crc ip) \
  "sudo systemctl enable chronyd && sudo systemctl start chronyd"
```

### "No servers reachable"

- Check network connectivity in VM
- Verify firewall settings
- Try different NTP servers

### "Permission denied" SSH errors

- Check SSH key permissions: `chmod 600 ~/.crc/machines/crc/id_ecdsa`
- Verify CRC VM IP: `crc ip`

## Best Practices

1. **Regular Maintenance**: Restart CRC weekly
2. **Monitor Alerts**: Check for clock issues before important work
3. **Host System Care**: Keep host NTP properly configured
4. **Avoid Disruption**: Don't pause/sleep during CRC operations
5. **Quick Response**: Fix clock issues immediately when detected
6. **Documentation**: Log clock-related issues for patterns

## Related Resources

- [OpenShift Local Documentation](https://developers.redhat.com/products/openshift-local/overview)
- [chronyd Configuration Guide](https://chrony.tuxfamily.org/doc/4.0/chrony.conf.html)
- [NTP Pool Project](https://www.pool.ntp.org/)
- [OpenShift Time Synchronization](https://docs.openshift.com/container-platform/latest/installing/install_config/configuring-firewall.html#configuring-firewall_configuring-firewall)

## Support and Troubleshooting

If clock synchronization issues persist:

1. Check CRC logs: `crc logs`
2. Review system logs on host
3. Consider CRC version updates
4. Check for known issues in CRC project
5. Verify hardware clock on host system

For additional help, consult the OpenShift Local community or Red Hat support documentation.
