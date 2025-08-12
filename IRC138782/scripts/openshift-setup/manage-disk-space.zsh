#!/usr/bin/env zsh
set -euo pipefail

# =========================
# OpenShift Local Disk Space Management Script
# =========================
# This script helps manage disk space on OpenShift Local (CRC) by:
# - Checking current disk usage and available space
# - Expanding the underlying storage in 10Gi increments
# - Managing CRC VM disk allocation
# - Monitoring storage classes and PVC usage
# - Providing recommendations for space optimization
#
# Prerequisites:
# - OpenShift Local (CRC) installed and running
# - OpenShift CLI (oc) installed and configured
# - Sufficient host disk space for expansion
# - Admin access to the CRC environment
#
# Usage:
#   ./manage-disk-space.zsh [options]
#
# =========================

# =========================
# Helpers & Defaults
# =========================
info() { print -P "%F{cyan}==>%f $*"; }
ok()   { print -P "%F{green}✔%f $*"; }
warn() { print -P "%F{yellow}WARNING:%f $*"; }
err()  { print -P "%F{red}ERROR:%f $*" >&2; }

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing '$1'. Please install it and re-run."
    case "$1" in
      crc) print "  macOS: brew install crc" ;;
      oc) print "  macOS: brew install openshift-cli" ;;
    esac
    exit 1
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Convert bytes to human readable format
bytes_to_human() {
  local bytes=$1
  local units=("B" "KB" "MB" "GB" "TB")
  local unit=0
  local size=$bytes
  
  while [[ $size -gt 1024 && $unit -lt 4 ]]; do
    size=$((size / 1024))
    unit=$((unit + 1))
  done
  
  echo "${size}${units[$unit]}"
}

# Convert human readable to bytes
human_to_bytes() {
  local input=$1
  local number=$(echo "$input" | sed 's/[^0-9.]//g')
  local unit=$(echo "$input" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
  
  case "$unit" in
    ""|"B") echo "$number" ;;
    "K"|"KB") echo $((${number%.*} * 1024)) ;;
    "M"|"MB") echo $((${number%.*} * 1024 * 1024)) ;;
    "G"|"GB") echo $((${number%.*} * 1024 * 1024 * 1024)) ;;
    "T"|"TB") echo $((${number%.*} * 1024 * 1024 * 1024 * 1024)) ;;
    *) echo "$number" ;;
  esac
}

# Defaults
: "${EXPAND_SIZE:=10Gi}"
: "${DRY_RUN:=false}"
: "${AUTO_EXPAND:=false}"
: "${CHECK_ONLY:=false}"

usage() {
  cat <<'EOF'
Usage: ./manage-disk-space.zsh [options]

Options:
  --check-only        Only check current disk usage, don't expand
  --expand [SIZE]     Expand disk by specified size (default: 10Gi)
  --auto-expand       Automatically expand if disk pressure detected
  --dry-run           Show what would be done without making changes
  -h, --help          Show this help

Environment Variables:
  EXPAND_SIZE=20Gi    Set default expansion size
  DRY_RUN=true        Enable dry run mode
  AUTO_EXPAND=true    Enable automatic expansion
  CHECK_ONLY=true     Only perform checks

Examples:
  # Check current disk usage
  ./manage-disk-space.zsh --check-only

  # Expand disk by 10Gi (default)
  ./manage-disk-space.zsh --expand

  # Expand disk by custom size
  ./manage-disk-space.zsh --expand 20Gi

  # Auto-expand if disk pressure detected
  ./manage-disk-space.zsh --auto-expand

  # Dry run to see what would be done
  ./manage-disk-space.zsh --expand --dry-run
EOF
}

# =========================
# Parse arguments
# =========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) CHECK_ONLY=true; shift;;
    --expand) 
      if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
        EXPAND_SIZE="$2"
        shift 2
      else
        shift
      fi
      ;;
    --auto-expand) AUTO_EXPAND=true; shift;;
    --dry-run) DRY_RUN=true; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

# =========================
# Preflight checks
# =========================
info "OpenShift Local Disk Space Management Tool"
info "==========================================="

need crc
need oc

# Check if CRC is running
if ! crc status 2>/dev/null | grep -q "OpenShift: .*Running"; then
  err "OpenShift Local (CRC) is not running. Please start it with 'crc start'"
  exit 1
fi

# Check if we're logged in
if ! oc whoami >/dev/null 2>&1; then
  warn "Not logged into OpenShift. Attempting to configure..."
  if crc oc-env >/dev/null 2>&1; then
    eval "$(crc oc-env)"
  else
    err "Could not configure OpenShift CLI. Please run 'oc login' manually."
    exit 1
  fi
