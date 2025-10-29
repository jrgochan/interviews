#!/bin/bash
# Fix CRC (OpenShift Local) clock synchronization issues
# Addresses NodeClockNotSynchronising alerts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log() {
    echo -e "${BLUE}$(date '+%H:%M:%S')${NC} - $*"
}

error() {
    echo -e "${RED}$(date '+%H:%M:%S') ERROR${NC} - $*" >&2
}

success() {
    echo -e "${GREEN}$(date '+%H:%M:%S') SUCCESS${NC} - $*"
}

warn() {
    echo -e "${YELLOW}$(date '+%H:%M:%S') WARNING${NC} - $*"
}

info() {
    echo -e "${CYAN}$(date '+%H:%M:%S') INFO${NC} - $*"
}

# Function to check if CRC is available
check_crc_available() {
    if ! command -v crc &> /dev/null; then
        error "CRC (CodeReady Containers) not found in PATH"
        echo "Please install OpenShift Local from: https://developers.redhat.com/products/openshift-local/overview"
        exit 1
    fi
}

# Function to check CRC status
check_crc_status() {
    log "Checking CRC cluster status..."
    
    local crc_status=$(crc status 2>/dev/null | grep "CRC VM:" | awk '{print $3}' || echo "Unknown")
    
    case "$crc_status" in
        "Running")
            success "CRC cluster is running"
            return 0
            ;;
        "Stopped")
            warn "CRC cluster is stopped"
            return 1
            ;;
        "Starting")
            warn "CRC cluster is starting - please wait for it to complete"
            return 1
            ;;
        *)
            warn "CRC cluster status unknown: $crc_status"
            return 1
            ;;
    esac
}

# Function to get CRC VM IP
get_crc_ip() {
    local crc_ip=$(crc ip 2>/dev/null || echo "")
    
    if [ -z "$crc_ip" ]; then
        error "Cannot determine CRC VM IP address"
        warn "This may indicate CRC is not fully started"
        return 1
    fi
    
    # Check if IP looks valid (not localhost)
    if [ "$crc_ip" = "127.0.0.1" ] || [ "$crc_ip" = "localhost" ]; then
        warn "CRC returned localhost IP ($crc_ip) - this may indicate networking issues"
        warn "CRC may not be fully initialized"
    fi
    
    echo "$crc_ip"
}

# Function to find SSH key for CRC
find_crc_ssh_key() {
    local ssh_key=""
    
    # Common SSH key paths for different CRC versions
    local key_paths=(
        "$HOME/.crc/machines/crc/id_ecdsa"
        "$HOME/.crc/machines/crc/id_rsa"
        "$HOME/.crc/cache/crc_libvirt_4.11.0/id_ecdsa"
        "$HOME/.crc/cache/crc_libvirt_4.12.0/id_ecdsa"
        "$HOME/.crc/cache/crc_libvirt_4.13.0/id_ecdsa"
        "$HOME/.crc/cache/crc_libvirt_4.14.0/id_ecdsa"
    )
    
    # Try to find existing SSH key
    for path in "${key_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    # Try to find any SSH key in .crc directory
    local found_key=$(find "$HOME/.crc" -name "id_*" -type f 2>/dev/null | head -1)
    if [ -n "$found_key" ]; then
        echo "$found_key"
        return 0
    fi
    
    return 1
}

