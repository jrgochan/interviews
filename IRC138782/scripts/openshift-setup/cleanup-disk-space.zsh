#!/usr/bin/env zsh
set -euo pipefail

# =========================
# OpenShift Disk Space Cleanup Script
# =========================
# This script helps free up disk space on OpenShift clusters by:
# - Cleaning up completed/failed pods
# - Pruning old builds and deployments
# - Removing unused images and containers
# - Cleaning up temporary resources
# - Managing disk pressure taints
# - Providing disk usage analysis
#
# Prerequisites:
# - OpenShift CLI (oc) installed and configured
# - Cluster admin or sufficient permissions
# - Access to the OpenShift cluster
#
# Usage:
#   ./cleanup-disk-space.zsh [options]
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
      oc) print "  macOS: brew install openshift-cli" ;;
    esac
    exit 1
  fi
}

# Defaults
: "${DRY_RUN:=false}"
: "${AGGRESSIVE:=false}"
: "${REMOVE_TAINT:=true}"
: "${CLEANUP_PROJECTS:=true}"
: "${CLEANUP_IMAGES:=true}"
: "${CLEANUP_BUILDS:=true}"
: "${CLEANUP_PODS:=true}"

usage() {
  cat <<'EOF'
Usage: ./cleanup-disk-space.zsh [options]

Options:
  --dry-run           Show what would be cleaned up without actually doing it
  --aggressive        More aggressive cleanup (removes more resources)
  --no-taint-removal  Don't remove disk pressure taints
  --no-projects       Don't clean up unused projects
  --no-images         Don't clean up images
  --no-builds         Don't clean up builds
  --no-pods           Don't clean up completed/failed pods
  -h, --help          Show this help

Environment Variables:
  DRY_RUN=true           Enable dry run mode
  AGGRESSIVE=true        Enable aggressive cleanup
  REMOVE_TAINT=false     Disable taint removal
  CLEANUP_PROJECTS=false Disable project cleanup
  CLEANUP_IMAGES=false   Disable image cleanup
  CLEANUP_BUILDS=false   Disable build cleanup
  CLEANUP_PODS=false     Disable pod cleanup

Examples:
  # Basic cleanup
  ./cleanup-disk-space.zsh

  # Dry run to see what would be cleaned
  ./cleanup-disk-space.zsh --dry-run

  # Aggressive cleanup
  ./cleanup-disk-space.zsh --aggressive

  # Cleanup without removing taints
  ./cleanup-disk-space.zsh --no-taint-removal
EOF
}

# =========================
# Parse arguments
# =========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift;;
    --aggressive) AGGRESSIVE=true; shift;;
    --no-taint-removal) REMOVE_TAINT=false; shift;;
    --no-projects) CLEANUP_PROJECTS=false; shift;;
    --no-images) CLEANUP_IMAGES=false; shift;;
    --no-builds) CLEANUP_BUILDS=false; shift;;
    --no-pods) CLEANUP_PODS=false; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

# =========================
# Preflight checks
# =========================
info "OpenShift Disk Space Cleanup Tool"
info "=================================="

need oc

# Check if we're logged in
if ! oc whoami >/dev/null 2>&1; then
  err "Not logged into OpenShift. Please run 'oc login' first."
  exit 1
fi

CLUSTER_URL=$(oc whoami --show-server)
CURRENT_USER=$(oc whoami)
ok "Connected to: $CLUSTER_URL as $CURRENT_USER"

if [[ "$DRY_RUN" == "true" ]]; then
  warn "DRY RUN MODE - No changes will be made"
fi

# =========================
# Disk usage analysis
# =========================
analyze_disk_usage() {
  info "Analyzing current disk usage..."
  
  # Check node conditions
  info "Node conditions:"
  oc get nodes -o custom-columns="NAME:.metadata.name,DISK-PRESSURE:.status.conditions[?(@.type=='DiskPressure')].status,MEMORY-PRESSURE:.status.conditions[?(@.type=='MemoryPressure')].status,READY:.status.conditions[?(@.type=='Ready')].status"
  
  # Check node capacity and allocatable resources
  info "Node storage capacity:"
  oc describe nodes | grep -A 5 -B 5 "ephemeral-storage\|Allocatable"
  
  # Check PVC usage
  info "PVC usage across all namespaces:"
  oc get pvc --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.status.capacity.storage,STORAGECLASS:.spec.storageClassName"
  
  # Check for large pods
  info "Pods with high resource requests:"
  oc get pods --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,CPU-REQ:.spec.containers[*].resources.requests.cpu,MEM-REQ:.spec.containers[*].resources.requests.memory" | head -20
}

