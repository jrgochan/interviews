#!/bin/bash
# Helper script to start OpenShift Local in Podman Desktop

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting OpenShift Local Environment${NC}"
echo

# Function to check Podman Desktop status
check_podman_desktop() {
    echo -e "${BLUE}📋 Checking Podman Desktop status...${NC}"
    
    if ! command -v podman &> /dev/null; then
        echo -e "${RED}❌ Podman CLI not found${NC}"
        echo -e "${YELLOW}Please install Podman Desktop from: https://podman-desktop.io/${NC}"
        exit 1
    fi
    
    # Check if Podman machine is running
    if ! podman machine info &> /dev/null; then
        echo -e "${YELLOW}⚠️  Podman machine not running, attempting to start...${NC}"
        podman machine start || {
            echo -e "${RED}❌ Failed to start Podman machine${NC}"
            echo -e "${YELLOW}Please start Podman Desktop application manually${NC}"
            exit 1
        }
    fi
    
    echo -e "${GREEN}✅ Podman Desktop is running${NC}"
}

# Function to start OpenShift Local
start_openshift_local() {
    echo -e "${BLUE}🎯 Starting OpenShift Local cluster...${NC}"
    
    # Check if CRC (CodeReady Containers) or OpenShift Local is available
    if command -v crc &> /dev/null; then
        echo -e "Using CodeReady Containers (crc)..."
        
        # Check CRC status
        crc_status=$(crc status 2>/dev/null | grep "CRC VM:" | awk '{print $3}' || echo "Stopped")
        
        if [ "$crc_status" = "Running" ]; then
            echo -e "${GREEN}✅ CRC cluster is already running${NC}"
        else
            echo -e "${YELLOW}Starting CRC cluster...${NC}"
            crc start
        fi
        
        # Get login info
        echo -e "${BLUE}Getting cluster login information...${NC}"
        crc console --credentials
        
    elif command -v podman &> /dev/null; then
        echo -e "${YELLOW}Using Podman for local OpenShift setup...${NC}"
        
        # Create a simple pod-based environment for testing
        echo -e "Setting up pod-based HPC environment..."
        
        # This creates a basic environment without full OpenShift
        # but allows testing the HPC components
        podman network create hpc-network 2>/dev/null || true
        
        echo -e "${GREEN}✅ Pod-based environment ready${NC}"
        echo -e "${BLUE}Note: Using simplified pod environment instead of full OpenShift${NC}"
        
    else
        echo -e "${RED}❌ No suitable container runtime found${NC}"
        exit 1
    fi
}

# Function to provide setup instructions
provide_instructions() {
    echo
    echo -e "${BLUE}📝 OpenShift Local Setup Instructions${NC}"
    echo
    echo -e "${YELLOW}If you don't have OpenShift Local set up yet:${NC}"
    echo
    echo -e "1. ${BLUE}Open Podman Desktop application${NC}"
    echo -e "   - Make sure it's running and the machine is started"
    echo
    echo -e "2. ${BLUE}Download OpenShift Local (formerly CodeReady Containers):${NC}"
    echo -e "   https://developers.redhat.com/products/openshift-local/overview"
    echo
    echo -e "3. ${BLUE}Extract and set up CRC:${NC}"
    echo -e "   tar -xvf crc-*.tar.xz"
    echo -e "   sudo cp crc-*/crc /usr/local/bin/"
    echo -e "   crc setup"
    echo
    echo -e "4. ${BLUE}Start the cluster:${NC}"
    echo -e "   crc start"
    echo
    echo -e "5. ${BLUE}Get login credentials:${NC}"
    echo -e "   crc console --credentials"
    echo
    echo -e "6. ${BLUE}Login as developer:${NC}"
    echo -e "   oc login -u developer https://api.crc.testing:6443"
    echo
    echo -e "${GREEN}Alternative: Simple Podman-based testing${NC}"
    echo -e "If you want to skip full OpenShift and just test the containers:"
    echo -e "  ./start-openshift.sh --podman-only"
    echo
}

