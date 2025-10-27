#!/bin/bash
# Helm Deployment Script for RHOS HPC Modules
# Comprehensive deployment management for all HPC interview modules

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="hpc-interview"
TIMEOUT_MINUTES=10
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Available modules in dependency order
AVAILABLE_MODULES=("shared-resources" "hpc-base" "hpc-aiml" "hpc-midas" "hpc-milk")
MODULE_DESCRIPTIONS=(
    "shared-resources:Shared PVCs for all HPC modules"
    "hpc-base:Base HPC environment (GCC, MPI, Python)"
    "hpc-aiml:AI/ML environment (PyTorch, Jupyter, TensorBoard)"
    "hpc-midas:MIDAS data acquisition system (PSI/TRIUMF, ROOT)"
    "hpc-milk:MILK diffraction analysis (MAUD, Java)"
)

# Get module dependencies
get_dependencies() {
    local module="$1"
    case "$module" in
        "shared-resources") echo "" ;;
        "hpc-base") echo "shared-resources" ;;
        "hpc-aiml") echo "shared-resources" ;;
        "hpc-midas") echo "shared-resources" ;;
        "hpc-milk") echo "shared-resources" ;;
        *) echo "" ;;
    esac
}

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

# Display usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
  deploy          Deploy modules (default)
  uninstall       Uninstall modules
  list            List deployed modules
  status          Show status of deployed modules
  help            Show this help message

DEPLOY/UNINSTALL OPTIONS:
  --all                    Deploy/uninstall all modules
  --module <module>        Deploy/uninstall specific module(s), comma-separated
  --values <file>          Custom values file
  --namespace <ns>         Target namespace (default: hpc-interview)
  --timeout <min>          Timeout in minutes (default: 10)
  --dry-run               Show what would be deployed without executing
  --force                 Force reinstallation (uninstall then install)
  --wait                  Wait for deployment to be ready
  --skip-deps             Skip dependency checks

LIST/STATUS OPTIONS:
  --all-namespaces        Show resources across all namespaces
  --output <format>       Output format: table, json, yaml (default: table)

EXAMPLES:
  # Deploy all modules
  $0 deploy --all

  # Deploy specific modules
  $0 deploy --module hpc-aiml,hpc-midas

  # Deploy with custom values
  $0 deploy --module hpc-base --values custom-values.yaml

  # Force redeploy all modules
  $0 deploy --all --force

  # Uninstall specific module
  $0 uninstall --module hpc-milk

  # List all deployed modules
  $0 list

  # Show deployment status
  $0 status --module hpc-aiml

AVAILABLE MODULES:
EOF

    for desc in "${MODULE_DESCRIPTIONS[@]}"; do
        module="${desc%%:*}"
        description="${desc##*:}"
        printf "  %-20s %s\n" "$module" "$description"
    done

    cat << EOF

DEPENDENCIES:
  - shared-resources: Required by all other modules
  - hpc-base, hpc-aiml, hpc-midas, hpc-milk: Depend on shared-resources

For more information, visit: https://github.com/jrgochan/interviews
EOF
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}📋 Checking prerequisites...${NC}"
    log "Checking prerequisites"
    
    # Check for required commands
    local required_commands=("helm" "oc" "kubectl")
    local has_errors=false
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "${GREEN}✅ $cmd found${NC}"
            log "$cmd found"
        else
            echo -e "${RED}❌ $cmd not found${NC}"
            log "ERROR: $cmd not found"
            has_errors=true
        fi
    done
    
    # Check Helm version
    if command -v helm &> /dev/null; then
        local helm_version=$(helm version --short --client)
        echo -e "${CYAN}Helm version: ${helm_version}${NC}"
        log "Helm version: ${helm_version}"
    fi
    
    # Check cluster connectivity
    echo -e "${CYAN}Testing cluster connectivity...${NC}"
    if oc status &> /dev/null || kubectl cluster-info &> /dev/null; then
        echo -e "${GREEN}✅ Connected to cluster${NC}"
        log "Cluster connectivity verified"
    else
        echo -e "${RED}❌ Cannot connect to cluster${NC}"
        log "ERROR: Cluster connectivity failed"
        has_errors=true
    fi
    
    if [ "$has_errors" = true ]; then
        echo -e "${RED}❌ Prerequisites check failed${NC}"
        log "Prerequisites check failed"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
    log "Prerequisites check passed"
}

