#!/bin/bash
# CRC SSH Access Management Script
# Creates, manages, and troubleshoots SSH access to OpenShift Local (CRC) VM

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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

highlight() {
    echo -e "${BOLD}$*${NC}"
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
            error "CRC cluster is stopped"
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
        return 1
    fi
    
    echo "$crc_ip"
}

# Function to find existing SSH keys for CRC
find_crc_ssh_keys() {
    local found_keys=()
    
    # Common SSH key paths for different CRC versions and configurations
    local key_paths=(
        "$HOME/.crc/machines/crc/id_ecdsa"
        "$HOME/.crc/machines/crc/id_rsa" 
        "$HOME/.crc/machines/crc/id_ed25519"
        "$HOME/.crc/cache/crc_libvirt_4.11.0/id_ecdsa"
        "$HOME/.crc/cache/crc_libvirt_4.12.0/id_ecdsa"
        "$HOME/.crc/cache/crc_libvirt_4.13.0/id_ecdsa"
        "$HOME/.crc/cache/crc_libvirt_4.14.0/id_ecdsa"
        "$HOME/.crc/cache/crc_libvirt_4.15.0/id_ecdsa"
        "$HOME/.crc/cache/crc_hyperkit_4.11.0/id_ecdsa"
        "$HOME/.crc/cache/crc_hyperkit_4.12.0/id_ecdsa"
        "$HOME/.crc/cache/crc_hyperkit_4.13.0/id_ecdsa"
        "$HOME/.crc/cache/crc_hyperkit_4.14.0/id_ecdsa"
        "$HOME/.crc/cache/crc_hyperkit_4.15.0/id_ecdsa"
    )
    
    # Check common paths first
    for path in "${key_paths[@]}"; do
        if [ -f "$path" ]; then
            found_keys+=("$path")
        fi
    done
    
    # Comprehensive search in .crc directory
    if [ -d "$HOME/.crc" ]; then
        while IFS= read -r -d '' key; do
            # Avoid duplicates
            local duplicate=false
            for existing in "${found_keys[@]}"; do
                if [ "$existing" = "$key" ]; then
                    duplicate=true
                    break
                fi
            done
            if [ "$duplicate" = false ]; then
                found_keys+=("$key")
            fi
        done < <(find "$HOME/.crc" -name "id_*" -type f ! -name "*.pub" -print0 2>/dev/null)
    fi
    
    # Return found keys
    for key in "${found_keys[@]}"; do
        echo "$key"
    done
}

