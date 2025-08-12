#!/usr/bin/env zsh
# =========================
# JupyterHub Deployment Examples
# =========================
# This script demonstrates various deployment scenarios for JupyterHub on OpenShift.
# Run individual examples by uncommenting the desired section.

set -euo pipefail

# Colors for output
info() { print -P "%F{cyan}==>%f $*"; }
ok()   { print -P "%F{green}✔%f $*"; }
warn() { print -P "%F{yellow}WARNING:%f $*"; }
err()  { print -P "%F{red}ERROR:%f $*" >&2; }

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy-jupyterhub.zsh"

# Check if deploy script exists
if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    err "Deploy script not found: $DEPLOY_SCRIPT"
    exit 1
fi

info "JupyterHub Deployment Examples"
info "=============================="
echo

# =========================
# Example 1: Basic Development Setup
# =========================
example_basic() {
    info "Example 1: Basic Development Setup"
    echo "This deploys JupyterHub with minimal resources for development/testing."
    echo
    
    "$DEPLOY_SCRIPT" \
        --namespace jupyterhub-dev \
        --admin-user developer \
        --storage-size 5Gi \
        --user-storage 2Gi \
        --memory-limit 1Gi \
        --cpu-limit 500m \
        --max-users 5
}

# =========================
# Example 2: Production-like Setup
# =========================
example_production() {
    info "Example 2: Production-like Setup"
    echo "This deploys JupyterHub with higher resources for production use."
    echo
    
    "$DEPLOY_SCRIPT" \
        --namespace jupyterhub-prod \
        --admin-user admin \
        --storage-size 50Gi \
        --user-storage 10Gi \
        --memory-limit 4Gi \
        --cpu-limit 2000m \
        --max-users 25 \
        --idle-timeout 7200 \
        --cull-timeout 14400
}

# =========================
# Example 3: Data Science Focused
# =========================
example_datascience() {
    info "Example 3: Data Science Focused Setup"
    echo "This deploys JupyterHub with data science notebook image and high resources."
    echo
    
    "$DEPLOY_SCRIPT" \
        --namespace jupyterhub-ds \
        --admin-user datascientist \
        --notebook-image quay.io/jupyter/datascience-notebook:latest \
        --storage-size 20Gi \
        --user-storage 15Gi \
        --memory-limit 8Gi \
        --cpu-limit 4000m \
        --max-users 15
}

# =========================
# Example 4: Minimal Resource Setup
# =========================
example_minimal() {
    info "Example 4: Minimal Resource Setup"
    echo "This deploys JupyterHub with minimal resources for resource-constrained environments."
    echo
    
    "$DEPLOY_SCRIPT" \
        --namespace jupyterhub-minimal \
        --admin-user admin \
        --notebook-image quay.io/jupyter/minimal-notebook:latest \
        --storage-size 2Gi \
        --user-storage 1Gi \
        --memory-limit 512Mi \
        --cpu-limit 250m \
        --max-users 3
}

# =========================
# Example 5: Custom Configuration
# =========================
example_custom() {
    info "Example 5: Custom Configuration"
    echo "This demonstrates custom image and configuration options."
    echo
    
    # Set custom admin password
    CUSTOM_PASSWORD="MySecurePassword123!"
    
    "$DEPLOY_SCRIPT" \
        --namespace jupyterhub-custom \
        --admin-user customadmin \
        --admin-password "$CUSTOM_PASSWORD" \
        --jupyterhub-image quay.io/jupyterhub/jupyterhub:3.1 \
        --notebook-image quay.io/jupyter/scipy-notebook:python-3.11 \
        --storage-size 30Gi \
        --user-storage 8Gi \
        --memory-limit 6Gi \
        --cpu-limit 3000m \
        --max-users 20 \
        --idle-timeout 1800 \
        --cull-timeout 3600
}

# =========================
# Cleanup Examples
# =========================
cleanup_example() {
    local namespace="$1"
    info "Cleaning up namespace: $namespace"
    
    if oc get namespace "$namespace" >/dev/null 2>&1; then
        oc delete all,pvc,secret,configmap,route -l app=jupyterhub -n "$namespace"
        oc delete project "$namespace"
        ok "Cleaned up $namespace"
    else
        warn "Namespace $namespace does not exist"
    fi
}