# =========================
# Cleanup functions
# =========================

cleanup_completed_pods() {
  if [[ "$CLEANUP_PODS" != "true" ]]; then
    info "Skipping pod cleanup (disabled)"
    return
  fi
  
  info "Cleaning up completed, failed, and evicted pods..."
  
  local pods_to_delete
  pods_to_delete=$(oc get pods --all-namespaces --field-selector=status.phase=Succeeded -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers 2>/dev/null || true)
  
  if [[ -n "$pods_to_delete" && "$pods_to_delete" != "No resources found" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would delete completed pods:"
      echo "$pods_to_delete"
    else
      echo "$pods_to_delete" | while read -r namespace pod; do
        if [[ -n "$namespace" && -n "$pod" && "$namespace" != "NAMESPACE" ]]; then
          oc delete pod "$pod" -n "$namespace" --ignore-not-found=true
        fi
      done
      ok "Cleaned up completed pods"
    fi
  fi
  
  # Clean up failed pods
  pods_to_delete=$(oc get pods --all-namespaces --field-selector=status.phase=Failed -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers 2>/dev/null || true)
  
  if [[ -n "$pods_to_delete" && "$pods_to_delete" != "No resources found" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would delete failed pods:"
      echo "$pods_to_delete"
    else
      echo "$pods_to_delete" | while read -r namespace pod; do
        if [[ -n "$namespace" && -n "$pod" && "$namespace" != "NAMESPACE" ]]; then
          oc delete pod "$pod" -n "$namespace" --ignore-not-found=true
        fi
      done
      ok "Cleaned up failed pods"
    fi
  fi
  
  # Clean up evicted pods
  local evicted_pods
  evicted_pods=$(oc get pods --all-namespaces | grep Evicted | awk '{print $1 " " $2}' || true)
  
  if [[ -n "$evicted_pods" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would delete evicted pods:"
      echo "$evicted_pods"
    else
      echo "$evicted_pods" | while read -r namespace pod; do
        if [[ -n "$namespace" && -n "$pod" ]]; then
          oc delete pod "$pod" -n "$namespace" --ignore-not-found=true
        fi
      done
      ok "Cleaned up evicted pods"
    fi
  fi
}

cleanup_builds() {
  if [[ "$CLEANUP_BUILDS" != "true" ]]; then
    info "Skipping build cleanup (disabled)"
    return
  fi
  
  info "Cleaning up old builds..."
  
  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would run: oc adm prune builds --confirm"
  else
    oc adm prune builds --confirm || warn "Build pruning failed or no builds to prune"
    ok "Cleaned up old builds"
  fi
}

cleanup_deployments() {
  info "Cleaning up old deployments..."
  
  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would run: oc adm prune deployments --confirm"
  else
    oc adm prune deployments --confirm || warn "Deployment pruning failed or no deployments to prune"
    ok "Cleaned up old deployments"
  fi
}

cleanup_images() {
  if [[ "$CLEANUP_IMAGES" != "true" ]]; then
    info "Skipping image cleanup (disabled)"
    return
  fi
  
  info "Attempting to clean up unused images..."
  
  # Try to get registry route
  local registry_route
  registry_route=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || true)
  
  if [[ -n "$registry_route" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would run: oc adm prune images --registry-url=https://$registry_route --confirm"
    else
      oc adm prune images --registry-url="https://$registry_route" --confirm || warn "Image pruning failed"
      ok "Cleaned up unused images"
    fi
  else
    warn "Could not determine registry route. Skipping image cleanup."
    info "You can manually enable the registry route with:"
    info "  oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p '{\"spec\":{\"defaultRoute\":true}}'"
  fi
}

cleanup_unused_projects() {
  if [[ "$CLEANUP_PROJECTS" != "true" ]]; then
    info "Skipping project cleanup (disabled)"
    return
  fi
  
  info "Identifying potentially unused projects..."
  
  # Get projects that are not system projects and have no running pods
  local unused_projects
  unused_projects=$(oc get projects -o custom-columns="NAME:.metadata.name" --no-headers | \
    grep -v -E "^(openshift|kube|default)" | \
    while read -r project; do
      if [[ -n "$project" ]]; then
        local pod_count
        pod_count=$(oc get pods -n "$project" --no-headers 2>/dev/null | wc -l)
        if [[ "$pod_count" -eq 0 ]]; then
          echo "$project"
        fi
      fi
    done)
  
  if [[ -n "$unused_projects" ]]; then
    warn "Found potentially unused projects (no running pods):"
    echo "$unused_projects"
    
    if [[ "$AGGRESSIVE" == "true" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        info "Would delete unused projects in aggressive mode"
      else
        warn "Aggressive mode: Deleting unused projects..."
        echo "$unused_projects" | while read -r project; do
          if [[ -n "$project" ]]; then
            oc delete project "$project" --ignore-not-found=true
          fi
        done
        ok "Deleted unused projects"
      fi
    else
      info "Use --aggressive flag to automatically delete these projects"
      info "Or manually delete with: oc delete project <project-name>"
    fi
  else
    ok "No unused projects found"
  fi
}

cleanup_temporary_resources() {
  info "Cleaning up temporary resources..."
  
  # Clean up jobs that have completed
  local completed_jobs
  completed_jobs=$(oc get jobs --all-namespaces --field-selector=status.successful=1 -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers 2>/dev/null || true)
  
  if [[ -n "$completed_jobs" && "$completed_jobs" != "No resources found" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would delete completed jobs:"
      echo "$completed_jobs"
    else
      echo "$completed_jobs" | while read -r namespace job; do
        if [[ -n "$namespace" && -n "$job" && "$namespace" != "NAMESPACE" ]]; then
          oc delete job "$job" -n "$namespace" --ignore-not-found=true
        fi
      done
      ok "Cleaned up completed jobs"
    fi
  fi
  
  # Clean up old replica sets
  if [[ "$AGGRESSIVE" == "true" ]]; then
    info "Aggressive mode: Cleaning up old replica sets..."
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would clean up old replica sets"
    else
      oc get rs --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,REPLICAS:.spec.replicas" --no-headers | \
        awk '$3 == 0 {print $1 " " $2}' | \
        while read -r namespace rs; do
          if [[ -n "$namespace" && -n "$rs" ]]; then
            oc delete rs "$rs" -n "$namespace" --ignore-not-found=true
          fi
        done
      ok "Cleaned up old replica sets"
    fi
  fi
}

remove_disk_pressure_taint() {
  if [[ "$REMOVE_TAINT" != "true" ]]; then
    info "Skipping taint removal (disabled)"
    return
  fi
  
  info "Checking for disk pressure taints..."
  
  local tainted_nodes
  tainted_nodes=$(oc get nodes -o custom-columns="NAME:.metadata.name,TAINTS:.spec.taints[*].key" --no-headers | grep "disk-pressure" | awk '{print $1}' || true)
  
  if [[ -n "$tainted_nodes" ]]; then
    warn "Found nodes with disk pressure taints:"
    echo "$tainted_nodes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would remove disk pressure taints from nodes"
    else
      echo "$tainted_nodes" | while read -r node; do
        if [[ -n "$node" ]]; then
          info "Removing disk pressure taint from node: $node"
          oc adm taint node "$node" node.kubernetes.io/disk-pressure:NoSchedule- || warn "Failed to remove taint from $node"
        fi
      done
      ok "Removed disk pressure taints"
    fi
  else
    ok "No disk pressure taints found"
  fi
}

force_garbage_collection() {
  info "Attempting to trigger garbage collection..."
  
  # This is a more aggressive approach - restart some system pods to trigger cleanup
  if [[ "$AGGRESSIVE" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would restart system pods to trigger garbage collection"
    else
      warn "Aggressive mode: Restarting some system pods to trigger cleanup..."
      
      # Restart the kubelet by deleting machine-config-daemon pods (they will restart automatically)
      oc delete pods -n openshift-machine-config-operator -l k8s-app=machine-config-daemon --ignore-not-found=true || true
      
      ok "Triggered system cleanup"
    fi
  fi
}

# =========================
# Main execution
# =========================
main() {
  info "Starting disk space cleanup..."
  
  # Analyze current state
  analyze_disk_usage
  
  # Perform cleanup operations
  cleanup_completed_pods
  cleanup_builds
  cleanup_deployments
  cleanup_images
  cleanup_unused_projects
  cleanup_temporary_resources
  
  # Remove taints and force cleanup
  remove_disk_pressure_taint
  force_garbage_collection
  
  # Final analysis
  info "Cleanup completed. Final disk usage analysis:"
  analyze_disk_usage
  
  if [[ "$DRY_RUN" == "true" ]]; then
    info "This was a dry run. No changes were made."
    info "Run without --dry-run to perform actual cleanup."
  else
    ok "Disk space cleanup completed!"
    info "Monitor your cluster for a few minutes to see if disk pressure is resolved."
    info "You may need to wait for the kubelet to update node conditions."
  fi
}

# Run main function
main "$@"