fi

CLUSTER_URL=$(oc whoami --show-server)
CURRENT_USER=$(oc whoami)
ok "Connected to: $CLUSTER_URL as $CURRENT_USER"

if [[ "$DRY_RUN" == "true" ]]; then
  warn "DRY RUN MODE - No changes will be made"
fi

# =========================
# Disk usage analysis functions
# =========================

check_host_disk_space() {
  info "Checking host system disk space..."
  
  # Get CRC machine info
  local crc_machine_dir="$HOME/.crc/machines/crc"
  if [[ -d "$crc_machine_dir" ]]; then
    info "CRC machine directory: $crc_machine_dir"
    du -sh "$crc_machine_dir" 2>/dev/null || warn "Could not check CRC machine disk usage"
  fi
  
  # Check available space on host
  local host_available
  host_available=$(df -h "$HOME" | awk 'NR==2 {print $4}')
  info "Available space on host: $host_available"
  
  # Check CRC VM disk file
  local vm_disk_file="$crc_machine_dir/crc.qcow2"
  if [[ -f "$vm_disk_file" ]]; then
    local vm_disk_size
    vm_disk_size=$(ls -lh "$vm_disk_file" | awk '{print $5}')
    info "CRC VM disk file size: $vm_disk_size"
  fi
}

check_cluster_disk_usage() {
  info "Checking OpenShift cluster disk usage..."
  
  # Check node conditions
  info "Node conditions:"
  oc get nodes -o custom-columns="NAME:.metadata.name,DISK-PRESSURE:.status.conditions[?(@.type=='DiskPressure')].status,READY:.status.conditions[?(@.type=='Ready')].status"
  
  # Check node capacity
  info "Node storage capacity:"
  oc get nodes -o custom-columns="NAME:.metadata.name,EPHEMERAL-STORAGE:.status.capacity.ephemeral-storage,ALLOCATABLE:.status.allocatable.ephemeral-storage"
  
  # Check storage classes
  info "Available storage classes:"
  oc get storageclass -o custom-columns="NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM-POLICY:.reclaimPolicy"
  
  # Check PVC usage
  info "PVC usage summary:"
  oc get pvc --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,SIZE:.spec.resources.requests.storage,USED:.status.capacity.storage" | head -20
  
  # Check for disk pressure
  local disk_pressure
  disk_pressure=$(oc get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="DiskPressure")].status}')
  if [[ "$disk_pressure" == "True" ]]; then
    warn "DISK PRESSURE DETECTED on cluster nodes!"
    return 1
  else
    ok "No disk pressure detected"
    return 0
  fi
}

get_current_disk_usage() {
  info "Analyzing current disk usage..."
  
  # Get detailed node information
  local node_info
  node_info=$(oc describe nodes | grep -A 20 "Allocated resources:")
  echo "$node_info"
  
  # Check for evicted pods (sign of disk pressure)
  local evicted_pods
  evicted_pods=$(oc get pods --all-namespaces | grep Evicted | wc -l)
  if [[ $evicted_pods -gt 0 ]]; then
    warn "Found $evicted_pods evicted pods (possible disk pressure)"
  fi
  
  # Check image registry storage
  info "Image registry storage usage:"
  oc get pvc -n openshift-image-registry -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,SIZE:.spec.resources.requests.storage,USED:.status.capacity.storage"
}

# =========================
# Disk expansion functions
# =========================

expand_crc_disk() {
  local expand_size="$1"
  
  info "Attempting to expand CRC disk by $expand_size..."
  
  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would expand CRC disk by $expand_size"
    info "This would involve:"
    info "  1. Stopping CRC"
    info "  2. Expanding the VM disk image"
    info "  3. Starting CRC"
    info "  4. Expanding the filesystem inside the VM"
    return 0
  fi
  
  # Check if CRC supports disk expansion
  if crc config get disk-size >/dev/null 2>&1; then
    info "CRC supports disk-size configuration"
    
    local current_size
    current_size=$(crc config get disk-size 2>/dev/null || echo "31")
    info "Current CRC disk size: ${current_size}GB"
    
    # Calculate new size (convert expand_size to GB)
    local expand_gb
    expand_gb=$(echo "$expand_size" | sed 's/Gi$//' | sed 's/G$//')
    local new_size=$((current_size + expand_gb))
    
    warn "This will stop and restart CRC, which may take several minutes..."
    read -q "REPLY?Continue with disk expansion? (y/N) "
    echo
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
      info "Disk expansion cancelled"
      return 1
    fi
    
    info "Stopping CRC..."
    crc stop
    
    info "Setting new disk size to ${new_size}GB..."
    crc config set disk-size "$new_size"
    
    info "Starting CRC with expanded disk..."
    crc start
    
    # Wait for cluster to be ready
    info "Waiting for cluster to be ready..."
    sleep 30
    
    # Re-configure oc
    eval "$(crc oc-env)"
    
    ok "CRC disk expanded successfully!"
    
  else
    warn "CRC disk expansion via config not supported in this version"
    info "Manual expansion steps:"
    info "1. Stop CRC: crc stop"
    info "2. Locate VM disk: ~/.crc/machines/crc/crc.qcow2"
    info "3. Expand with qemu-img: qemu-img resize ~/.crc/machines/crc/crc.qcow2 +${expand_size}"
    info "4. Start CRC: crc start"
    info "5. Expand filesystem inside VM manually"
    return 1
  fi
}