# Function to test SSH connectivity to CRC VM
test_crc_ssh() {
    local crc_ip="$1"
    local ssh_key="$2"
    
    # Test SSH connection
    if ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -o PasswordAuthentication=no -o BatchMode=yes \
        "core@$crc_ip" "echo 'SSH test successful'" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check current clock status in CRC VM
check_vm_clock_status() {
    local crc_ip="$1"
    
    log "Checking clock synchronization status in CRC VM..."
    
    # Find SSH key
    local ssh_key
    if ! ssh_key=$(find_crc_ssh_key); then
        error "No CRC SSH key found in expected locations"
        info "Searched paths:"
        info "  - $HOME/.crc/machines/crc/id_ecdsa"
        info "  - $HOME/.crc/machines/crc/id_rsa"
        info "  - $HOME/.crc/cache/*/id_ecdsa"
        warn "SSH keys may need to be regenerated"
        
        # Offer SSH management script
        if [ -f "${SCRIPT_DIR}/manage-crc-ssh.sh" ]; then
            echo
            warn "Use the SSH management script to fix SSH access:"
            echo "  ${SCRIPT_DIR}/manage-crc-ssh.sh --status"
            echo "  ${SCRIPT_DIR}/manage-crc-ssh.sh --regenerate-keys"
        fi
        
        return 1
    fi
    
    info "Using SSH key: $ssh_key"
    
    # Test SSH connectivity
    if ! test_crc_ssh "$crc_ip" "$ssh_key"; then
        error "Cannot SSH to CRC VM at $crc_ip using key $ssh_key"
        warn "This could indicate:"
        warn "  1. CRC VM is not fully started"
        warn "  2. SSH service not ready in VM"
        warn "  3. Network connectivity issues"
        warn "  4. Wrong SSH key"
        
        # Offer SSH management script
        if [ -f "${SCRIPT_DIR}/manage-crc-ssh.sh" ]; then
            echo
            warn "Use the SSH management script to diagnose and fix SSH issues:"
            echo "  ${SCRIPT_DIR}/manage-crc-ssh.sh --test"
            echo "  ${SCRIPT_DIR}/manage-crc-ssh.sh --fix-permissions"
            echo "  ${SCRIPT_DIR}/manage-crc-ssh.sh --regenerate-keys"
        fi
        
        return 1
    fi
    
    # Check chronyd status
    local chrony_status=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "core@$crc_ip" "sudo systemctl is-active chronyd" 2>/dev/null || echo "inactive")
    
    info "Chronyd service status: $chrony_status"
    
    # Check time synchronization
    local time_sync=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "core@$crc_ip" "sudo chronyc tracking | grep 'System time'" 2>/dev/null || echo "unknown")
    
    info "Time sync status: $time_sync"
    
    # Check if severely out of sync (more than 1 second)
    local time_offset=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "core@$crc_ip" "sudo chronyc tracking | grep 'System time' | awk '{print \$4}'" 2>/dev/null || echo "0")
    
    if [ -n "$time_offset" ] && [ "${time_offset%.*}" != "0" ]; then
        warn "Clock appears to be out of sync (offset: $time_offset seconds)"
        return 1
    fi
    
    success "Clock appears to be synchronized"
    return 0
}

# Function to fix clock synchronization
fix_clock_sync() {
    local crc_ip="$1"
    
    log "Fixing clock synchronization in CRC VM..."
    
    # Find SSH key
    local ssh_key
    if ! ssh_key=$(find_crc_ssh_key); then
        error "No CRC SSH key found - cannot fix clock synchronization"
        return 1
    fi
    
    # Test SSH connectivity first
    if ! test_crc_ssh "$crc_ip" "$ssh_key"; then
        error "Cannot SSH to CRC VM - cannot fix clock synchronization"
        return 1
    fi
    
    # Restart chronyd service
    info "Restarting chronyd service..."
    if ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "core@$crc_ip" "sudo systemctl restart chronyd" 2>/dev/null; then
        success "Chronyd service restarted"
    else
        error "Failed to restart chronyd service"
        return 1
    fi
    
    # Wait a moment for chronyd to start
    sleep 5
    
    # Force time synchronization
    info "Forcing time synchronization..."
    if ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "core@$crc_ip" "sudo chronyc makestep" 2>/dev/null; then
        success "Forced time synchronization"
    else
        warn "makestep command may have failed, but this is sometimes normal"
    fi
    
    # Wait for sync to complete
    sleep 10
    
    # Force sources online
    info "Bringing NTP sources online..."
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "core@$crc_ip" "sudo chronyc online" 2>/dev/null || true
    
    # Wait for synchronization
    sleep 5
    
    success "Clock synchronization fix attempted"
}

# Function to verify the fix worked
verify_clock_fix() {
    local crc_ip="$1"
    
    log "Verifying clock synchronization fix..."
    
    # Find SSH key
    local ssh_key
    if ! ssh_key=$(find_crc_ssh_key); then
        error "No CRC SSH key found - cannot verify fix"
        return 1
    fi
    
    # Check chronyd status again
    local chrony_status=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "core@$crc_ip" "sudo systemctl is-active chronyd" 2>/dev/null || echo "inactive")
    
    if [ "$chrony_status" != "active" ]; then
        error "Chronyd service is not active: $chrony_status"
        return 1
    fi
    
    # Get detailed sync info
    info "Current synchronization status:"
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "core@$crc_ip" "sudo chronyc tracking" 2>/dev/null || true
    
    # Check sources
    info "NTP sources:"
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "core@$crc_ip" "sudo chronyc sources -v" 2>/dev/null || true
    
    success "Clock fix verification completed"
}

