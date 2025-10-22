#!/bin/bash
# Force delete and recreate CRC (CodeReady Containers) cluster
# Fixes bundle mismatch and other cluster issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 CRC Cluster Reset & Recreate${NC}"
echo -e "${YELLOW}This will completely remove and recreate your CodeReady Containers cluster${NC}"
echo

# Configuration for Full OpenShift (most capable)
MEMORY_SIZE="16384"  # 16GB RAM for full OpenShift
CPU_COUNT="6"        # 6 CPUs for optimal performance
PRESET="openshift"   # Full OpenShift Container Platform (not MicroShift)
DISK_SIZE="512"      # 128 GB (adjust based on your system)

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}📋 Checking prerequisites...${NC}"
    
    if ! command -v crc &> /dev/null; then
        echo -e "${RED}❌ CodeReady Containers (crc) not found${NC}"
        echo -e "${YELLOW}Please download and install from:${NC}"
        echo -e "https://developers.redhat.com/products/openshift-local/overview"
        exit 1
    fi
    
    echo -e "${GREEN}✅ CRC is installed${NC}"
    
    # Check system resources and configure optimal OpenShift
    local total_memory=$(sysctl hw.memsize | awk '{print int($2/1024/1024/1024)}')
    local total_cpus=$(sysctl hw.ncpu | awk '{print $2}')
    echo -e "System Resources: ${total_memory}GB RAM, ${total_cpus} CPUs"
    
    # Configure for full OpenShift based on system resources
    if [ "$total_memory" -ge 32 ]; then
        echo -e "${GREEN}High-end system detected - configuring maximum OpenShift${NC}"
        MEMORY_SIZE="20480"  # 20GB for high-performance
        CPU_COUNT="8"
        DISK_SIZE="120"
    elif [ "$total_memory" -ge 16 ]; then
        echo -e "${GREEN}Mid-range system - configuring standard OpenShift${NC}"
        MEMORY_SIZE="16384"  # 16GB standard
        CPU_COUNT="6"
        DISK_SIZE="100"
    elif [ "$total_memory" -ge 12 ]; then
        echo -e "${YELLOW}Lower resources - configuring minimal full OpenShift${NC}"
        MEMORY_SIZE="12288"  # 12GB minimal
        CPU_COUNT="4"
        DISK_SIZE="80"
    else
        echo -e "${RED}⚠️  Warning: System has less than 12GB RAM${NC}"
        echo -e "${YELLOW}Full OpenShift requires minimum 12GB RAM${NC}"
        echo -e "${BLUE}Options:${NC}"
        echo -e "1. Continue with MicroShift (reduced functionality)"
        echo -e "2. Continue with minimal OpenShift (may be slow)"
        echo -e "3. Cancel and upgrade system RAM"
        echo
        read -p "Choose option [1/2/3]: " -n 1 -r
        echo
        case $REPLY in
            1)
                PRESET="microshift"
                MEMORY_SIZE="8192"
                CPU_COUNT="4"
                DISK_SIZE="60"
                echo -e "${YELLOW}Using MicroShift preset${NC}"
                ;;
            2)
                MEMORY_SIZE="10240"  # 10GB absolute minimum
                CPU_COUNT="4"
                DISK_SIZE="60"
                echo -e "${YELLOW}Using minimal OpenShift (performance may be degraded)${NC}"
                ;;
            *)
                echo -e "${YELLOW}Operation cancelled${NC}"
                exit 0
                ;;
        esac
    fi
    
    echo -e "${BLUE}Configured for: ${MEMORY_SIZE}MB RAM, ${CPU_COUNT} CPUs, ${DISK_SIZE}GB disk, preset: ${PRESET}${NC}"
}