# Function to test SSH connectivity
test_ssh_connection() {
    local crc_ip="$1"
    local ssh_key="$2"
    local timeout="${3:-5}"
    
    if ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        -o ConnectTimeout="$timeout" \
        -o ServerAliveInterval=5 \
        -o ServerAliveCountMax=1 \
        "core@$crc_ip" "echo 'SSH connection successful'" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to display current SSH status
show_ssh_status() {
    log "Current SSH Configuration Status"
    echo
    
    # Check CRC status
    local crc_running=false
    if check_crc_status; then
        crc_running=true
        local crc_ip
        if crc_ip=$(get_crc_ip); then
            info "CRC VM IP: $crc_ip"
        else
            warn "Could not determine CRC IP"
            return 1
        fi
    else
        warn "CRC is not running - cannot test SSH connectivity"
        return 0
    fi
    
    # Find SSH keys
    local keys=($(find_crc_ssh_keys))
    
    if [ ${#keys[@]} -eq 0 ]; then
        warn "No SSH keys found for CRC"
        info "SSH keys may need to be regenerated"
        return 1
    fi
    
    info "Found ${#keys[@]} SSH key(s):"
    
    local working_keys=()
    local broken_keys=()
    
    for key in "${keys[@]}"; do
        echo -e "  ${CYAN}Key:${NC} $key"
        
        # Check key file permissions
        local perms=$(stat -f "%OLp" "$key" 2>/dev/null || stat -c "%a" "$key" 2>/dev/null || echo "unknown")
        if [ "$perms" != "600" ] && [ "$perms" != "unknown" ]; then
            warn "    Permissions: $perms (should be 600)"
        else
            info "    Permissions: $perms ✓"
        fi
        
        # Test connectivity if CRC is running
        if [ "$crc_running" = true ]; then
            if test_ssh_connection "$crc_ip" "$key"; then
                success "    Connectivity: Working ✓"
                working_keys+=("$key")
            else
                error "    Connectivity: Failed ✗"
                broken_keys+=("$key")
            fi
        fi
        echo
    done
    
    # Summary
    if [ "$crc_running" = true ]; then
        if [ ${#working_keys[@]} -gt 0 ]; then
            success "SSH access is working with ${#working_keys[@]} key(s)"
            export CRC_WORKING_SSH_KEY="${working_keys[0]}"
        else
            error "No working SSH keys found"
            return 1
        fi
    fi
    
    return 0
}

# Function to fix SSH key permissions
fix_ssh_permissions() {
    log "Fixing SSH key permissions..."
    
    local keys=($(find_crc_ssh_keys))
    local fixed=0
    
    for key in "${keys[@]}"; do
        local current_perms=$(stat -f "%OLp" "$key" 2>/dev/null || stat -c "%a" "$key" 2>/dev/null || echo "unknown")
        
        if [ "$current_perms" != "600" ]; then
            info "Fixing permissions for: $key ($current_perms -> 600)"
            chmod 600 "$key"
            fixed=$((fixed + 1))
        fi
        
        # Also fix .pub file if it exists
        if [ -f "${key}.pub" ]; then
            local pub_perms=$(stat -f "%OLp" "${key}.pub" 2>/dev/null || stat -c "%a" "${key}.pub" 2>/dev/null || echo "unknown")
            if [ "$pub_perms" != "644" ]; then
                info "Fixing permissions for: ${key}.pub ($pub_perms -> 644)"
                chmod 644 "${key}.pub"
                fixed=$((fixed + 1))
            fi
        fi
    done
    
    if [ $fixed -gt 0 ]; then
        success "Fixed permissions for $fixed file(s)"
    else
        info "All SSH key permissions are correct"
    fi
}

# Function to create SSH config entry
create_ssh_config() {
    local crc_ip="$1"
    local ssh_key="$2"
    
    log "Creating SSH config entry..."
    
    local ssh_config="$HOME/.ssh/config"
    local config_dir="$HOME/.ssh"
    
    # Create .ssh directory if it doesn't exist
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
        chmod 700 "$config_dir"
        info "Created ~/.ssh directory"
    fi
    
    # Check if CRC entry already exists
    if [ -f "$ssh_config" ] && grep -q "Host crc" "$ssh_config"; then
        warn "CRC SSH config entry already exists"
        info "Backing up current config..."
        cp "$ssh_config" "${ssh_config}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove existing CRC entry
        sed -i '' '/^Host crc$/,/^$/d' "$ssh_config" 2>/dev/null || \
        sed -i '/^Host crc$/,/^$/d' "$ssh_config" 2>/dev/null
    fi
    
    # Add new CRC entry
    cat >> "$ssh_config" << EOF

# CRC (OpenShift Local) SSH Configuration - Generated by manage-crc-ssh.sh
Host crc
    HostName $crc_ip
    User core
    IdentityFile $ssh_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    ServerAliveInterval 30
    ServerAliveCountMax 3

EOF
    
    chmod 600 "$ssh_config"
    success "Created SSH config entry for CRC"
    info "You can now connect with: ssh crc"
}

# Function to regenerate SSH keys (if needed)
regenerate_ssh_keys() {
    warn "This will restart CRC to regenerate SSH keys"
    echo "This process will:"
    echo "  1. Stop CRC"
    echo "  2. Clean up old SSH keys"
    echo "  3. Start CRC (regenerates keys)"
    echo "  4. Test new connection"
    echo
    
    read -p "Continue? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "SSH key regeneration cancelled"
        return 0
    fi
    
    log "Stopping CRC..."
    crc stop
    
    log "Cleaning up old SSH keys..."
    find "$HOME/.crc" -name "id_*" -type f -delete 2>/dev/null || true
    
    log "Starting CRC (this will regenerate SSH keys)..."
    crc start
    
    log "Testing new SSH connection..."
    local crc_ip
    if crc_ip=$(get_crc_ip); then
        local keys=($(find_crc_ssh_keys))
        if [ ${#keys[@]} -gt 0 ] && test_ssh_connection "$crc_ip" "${keys[0]}"; then
            success "SSH keys successfully regenerated and working!"
            create_ssh_config "$crc_ip" "${keys[0]}"
        else
            error "SSH key regeneration failed"
            return 1
        fi
    else
        error "Could not get CRC IP after restart"
        return 1
    fi
}

# Function to test and troubleshoot connection
test_connection() {
    log "Testing SSH connection to CRC..."
    
    if ! check_crc_status; then
        error "CRC is not running - cannot test SSH"
        return 1
    fi
    
    local crc_ip
    if ! crc_ip=$(get_crc_ip); then
        error "Could not determine CRC IP"
        return 1
    fi
    
    local keys=($(find_crc_ssh_keys))
    
    if [ ${#keys[@]} -eq 0 ]; then
        error "No SSH keys found"
        echo "Try: $0 --regenerate-keys"
        return 1
    fi
    
    info "Testing connection to $crc_ip..."
    
    local working_key=""
    for key in "${keys[@]}"; do
        info "Testing key: $key"
        if test_ssh_connection "$crc_ip" "$key" 10; then
            success "✓ Connection successful with: $key"
            working_key="$key"
            break
        else
            warn "✗ Connection failed with: $key"
        fi
    done
    
    if [ -n "$working_key" ]; then
        success "SSH connection is working!"
        
        # Offer to create SSH config
        if [ ! -f "$HOME/.ssh/config" ] || ! grep -q "Host crc" "$HOME/.ssh/config" 2>/dev/null; then
            echo
            read -p "Create SSH config entry for easy access? [Y/n]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                create_ssh_config "$crc_ip" "$working_key"
            fi
        fi
        
        echo
        highlight "Connect to CRC VM with:"
        if grep -q "Host crc" "$HOME/.ssh/config" 2>/dev/null; then
            echo "  ssh crc"
        else
            echo "  ssh -i $working_key core@$crc_ip"
        fi
        
    else
        error "All SSH connections failed"
        echo
        echo "Troubleshooting suggestions:"
        echo "  1. Check CRC logs: crc logs"
        echo "  2. Restart CRC: crc stop && crc start"
        echo "  3. Regenerate keys: $0 --regenerate-keys"
        return 1
    fi
}

# Function to create convenient SSH wrapper
create_ssh_wrapper() {
    local wrapper_script="$SCRIPT_DIR/crc-ssh.sh"
    
    log "Creating SSH wrapper script..."
    
    local crc_ip
    if ! crc_ip=$(get_crc_ip); then
        error "Could not determine CRC IP"
        return 1
    fi
    
    local keys=($(find_crc_ssh_keys))
    if [ ${#keys[@]} -eq 0 ]; then
        error "No SSH keys found"
        return 1
    fi
    
    local working_key=""
    for key in "${keys[@]}"; do
        if test_ssh_connection "$crc_ip" "$key"; then
            working_key="$key"
            break
        fi
    done
    
    if [ -z "$working_key" ]; then
        error "No working SSH key found"
        return 1
    fi
    
    cat > "$wrapper_script" << EOF
#!/bin/bash
# CRC SSH Wrapper Script - Auto-generated by manage-crc-ssh.sh
# Provides easy SSH access to CRC VM

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Get current CRC IP
CRC_IP=\$(crc ip 2>/dev/null || echo "")

if [ -z "\$CRC_IP" ]; then
    echo -e "\${RED}Error: Could not determine CRC IP. Is CRC running?\${NC}"
    echo "Check with: crc status"
    exit 1
fi

# SSH key to use
SSH_KEY="$working_key"

if [ ! -f "\$SSH_KEY" ]; then
    echo -e "\${RED}Error: SSH key not found: \$SSH_KEY\${NC}"
    echo "Regenerate with: \$(dirname "\$0")/manage-crc-ssh.sh --regenerate-keys"
    exit 1
fi

echo -e "\${BLUE}Connecting to CRC VM at \$CRC_IP...\${NC}"

# Connect to CRC VM
ssh -i "\$SSH_KEY" \\
    -o StrictHostKeyChecking=no \\
    -o UserKnownHostsFile=/dev/null \\
    -o LogLevel=ERROR \\
    -o ServerAliveInterval=30 \\
    -o ServerAliveCountMax=3 \\
    "core@\$CRC_IP" "\$@"
EOF
    
    chmod +x "$wrapper_script"
    success "Created SSH wrapper: $wrapper_script"
    
    echo
    highlight "Quick SSH access commands:"
    echo "  $wrapper_script                    # Interactive shell"
    echo "  $wrapper_script 'sudo systemctl status chronyd'  # Run command"
    echo "  $wrapper_script -L 8080:localhost:8080           # Port forwarding"
}

# Function to display comprehensive help
show_help() {
    echo "CRC SSH Access Management Script"
    echo "Manages SSH connectivity to OpenShift Local (CRC) VM"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --status              Show current SSH status and test connectivity"
    echo "  --test                Test SSH connection to CRC VM"
    echo "  --fix-permissions     Fix SSH key file permissions"
    echo "  --create-config       Create SSH config entry for CRC"
    echo "  --create-wrapper      Create convenient SSH wrapper script"
    echo "  --regenerate-keys     Restart CRC to regenerate SSH keys"
    echo "  --find-keys           Find and list all CRC SSH keys"
    echo "  --help, -h           Show this help message"
    echo
    echo "Examples:"
    echo "  $0                    # Show status and interactive menu"
    echo "  $0 --test            # Quick connection test"
    echo "  $0 --create-wrapper  # Create easy SSH access script"
    echo "  $0 --regenerate-keys # Fix broken SSH by restarting CRC"
    echo
    echo "Generated Files:"
    echo "  ~/.ssh/config        # SSH config entry (Host crc)"
    echo "  $SCRIPT_DIR/crc-ssh.sh  # SSH wrapper script"
    echo
}

# Function to show interactive menu
show_interactive_menu() {
    echo
    highlight "CRC SSH Management - Interactive Menu"
    echo
    echo "1. Show SSH Status"
    echo "2. Test SSH Connection"
    echo "3. Fix SSH Key Permissions"
    echo "4. Create SSH Config Entry"
    echo "5. Create SSH Wrapper Script"
    echo "6. Regenerate SSH Keys (restart CRC)"
    echo "7. Find All SSH Keys"
    echo "8. Help"
    echo "9. Exit"
    echo
    
    while true; do
        read -p "Select option [1-9]: " -n 1 -r
        echo
        
        case $REPLY in
            1) show_ssh_status; break ;;
            2) test_connection; break ;;
            3) fix_ssh_permissions; break ;;
            4) 
                if check_crc_status; then
                    local crc_ip
                    if crc_ip=$(get_crc_ip); then
                        local keys=($(find_crc_ssh_keys))
                        if [ ${#keys[@]} -gt 0 ]; then
                            create_ssh_config "$crc_ip" "${keys[0]}"
                        else
                            error "No SSH keys found"
                        fi
                    fi
                fi
                break ;;
            5) create_ssh_wrapper; break ;;
            6) regenerate_ssh_keys; break ;;
            7) 
                local keys=($(find_crc_ssh_keys))
                if [ ${#keys[@]} -gt 0 ]; then
                    info "Found SSH keys:"
                    for key in "${keys[@]}"; do
                        echo "  $key"
                    done
                else
                    warn "No SSH keys found"
                fi
                break ;;
            8) show_help; break ;;
            9) exit 0 ;;
            *) echo "Invalid option. Please select 1-9." ;;
        esac
    done
}

# Main execution function
main() {
    # Check if CRC is available
    check_crc_available
    
    # Parse command line arguments
    case "${1:-}" in
        --status)
            show_ssh_status
            ;;
        --test)
            test_connection
            ;;
        --fix-permissions)
            fix_ssh_permissions
            ;;
        --create-config)
            if check_crc_status; then
                local crc_ip
                if crc_ip=$(get_crc_ip); then
                    local keys=($(find_crc_ssh_keys))
                    if [ ${#keys[@]} -gt 0 ]; then
                        create_ssh_config "$crc_ip" "${keys[0]}"
                    else
                        error "No SSH keys found"
                        exit 1
                    fi
                fi
            fi
            ;;
        --create-wrapper)
            create_ssh_wrapper
            ;;
        --regenerate-keys)
            regenerate_ssh_keys
            ;;
        --find-keys)
            local keys=($(find_crc_ssh_keys))
            if [ ${#keys[@]} -gt 0 ]; then
                success "Found ${#keys[@]} SSH key(s):"
                for key in "${keys[@]}"; do
                    echo "  $key"
                done
            else
                warn "No SSH keys found"
                exit 1
            fi
            ;;
        --help|-h)
            show_help
            ;;
        "")
            # Interactive mode
            log "CRC SSH Access Management"
            echo
            
            # Show basic status first
            show_ssh_status
            
            # Show interactive menu
            show_interactive_menu
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