# Function to check OpenShift cluster status
check_openshift_status() {
    log "Checking OpenShift cluster health after clock fix..."
    
    if ! command -v oc &> /dev/null; then
        warn "oc CLI not found, skipping OpenShift status check"
        return 0
    fi
    
    # Test connection
    if oc status &> /dev/null; then
        success "OpenShift cluster is accessible"
        
        # Check for clock-related alerts
        log "Checking for NodeClockNotSynchronising alerts..."
        local clock_alerts=$(oc get events --all-namespaces --field-selector reason=NodeClockNotSynchronising 2>/dev/null | wc -l)
        
        if [ "$clock_alerts" -gt 1 ]; then  # Greater than 1 because header counts as 1
            warn "Clock synchronization alerts still present - may take a few minutes to clear"
        else
            success "No clock synchronization alerts detected"
        fi
        
        # Show node status
        info "Node status:"
        oc get nodes 2>/dev/null || true
        
    else
        warn "OpenShift cluster not accessible - may still be starting up"
    fi
}

# Function to provide troubleshooting information
provide_troubleshooting() {
    echo
    log "Clock Synchronization Troubleshooting Guide"
    echo
    echo -e "${YELLOW}If the issue persists, try these additional steps:${NC}"
    echo
    echo -e "1. ${BLUE}Restart CRC completely:${NC}"
    echo -e "   crc stop && crc start"
    echo
    echo -e "2. ${BLUE}Check host system clock:${NC}"
    echo -e "   date  # Should show correct time"
    echo -e "   sudo sntp -sS time.apple.com  # macOS"
    echo -e "   sudo ntpdate -s time.nist.gov  # Linux"
    echo
    echo -e "3. ${BLUE}Monitor CRC logs:${NC}"
    echo -e "   crc logs"
    echo
    echo -e "4. ${BLUE}If using a laptop, ensure:${NC}"
    echo -e "   - System didn't sleep/hibernate recently"
    echo -e "   - System time zone is correct"
    echo -e "   - NTP is enabled on host system"
    echo
    echo -e "5. ${BLUE}Advanced debugging:${NC}"
    echo -e "   ssh -i ~/.crc/machines/crc/id_ecdsa core@\$(crc ip)"
    echo -e "   sudo chronyc sources -v"
    echo -e "   sudo chronyc tracking"
    echo -e "   sudo journalctl -u chronyd --since '1 hour ago'"
    echo
}

# Function to enable automatic clock sync on CRC startup
enable_auto_clock_sync() {
    local crc_ip="$1"
    
    log "Configuring automatic clock synchronization..."
    
    # Find SSH key
    local ssh_key
    if ! ssh_key=$(find_crc_ssh_key); then
        error "No CRC SSH key found - cannot configure auto-sync"
        return 1
    fi
    
    # Create a script to run on CRC startup
    local sync_script="/tmp/crc-clock-sync.sh"
    cat > "$sync_script" << 'EOF'
#!/bin/bash
# Auto-sync clock on CRC VM startup

sleep 30  # Wait for network
systemctl restart chronyd
sleep 10
chronyc makestep
chronyc online
EOF
    
    # Copy script to CRC VM
    if scp -i "$ssh_key" -o StrictHostKeyChecking=no "$sync_script" "core@$crc_ip:/tmp/crc-clock-sync.sh" 2>/dev/null; then
        ssh -i "$ssh_key" -o StrictHostKeyChecking=no "core@$crc_ip" \
            "sudo cp /tmp/crc-clock-sync.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/crc-clock-sync.sh" 2>/dev/null
        
        # Create systemd service for auto-sync
        ssh -i "$ssh_key" -o StrictHostKeyChecking=no "core@$crc_ip" \
            'sudo tee /etc/systemd/system/crc-clock-sync.service > /dev/null << EOF
[Unit]
Description=CRC Clock Sync on Boot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/crc-clock-sync.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF' 2>/dev/null
        
        ssh -i "$ssh_key" -o StrictHostKeyChecking=no "core@$crc_ip" \
            "sudo systemctl enable crc-clock-sync.service" 2>/dev/null
        
        success "Auto-sync service installed"
    else
        warn "Could not install auto-sync service"
    fi
    
    rm -f "$sync_script"
}