# Function to check for clock synchronization issues
check_clock_sync() {
    echo -e "${BLUE}🕐 Checking CRC clock synchronization...${NC}"
    
    # Only check if CRC and oc are available
    if ! command -v crc &> /dev/null || ! command -v oc &> /dev/null; then
        return 0
    fi
    
    # Check if CRC is running
    local crc_status=$(crc status 2>/dev/null | grep "CRC VM:" | awk '{print $3}' || echo "Unknown")
    if [ "$crc_status" != "Running" ]; then
        return 0
    fi
    
    # Check for NodeClockNotSynchronising events
    local clock_alerts=$(oc get events --all-namespaces --field-selector reason=NodeClockNotSynchronising 2>/dev/null | wc -l || echo "0")
    
    if [ "$clock_alerts" -gt 1 ]; then  # Greater than 1 because header counts as 1
        echo -e "${YELLOW}⚠️  Clock synchronization issues detected!${NC}"
        echo -e "${CYAN}NodeClockNotSynchronising alerts found in cluster${NC}"
        echo
        
        if [ -f "$(dirname "$0")/fix-crc-clock.sh" ]; then
            read -p "Run automatic clock fix? [Y/n]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                echo -e "${BLUE}Running clock synchronization fix...${NC}"
                "$(dirname "$0")/fix-crc-clock.sh" --auto
                echo
            fi
        else
            echo -e "${YELLOW}To fix this issue, run:${NC}"
            echo -e "  crc stop && crc start"
            echo -e "${YELLOW}Or use the dedicated fix script if available${NC}"
            echo
        fi
    else
        echo -e "${GREEN}✅ Clock synchronization appears healthy${NC}"
    fi
}

# Function to test connection
test_connection() {
    echo -e "${BLUE}🔌 Testing OpenShift connection...${NC}"
    
    if oc status &> /dev/null; then
        echo -e "${GREEN}✅ Connected to OpenShift cluster${NC}"
        oc version
        echo
        echo -e "${BLUE}Current context:${NC}"
        oc whoami
        echo -e "${BLUE}Available projects:${NC}"
        oc projects
        return 0
    else
        echo -e "${RED}❌ Cannot connect to OpenShift cluster${NC}"
        return 1
    fi
}

# Function for podman-only mode
podman_only_mode() {
    echo -e "${BLUE}🐳 Setting up Podman-only testing environment${NC}"
    
    check_podman_desktop
    
    # Create network
    podman network create hpc-network 2>/dev/null || true
    
    # Build and run a simple HPC container for testing
    echo -e "${YELLOW}Building test container...${NC}"
    cd "$(dirname "$0")"
    podman build -t hpc-local-test -f containers/Containerfile.hpc-base ../..
    
    echo -e "${GREEN}✅ Podman environment ready${NC}"
    echo
    echo -e "${BLUE}To test your examples:${NC}"
    echo -e "  podman run -it --rm --network hpc-network hpc-local-test /bin/bash"
    echo
    echo -e "Inside the container you can run:"
    echo -e "  - cd examples/mpi && mpirun -np 2 ./mpi_ring"
    echo -e "  - cd examples/mpi_debugging && mpirun -np 2 ./mpi_deadlock"
    echo -e "  - python examples/ai_ml/distributed_training.py --epochs 2"
}

# Main execution
case "${1:-}" in
    --podman-only)
        podman_only_mode
        ;;
    --help|-h)
        echo "Usage: $0 [--podman-only] [--help]"
        echo "  --podman-only  Setup simple Podman environment without OpenShift"
        echo "  --help         Show this help message"
        exit 0
        ;;
    *)
        check_podman_desktop
        
        if test_connection; then
            echo -e "${GREEN}🎉 OpenShift cluster is ready!${NC}"
            
            # Check for clock synchronization issues
            check_clock_sync
            
            echo -e "You can now run: ./setup.sh"
        else
            echo -e "${YELLOW}⚠️  OpenShift cluster not accessible${NC}"
            start_openshift_local
            
            if ! test_connection; then
                provide_instructions
                echo
                echo -e "${BLUE}🔄 Alternative: Try Podman-only mode${NC}"
                echo -e "  ./start-openshift.sh --podman-only"
            else
                # Check clock sync after successful connection
                check_clock_sync
            fi
        fi
        ;;
esac