cleanup_all_examples() {
    info "Cleaning up all example deployments"
    
    local namespaces=(
        "jupyterhub-dev"
        "jupyterhub-prod"
        "jupyterhub-ds"
        "jupyterhub-minimal"
        "jupyterhub-custom"
    )
    
    for ns in "${namespaces[@]}"; do
        cleanup_example "$ns"
    done
}

# =========================
# Go Examples
# =========================
example_go_basic() {
    info "Go Example: Basic Deployment"
    echo "This demonstrates using the Go implementation for deployment."
    echo
    
    cd "$SCRIPT_DIR"
    go run deploy_jupyterhub.go \
        --namespace=jupyterhub-go \
        --admin-user=goadmin \
        --storage-size=10Gi \
        --memory-limit=2Gi \
        --max-users=10
}

example_go_advanced() {
    info "Go Example: Advanced Deployment"
    echo "This demonstrates advanced Go deployment with custom settings."
    echo
    
    cd "$SCRIPT_DIR"
    go run deploy_jupyterhub.go \
        --namespace=jupyterhub-go-advanced \
        --name=advanced-hub \
        --admin-user=advanced-admin \
        --jupyterhub-image=quay.io/jupyterhub/jupyterhub:4.0 \
        --notebook-image=quay.io/jupyter/datascience-notebook:latest \
        --storage-size=25Gi \
        --user-storage-size=12Gi \
        --memory-limit=6Gi \
        --cpu-limit=3000m \
        --max-users=30 \
        --timeout=15m
}

# =========================
# Menu System
# =========================
show_menu() {
    echo
    info "Available Examples:"
    echo "1) Basic Development Setup"
    echo "2) Production-like Setup"
    echo "3) Data Science Focused"
    echo "4) Minimal Resource Setup"
    echo "5) Custom Configuration"
    echo "6) Go Basic Deployment"
    echo "7) Go Advanced Deployment"
    echo
    info "Cleanup Options:"
    echo "c) Cleanup specific namespace"
    echo "C) Cleanup all example namespaces"
    echo
    echo "q) Quit"
    echo
}

# =========================
# Main Menu Loop
# =========================
main() {
    if [[ $# -gt 0 ]]; then
        # Run specific example if provided as argument
        case "$1" in
            1|basic) example_basic ;;
            2|production) example_production ;;
            3|datascience) example_datascience ;;
            4|minimal) example_minimal ;;
            5|custom) example_custom ;;
            6|go-basic) example_go_basic ;;
            7|go-advanced) example_go_advanced ;;
            cleanup) cleanup_all_examples ;;
            *) err "Unknown example: $1"; exit 1 ;;
        esac
        return
    fi
    
    # Interactive menu
    while true; do
        show_menu
        read -r "choice?Choose an option: "
        
        case "$choice" in
            1) example_basic ;;
            2) example_production ;;
            3) example_datascience ;;
            4) example_minimal ;;
            5) example_custom ;;
            6) example_go_basic ;;
            7) example_go_advanced ;;
            c)
                read -r "ns?Enter namespace to cleanup: "
                cleanup_example "$ns"
                ;;
            C) cleanup_all_examples ;;
            q|Q) info "Goodbye!"; break ;;
            *) warn "Invalid option: $choice" ;;
        esac
        
        echo
        read -r "?Press Enter to continue..."
    done
}

# =========================
# Usage Information
# =========================
usage() {
    cat <<'EOF'
Usage: ./examples.zsh [option]

Options:
  1, basic        Run basic development setup
  2, production   Run production-like setup
  3, datascience  Run data science focused setup
  4, minimal      Run minimal resource setup
  5, custom       Run custom configuration setup
  6, go-basic     Run Go basic deployment
  7, go-advanced  Run Go advanced deployment
  cleanup         Cleanup all example namespaces

If no option is provided, an interactive menu will be shown.

Examples:
  ./examples.zsh basic
  ./examples.zsh production
  ./examples.zsh cleanup
EOF
}

# Handle help flag
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Run main function
main "$@"