# Main execution function
main() {
    local auto_mode=false
    local enable_auto=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                auto_mode=true
                shift
                ;;
            --enable-auto-sync)
                enable_auto=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Fix CRC (OpenShift Local) clock synchronization issues"
                echo ""
                echo "Options:"
                echo "  --auto                Run in automatic mode (less prompts)"
                echo "  --enable-auto-sync    Install auto-sync service in CRC VM"
                echo "  --help, -h           Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    log "Starting CRC Clock Synchronization Fix"
    echo
    
    # Step 1: Check if CRC is available
    check_crc_available
    
    # Step 2: Check CRC status
    if ! check_crc_status; then
        if [ "$auto_mode" = "false" ]; then
            read -p "CRC is not running. Start it now? [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log "Starting CRC..."
                crc start
            else
                error "CRC must be running to fix clock synchronization"
                exit 1
            fi
        else
            error "CRC is not running. Please start it first with: crc start"
            exit 1
        fi
    fi
    
    # Step 3: Get CRC VM IP
    local crc_ip
    if ! crc_ip=$(get_crc_ip); then
        exit 1
    fi
    
    info "CRC VM IP: $crc_ip"
    
    # Step 4: Check current clock status
    local needs_fix=false
    if ! check_vm_clock_status "$crc_ip"; then
        needs_fix=true
    fi
    
    # Step 5: Fix clock if needed or if forced
    if [ "$needs_fix" = "true" ] || [ "$auto_mode" = "false" ]; then
        if [ "$auto_mode" = "false" ] && [ "$needs_fix" = "false" ]; then
            read -p "Clock appears synchronized. Force fix anyway? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                success "No clock fix needed"
                exit 0
            fi
        fi
        
        if ! fix_clock_sync "$crc_ip"; then
            error "Failed to fix clock synchronization via SSH"
            
            # Offer fallback solutions
            echo
            warn "SSH-based fix failed. Alternative solutions:"
            echo -e "  ${BLUE}1. Fix SSH access first:${NC}"
            if [ -f "${SCRIPT_DIR}/manage-crc-ssh.sh" ]; then
                echo -e "     ${SCRIPT_DIR}/manage-crc-ssh.sh --test"
                echo -e "     ${SCRIPT_DIR}/manage-crc-ssh.sh --regenerate-keys"
            else
                echo -e "     Check SSH keys and permissions"
            fi
            echo
            echo -e "  ${BLUE}2. Restart CRC (most reliable):${NC}"
            echo -e "     crc stop && crc start"
            echo
            echo -e "  ${BLUE}3. Check if CRC is fully started:${NC}"
            echo -e "     crc status"
            echo
            echo -e "  ${BLUE}4. Check CRC logs for issues:${NC}"
            echo -e "     crc logs"
            echo
            
            if [ "$auto_mode" = "false" ]; then
                read -p "Would you like to restart CRC now? This is the most reliable fix. [Y/n]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    log "Restarting CRC to fix clock synchronization..."
                    crc stop
                    echo "Waiting for CRC to stop..."
                    sleep 10
                    crc start
                    success "CRC restart completed - clock should now be synchronized"
                    
                    # Verify after restart
                    check_openshift_status
                    return 0
                else
                    warn "Skipping CRC restart - clock issues may persist"
                fi
            fi
            
            exit 1
        fi
        
        # Step 6: Verify the fix
        verify_clock_fix "$crc_ip"
    fi
    
    # Step 7: Enable auto-sync if requested
    if [ "$enable_auto" = "true" ]; then
        enable_auto_clock_sync "$crc_ip"
    fi
    
    # Step 8: Check OpenShift status
    check_openshift_status
    
    # Step 9: Provide troubleshooting info
    if [ "$auto_mode" = "false" ]; then
        provide_troubleshooting
    fi
    
    echo
    success "CRC clock synchronization fix completed!"
    info "Monitor alerts with: oc get events --all-namespaces --field-selector reason=NodeClockNotSynchronising"
    info "For persistent issues, restart CRC: crc stop && crc start"
}

# Run main function with all arguments
main "$@"