# Function to force delete existing cluster
force_delete_cluster() {
    echo -e "${BLUE}🗑️  Force deleting existing cluster...${NC}"
    
    # Get current status
    echo -e "Current CRC status:"
    crc status || true
    
    # Stop cluster if running
    echo -e "${YELLOW}Stopping cluster...${NC}"
    crc stop --force 2>/dev/null || true
    
    # Delete cluster
    echo -e "${YELLOW}Deleting cluster (this may take a few minutes)...${NC}"
    crc delete --force || true
    
    # Clean up any remaining artifacts
    echo -e "${YELLOW}Cleaning up CRC artifacts...${NC}"
    
    # Remove CRC cache and config (nuclear option)
    read -p "Remove all CRC cache and configuration? This ensures a completely clean start. [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Removing CRC cache directory...${NC}"
        rm -rf ~/.crc/cache/* 2>/dev/null || true
        rm -rf ~/.crc/machines/* 2>/dev/null || true
        echo -e "${GREEN}✅ CRC cache cleaned${NC}"
    fi
    
    echo -e "${GREEN}✅ Cluster deletion completed${NC}"
}

# Function to setup fresh cluster
create_fresh_cluster() {
    echo -e "${BLUE}🚀 Creating fresh CRC cluster with ${PRESET}...${NC}"
    
    # Set up configuration for most capable OpenShift
    echo -e "${YELLOW}Configuring cluster resources for optimal performance...${NC}"
    crc config set memory "$MEMORY_SIZE"
    crc config set cpus "$CPU_COUNT"
    crc config set disk-size "$DISK_SIZE"
    crc config set preset "$PRESET"
    
    # Configure additional settings for full OpenShift
    if [ "$PRESET" = "openshift" ]; then
        echo -e "${BLUE}Configuring full OpenShift Container Platform...${NC}"
        
        # Check for pull secret
        if [ ! -f ~/.crc/pull-secret.txt ]; then
            echo -e "${YELLOW}⚠️  Pull secret not found for full OpenShift${NC}"
            echo -e "${BLUE}To get the most capable OpenShift:${NC}"
            echo -e "1. Visit: https://console.redhat.com/openshift/create/local"
            echo -e "2. Download your pull secret"
            echo -e "3. Save it as: ~/.crc/pull-secret.txt"
            echo
            read -p "Do you have a pull secret file? [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                read -p "Enter path to pull secret file: " pull_secret_path
                if [ -f "$pull_secret_path" ]; then
                    cp "$pull_secret_path" ~/.crc/pull-secret.txt
                    echo -e "${GREEN}✅ Pull secret configured${NC}"
                else
                    echo -e "${RED}❌ Pull secret file not found: $pull_secret_path${NC}"
                    echo -e "${YELLOW}Continuing without pull secret (reduced functionality)${NC}"
                fi
            else
                echo -e "${YELLOW}Continuing without pull secret${NC}"
                echo -e "${BLUE}Note: Some OpenShift features may be limited${NC}"
            fi
        else
            echo -e "${GREEN}✅ Pull secret found${NC}"
        fi
        
        # Enable additional OpenShift features
        crc config set enable-cluster-monitoring true
        crc config set disable-update-check false
        
        # Set network configuration for better connectivity
        crc config set network-mode user
        
    fi
    
    # Show final configuration
    echo -e "${BLUE}Final CRC Configuration:${NC}"
    crc config view
    
    # Setup CRC (downloads bundle if needed)
    echo -e "${YELLOW}Setting up CRC (may download ${PRESET} bundle - this could take 10-30 minutes)...${NC}"
    crc setup
    
    # Start the cluster
    echo -e "${YELLOW}Starting fresh ${PRESET} cluster (this will take 5-15 minutes)...${NC}"
    if [ -f ~/.crc/pull-secret.txt ]; then
        crc start --pull-secret-file ~/.crc/pull-secret.txt
    else
        crc start
    fi
    
    echo -e "${GREEN}✅ Fresh ${PRESET} cluster created successfully${NC}"
}

# Function to verify cluster and get credentials
verify_and_configure() {
    echo -e "${BLUE}🔌 Verifying cluster and getting credentials...${NC}"
    
    # Wait for cluster to be fully ready
    echo -e "${YELLOW}Waiting for cluster to be fully ready...${NC}"
    sleep 30  # Give cluster time to stabilize
    
    # Check status
    crc status
    
    # Get console credentials (different for OpenShift vs MicroShift)
    echo -e "${BLUE}Console credentials:${NC}"
    if [ "$PRESET" = "openshift" ]; then
        crc console --credentials || echo "Full OpenShift credentials available via console"
    else
        echo "MicroShift preset - simplified authentication"
    fi
    
    # Get login command
    echo
    echo -e "${BLUE}Login commands:${NC}"
    
    # Extract login info
    local console_url=$(crc console --url 2>/dev/null || echo "https://console-openshift-console.apps-crc.testing")
    echo -e "Console URL: ${console_url}"
    
    # Configure oc CLI environment
    eval $(crc oc-env)
    
    # Show login options for full OpenShift
    if [ "$PRESET" = "openshift" ]; then
        echo -e "${GREEN}Full OpenShift login options:${NC}"
        echo -e "  oc login -u developer -p developer https://api.crc.testing:6443"
        echo -e "  oc login -u kubeadmin https://api.crc.testing:6443  # Admin access"
        
        # Get kubeadmin password
        local kubeadmin_password=$(crc console --credentials 2>/dev/null | grep "kubeadmin" | awk '{print $NF}' || echo "check 'crc console --credentials'")
        echo -e "  Admin password: ${kubeadmin_password}"
    else
        echo -e "${GREEN}MicroShift login:${NC}"
        echo -e "  oc login -u developer https://api.crc.testing:6443"
    fi
    
    # Test connection
    echo
    echo -e "${YELLOW}Testing connection...${NC}"
    if oc login -u developer -p developer "https://api.crc.testing:6443" 2>/dev/null; then
        echo -e "${GREEN}✅ Successfully logged in to ${PRESET} cluster${NC}"
        oc status
        echo
        echo -e "${BLUE}Available projects:${NC}"
        oc projects
    else
        echo -e "${YELLOW}⚠️  Manual login may be required${NC}"
        echo -e "Try: oc login -u developer https://api.crc.testing:6443"
    fi
    
    # Show additional capabilities for full OpenShift
    if [ "$PRESET" = "openshift" ]; then
        echo
        echo -e "${BLUE}🎉 Full OpenShift Features Available:${NC}"
        echo -e "  • Web Console with full UI"
        echo -e "  • Operator Hub for additional services"
        echo -e "  • Persistent storage with multiple providers"
        echo -e "  • Service mesh and serverless capabilities"
        echo -e "  • Complete monitoring and logging stack"
        echo -e "  • Developer and admin perspectives"
        echo -e "  • CI/CD with OpenShift Pipelines"
        echo -e "  • Container registry"
    fi
}

# Function to show next steps
show_next_steps() {
    echo
    echo -e "${GREEN}🎉 CRC Cluster Reset Complete!${NC}"
    echo
    echo -e "${BLUE}Next steps for HPC environment:${NC}"
    echo -e "1. Verify login: ${YELLOW}oc whoami${NC}"
    echo -e "2. Set up HPC environment: ${YELLOW}./setup.sh${NC}"
    echo -e "3. Run demonstrations: ${YELLOW}./examples/run-mpi-debug.sh${NC}"
    echo
    echo -e "${BLUE}Alternative (immediate testing):${NC}"
    echo -e "  ${YELLOW}./examples/simple-podman-test.sh${NC}"
    echo
    echo -e "${BLUE}Cluster information:${NC}"
    echo -e "  Console URL: $(crc console --url 2>/dev/null || echo 'Run: crc console --url')"
    echo -e "  API URL: https://api.crc.testing:6443"
    echo -e "  Username: developer"
    echo -e "  Password: developer"
}

# Main execution
main() {
    check_prerequisites
    
    echo -e "${RED}⚠️  WARNING: This will completely delete your existing CRC cluster${NC}"
    echo -e "All data in the cluster will be lost."
    echo
    read -p "Are you sure you want to proceed? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled${NC}"
        exit 0
    fi
    
    force_delete_cluster
    create_fresh_cluster
    verify_and_configure
    show_next_steps
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--force] [--help]"
        echo "Force delete and recreate CRC cluster"
        echo "  --force  Skip confirmation prompts"
        echo "  --help   Show this help message"
        exit 0
        ;;
    --force)
        check_prerequisites
        force_delete_cluster
        create_fresh_cluster
        verify_and_configure
        show_next_steps
        ;;
    *)
        main
        ;;
esac