# Create namespace if it doesn't exist
ensure_namespace() {
    local namespace="$1"
    
    echo -e "${CYAN}Ensuring namespace: ${namespace}${NC}"
    log "Ensuring namespace: ${namespace}"
    
    if ! oc get namespace "${namespace}" &> /dev/null && ! kubectl get namespace "${namespace}" &> /dev/null; then
        echo -e "${YELLOW}Creating namespace: ${namespace}${NC}"
        if command -v oc &> /dev/null; then
            oc create namespace "${namespace}" || kubectl create namespace "${namespace}"
        else
            kubectl create namespace "${namespace}"
        fi
        log "Created namespace: ${namespace}"
    else
        echo -e "${GREEN}✅ Namespace ${namespace} exists${NC}"
        log "Namespace ${namespace} exists"
    fi
}

# Validate module names
validate_modules() {
    local modules_to_validate="$1"
    local invalid_modules=()
    
    IFS=',' read -ra MODULES <<< "$modules_to_validate"
    for module in "${MODULES[@]}"; do
        module=$(echo "$module" | xargs)  # trim whitespace
        if [[ ! " ${AVAILABLE_MODULES[@]} " =~ " ${module} " ]]; then
            invalid_modules+=("$module")
        fi
    done
    
    if [ ${#invalid_modules[@]} -gt 0 ]; then
        echo -e "${RED}❌ Invalid modules: ${invalid_modules[*]}${NC}"
        echo -e "${CYAN}Available modules: ${AVAILABLE_MODULES[*]}${NC}"
        exit 1
    fi
}


# Get all modules with dependencies resolved
resolve_dependencies() {
    local requested_modules="$1"
    local skip_deps="$2"
    local all_modules=()
    
    if [ "$skip_deps" = true ]; then
        IFS=',' read -ra all_modules <<< "$requested_modules"
    else
        # Add dependencies for each requested module
        IFS=',' read -ra MODULES <<< "$requested_modules"
        for module in "${MODULES[@]}"; do
            module=$(echo "$module" | xargs)
            local deps=$(get_dependencies "$module")
            if [ -n "$deps" ]; then
                IFS=' ' read -ra DEP_ARRAY <<< "$deps"
                for dep in "${DEP_ARRAY[@]}"; do
                    if [[ ! " ${all_modules[@]} " =~ " ${dep} " ]]; then
                        all_modules+=("$dep")
                    fi
                done
            fi
            if [[ ! " ${all_modules[@]} " =~ " ${module} " ]]; then
                all_modules+=("$module")
            fi
        done
    fi
    
    # Sort modules in dependency order
    local sorted_modules=()
    for available_module in "${AVAILABLE_MODULES[@]}"; do
        if [[ " ${all_modules[@]} " =~ " ${available_module} " ]]; then
            sorted_modules+=("$available_module")
        fi
    done
    
    echo "${sorted_modules[@]}"
}

# Check if Helm release exists
helm_release_exists() {
    local release_name="$1"
    local namespace="$2"
    
    helm list -n "$namespace" -q | grep -q "^${release_name}$"
}

# Deploy a single module
deploy_module() {
    local module="$1"
    local namespace="$2"
    local values_file="$3"
    local timeout="$4"
    local dry_run="$5"
    local force="$6"
    local wait="$7"
    
    echo -e "${BLUE}🚀 Deploying module: ${module}${NC}"
    log "Deploying module: ${module}"
    
    local chart_path="${SCRIPT_DIR}/${module}"
    local release_name="$module"
    
    # Check if chart directory exists
    if [ ! -d "$chart_path" ]; then
        echo -e "${RED}❌ Chart not found: ${chart_path}${NC}"
        log "ERROR: Chart not found: ${chart_path}"
        return 1
    fi
    
    # Build Helm command
    local helm_cmd="helm upgrade --install ${release_name} ${chart_path}"
    helm_cmd+=" --namespace ${namespace}"
    helm_cmd+=" --timeout ${timeout}m"
    
    if [ "$dry_run" = true ]; then
        helm_cmd+=" --dry-run"
    fi
    
    if [ "$wait" = true ]; then
        helm_cmd+=" --wait"
    fi
    
    if [ -n "$values_file" ]; then
        if [ -f "$values_file" ]; then
            helm_cmd+=" --values ${values_file}"
        else
            echo -e "${RED}❌ Values file not found: ${values_file}${NC}"
            log "ERROR: Values file not found: ${values_file}"
            return 1
        fi
    fi
    
    # Handle force reinstallation
    if [ "$force" = true ] && helm_release_exists "$release_name" "$namespace"; then
        echo -e "${YELLOW}⚠️  Force mode: Uninstalling existing release${NC}"
        helm uninstall "$release_name" --namespace "$namespace" || true
    fi
    
    # Execute deployment
    echo -e "${CYAN}Executing: ${helm_cmd}${NC}"
    if eval "$helm_cmd"; then
        echo -e "${GREEN}✅ Successfully deployed: ${module}${NC}"
        log "Successfully deployed: ${module}"
        return 0
    else
        echo -e "${RED}❌ Failed to deploy: ${module}${NC}"
        log "ERROR: Failed to deploy: ${module}"
        return 1
    fi
}

# Uninstall a single module
uninstall_module() {
    local module="$1"
    local namespace="$2"
    
    echo -e "${BLUE}🗑️  Uninstalling module: ${module}${NC}"
    log "Uninstalling module: ${module}"
    
    local release_name="$module"
    
    if helm_release_exists "$release_name" "$namespace"; then
        if helm uninstall "$release_name" --namespace "$namespace"; then
            echo -e "${GREEN}✅ Successfully uninstalled: ${module}${NC}"
            log "Successfully uninstalled: ${module}"
            return 0
        else
            echo -e "${RED}❌ Failed to uninstall: ${module}${NC}"
            log "ERROR: Failed to uninstall: ${module}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  Module not found: ${module}${NC}"
        log "WARNING: Module not found: ${module}"
        return 0
    fi
}

# List deployed modules
list_modules() {
    local namespace="$1"
    local all_namespaces="$2"
    local output_format="$3"
    
    echo -e "${BLUE}📋 Listing deployed modules...${NC}"
    
    local helm_cmd="helm list"
    
    if [ "$all_namespaces" = true ]; then
        helm_cmd+=" --all-namespaces"
    else
        helm_cmd+=" --namespace ${namespace}"
    fi
    
    case "$output_format" in
        "json")
            helm_cmd+=" --output json"
            ;;
        "yaml")
            helm_cmd+=" --output yaml"
            ;;
        *)
            helm_cmd+=" --output table"
            ;;
    esac
    
    eval "$helm_cmd"
}