expand_storage_class() {
  local expand_size="$1"
  
  info "Checking if storage class supports expansion..."
  
  # Check if the default storage class allows volume expansion
  local storage_class
  storage_class=$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
  
  if [[ -n "$storage_class" ]]; then
    info "Default storage class: $storage_class"
    
    local allow_expansion
    allow_expansion=$(oc get storageclass "$storage_class" -o jsonpath='{.allowVolumeExpansion}')
    
    if [[ "$allow_expansion" == "true" ]]; then
      ok "Storage class supports volume expansion"
    else
      warn "Storage class does not support volume expansion"
      info "You may need to expand the underlying CRC VM disk instead"
    fi
  else
    warn "No default storage class found"
  fi
}

# =========================
# Automatic expansion logic
# =========================

auto_expand_if_needed() {
  info "Checking if automatic expansion is needed..."
  
  # Check for disk pressure
  if ! check_cluster_disk_usage; then
    warn "Disk pressure detected - automatic expansion triggered"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would automatically expand disk by $EXPAND_SIZE"
      return 0
    fi
    
    expand_crc_disk "$EXPAND_SIZE"
    
    # Wait a bit and recheck
    info "Waiting for expansion to take effect..."
    sleep 60
    
    # Remove any disk pressure taints
    info "Removing disk pressure taints..."
    oc adm taint nodes --all node.kubernetes.io/disk-pressure:NoSchedule- || true
    
    ok "Automatic expansion completed"
  else
    ok "No automatic expansion needed"
  fi
}

# =========================
# Recommendations
# =========================

provide_recommendations() {
  info "Disk space management recommendations:"
  
  echo "1. Regular Cleanup:"
  echo "   - Run cleanup script: ./cleanup-disk-space.zsh --aggressive"
  echo "   - Remove unused projects and PVCs"
  echo "   - Prune old images and builds"
  echo
  echo "2. Storage Optimization:"
  echo "   - Use smaller PVC sizes where possible"
  echo "   - Enable PVC expansion in storage classes"
  echo "   - Monitor image registry storage usage"
  echo
  echo "3. CRC Configuration:"
  echo "   - Increase CRC disk size: crc config set disk-size 50"
  echo "   - Monitor host system disk space"
  echo "   - Consider using external storage for large datasets"
  echo
  echo "4. Monitoring:"
  echo "   - Check node conditions regularly"
  echo "   - Monitor PVC usage across namespaces"
  echo "   - Set up alerts for disk pressure"
}

# =========================
# Main execution
# =========================

main() {
  info "Starting disk space analysis..."
  
  # Always check current usage
  check_host_disk_space
  echo
  check_cluster_disk_usage
  local disk_pressure_detected=$?
  echo
  get_current_disk_usage
  echo
  
  if [[ "$CHECK_ONLY" == "true" ]]; then
    info "Check-only mode - analysis complete"
    provide_recommendations
    return 0
  fi
  
  # Handle automatic expansion
  if [[ "$AUTO_EXPAND" == "true" ]]; then
    auto_expand_if_needed
    return 0
  fi
  
  # Handle manual expansion
  if [[ "$EXPAND_SIZE" != "10Gi" ]] || [[ $disk_pressure_detected -ne 0 ]]; then
    info "Disk expansion requested or needed..."
    
    # Check storage class expansion capability
    expand_storage_class "$EXPAND_SIZE"
    echo
    
    # Expand CRC disk
    expand_crc_disk "$EXPAND_SIZE"
    echo
    
    # Recheck after expansion
    info "Rechecking disk usage after expansion..."
    check_cluster_disk_usage
  fi
  
  provide_recommendations
  
  ok "Disk space management completed!"
}

# Run main function
main "$@"