# Show deployment status
show_status() {
    local modules="$1"
    local namespace="$2"
    
    echo -e "${BLUE}📊 Showing deployment status...${NC}"
    
    if [ "$modules" = "all" ]; then
        modules=$(IFS=','; echo "${AVAILABLE_MODULES[*]}")
    fi
    
    IFS=',' read -ra MODULES <<< "$modules"
    for module in "${MODULES[@]}"; do
        module=$(echo "$module" | xargs)
        local release_name="$module"
        
        echo -e "${CYAN}=== ${module} ===${NC}"
        
        if helm_release_exists "$release_name" "$namespace"; then
            helm status "$release_name" --namespace "$namespace"
            
            echo -e "\n${CYAN}Pod Status:${NC}"
            if command -v oc &> /dev/null; then
                oc get pods -l app.kubernetes.io/instance="$release_name" -n "$namespace" 2>/dev/null || echo "No pods found"
            else
                kubectl get pods -l app.kubernetes.io/instance="$release_name" -n "$namespace" 2>/dev/null || echo "No pods found"
            fi
        else
            echo -e "${YELLOW}Module not deployed${NC}"
        fi
        echo
    done
}

# Main deployment function
deploy_modules() {
    local modules="$1"
    local namespace="$2"
    local values_file="$3"
    local timeout="$4"
    local dry_run="$5"
    local force="$6"
    local wait="$7"
    local skip_deps="$8"
    
    echo -e "${BLUE}🚀 Starting module deployment...${NC}"
    log "Starting deployment for modules: ${modules}"
    
    # Resolve dependencies
    local resolved_modules
    resolved_modules=$(resolve_dependencies "$modules" "$skip_deps")
    
    echo -e "${CYAN}Deployment order: ${resolved_modules}${NC}"
    log "Deployment order: ${resolved_modules}"
    
    # Deploy each module
    local failed_modules=()
    local successful_modules=()
    
    for module in $resolved_modules; do
        if deploy_module "$module" "$namespace" "$values_file" "$timeout" "$dry_run" "$force" "$wait"; then
            successful_modules+=("$module")
        else
            failed_modules+=("$module")
            if [ "$force" != true ]; then
                echo -e "${RED}❌ Stopping deployment due to failure${NC}"
                break
            fi
        fi
    done
    
    # Summary
    echo -e "\n${BLUE}📊 Deployment Summary${NC}"
    if [ ${#successful_modules[@]} -gt 0 ]; then
        echo -e "${GREEN}✅ Successfully deployed: ${successful_modules[*]}${NC}"
        log "Successfully deployed: ${successful_modules[*]}"
    fi
    
    if [ ${#failed_modules[@]} -gt 0 ]; then
        echo -e "${RED}❌ Failed to deploy: ${failed_modules[*]}${NC}"
        log "Failed to deploy: ${failed_modules[*]}"
        return 1
    fi
    
    return 0
}

# Main uninstall function
uninstall_modules() {
    local modules="$1"
    local namespace="$2"
    
    echo -e "${BLUE}🗑️  Starting module uninstallation...${NC}"
    log "Starting uninstallation for modules: ${modules}"
    
    # Uninstall in reverse dependency order
    IFS=',' read -ra MODULES <<< "$modules"
    local reversed_modules=()
    for ((i=${#AVAILABLE_MODULES[@]}-1; i>=0; i--)); do
        for module in "${MODULES[@]}"; do
            module=$(echo "$module" | xargs)
            if [ "${AVAILABLE_MODULES[i]}" = "$module" ]; then
                reversed_modules+=("$module")
                break
            fi
        done
    done
    
    echo -e "${CYAN}Uninstall order: ${reversed_modules[*]}${NC}"
    log "Uninstall order: ${reversed_modules[*]}"
    
    # Uninstall each module
    local failed_modules=()
    local successful_modules=()
    
    for module in "${reversed_modules[@]}"; do
        if uninstall_module "$module" "$namespace"; then
            successful_modules+=("$module")
        else
            failed_modules+=("$module")
        fi
    done
    
    # Summary
    echo -e "\n${BLUE}📊 Uninstallation Summary${NC}"
    if [ ${#successful_modules[@]} -gt 0 ]; then
        echo -e "${GREEN}✅ Successfully uninstalled: ${successful_modules[*]}${NC}"
        log "Successfully uninstalled: ${successful_modules[*]}"
    fi
    
    if [ ${#failed_modules[@]} -gt 0 ]; then
        echo -e "${RED}❌ Failed to uninstall: ${failed_modules[*]}${NC}"
        log "Failed to uninstall: ${failed_modules[*]}"
        return 1
    fi
    
    return 0
}

# Main function
main() {
    # Initialize log file
    echo "=== Helm Deployment Script - $(date) ===" > "${LOG_FILE}"
    
    # Parse command line arguments
    local command="deploy"
    local modules=""
    local namespace="$NAMESPACE"
    local values_file=""
    local timeout="$TIMEOUT_MINUTES"
    local dry_run=false
    local force=false
    local wait=false
    local skip_deps=false
    local all_namespaces=false
    local output_format="table"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            deploy|uninstall|list|status|help)
                command="$1"
                shift
                ;;
            --all)
                modules=$(IFS=','; echo "${AVAILABLE_MODULES[*]}")
                shift
                ;;
            --module)
                modules="$2"
                validate_modules "$modules"
                shift 2
                ;;
            --values)
                values_file="$2"
                shift 2
                ;;
            --namespace)
                namespace="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --wait)
                wait=true
                shift
                ;;
            --skip-deps)
                skip_deps=true
                shift
                ;;
            --all-namespaces)
                all_namespaces=true
                shift
                ;;
            --output)
                output_format="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Handle commands
    case "$command" in
        "help")
            show_usage
            exit 0
            ;;
        "list")
            check_prerequisites
            list_modules "$namespace" "$all_namespaces" "$output_format"
            ;;
        "status")
            check_prerequisites
            if [ -z "$modules" ]; then
                modules="all"
            fi
            show_status "$modules" "$namespace"
            ;;
        "deploy")
            if [ -z "$modules" ]; then
                echo -e "${RED}❌ No modules specified. Use --all or --module <module>${NC}"
                show_usage
                exit 1
            fi
            check_prerequisites
            ensure_namespace "$namespace"
            deploy_modules "$modules" "$namespace" "$values_file" "$timeout" "$dry_run" "$force" "$wait" "$skip_deps"
            ;;
        "uninstall")
            if [ -z "$modules" ]; then
                echo -e "${RED}❌ No modules specified. Use --all or --module <module>${NC}"
                show_usage
                exit 1
            fi
            check_prerequisites
            uninstall_modules "$modules" "$namespace"
            ;;
        *)
            echo -e "${RED}❌ Unknown command: $command${NC}"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
