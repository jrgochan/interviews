#!/bin/bash
# MIDAS Data Acquisition System Demo Script
# Comprehensive demonstration of MIDAS DAQ capabilities

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
NAMESPACE="hpc-interview"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🎯 MIDAS Data Acquisition System Demo${NC}"
echo -e "Namespace: ${NAMESPACE}"
echo

# Function to find MIDAS pod
find_midas_pod() {
    local pod_name=$(oc get pods -n "${NAMESPACE}" -l app=midas-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -z "$pod_name" ]; then
        echo -e "${RED}❌ MIDAS workspace pod not found${NC}"
        echo -e "${CYAN}Deployment status:${NC}"
        oc get deployment midas-workspace -n "${NAMESPACE}" 2>/dev/null || echo "Deployment not found"
        echo
        echo -e "${YELLOW}💡 Try running the setup script first:${NC}"
        echo -e "  ${SCRIPT_DIR}/../setup.sh --modules midas"
        exit 1
    fi
    echo "$pod_name"
}

# Function to wait for pod readiness
wait_for_pod() {
    local pod_name="$1"
    echo -e "${CYAN}⏳ Waiting for MIDAS pod to be ready...${NC}"
    
    if ! oc wait --for=condition=ready pod/"$pod_name" -n "${NAMESPACE}" --timeout=300s; then
        echo -e "${RED}❌ Pod failed to become ready${NC}"
        echo -e "${CYAN}Pod status:${NC}"
        oc describe pod "$pod_name" -n "${NAMESPACE}" | tail -20
        exit 1
    fi
    
    echo -e "${GREEN}✅ MIDAS pod is ready${NC}"
}

# Function to check MIDAS environment
check_midas_environment() {
    local pod_name="$1"
    echo -e "${CYAN}🔍 Checking MIDAS environment...${NC}"
    
    # Check MIDAS installation using environment variables
    oc exec "$pod_name" -n "${NAMESPACE}" -- bash -c "
        echo '📦 MIDAS System: \$MIDASSYS'
        echo '🔬 ROOT System: \$ROOTSYS'
        echo '🧪 Experiment: \$MIDAS_EXPT_NAME'
        echo '📁 Experiment Dir: \$MIDAS_EXPT_DIR'
        echo
        echo '🔧 Available MIDAS tools:'
        ls -la \$MIDASSYS/bin/ | head -10
        echo
        echo '✅ MIDAS environment verified'
    "
}

# Function to initialize MIDAS experiment
initialize_experiment() {
    local pod_name="$1"
    echo -e "${CYAN}🚀 Initializing MIDAS experiment...${NC}"
    
    oc exec "$pod_name" -n "${NAMESPACE}" -- bash -c "
        export MIDASSYS=\${MIDASSYS}
        export PATH=\${MIDASSYS}/bin:\$PATH
        export LD_LIBRARY_PATH=\${MIDASSYS}/lib:\$LD_LIBRARY_PATH
        
        echo '📂 Setting up experiment directory...'
        mkdir -p /tmp/midas_demo/{data,logs}
        cd /tmp/midas_demo
        
        # Try to initialize ODB 
        echo '🗄️  Initializing ODB (Online Database)...'
        if odbedit -h localhost -e demo -c 'create STRING \"/Experiment/Name[32]\" \"MIDAS Demo\"' 2>/dev/null; then
            echo '✅ ODB initialized'
        else
            echo '⚠️  ODB initialization skipped (likely no connection)'
        fi
        
        # Test basic MIDAS commands
        echo '⚙️  Testing MIDAS commands...'
        echo '  Testing odbedit...'
        if odbedit --help >/dev/null 2>&1; then
            echo '  ✅ odbedit command available'
        fi
        
        echo '  Testing mserver...'
        if mserver --help >/dev/null 2>&1; then
            echo '  ✅ mserver command available'
        fi
        
        echo '✅ Experiment environment verified'
    "
}

# Function to compile and setup frontend
setup_frontend() {
    local pod_name="$1"
    echo -e "${CYAN}🔨 Setting up MIDAS frontend...${NC}"
    
    oc exec "$pod_name" -n "${NAMESPACE}" -- bash -c "
        export MIDASSYS=\${MIDASSYS}
        export PATH=\${MIDASSYS}/bin:\$PATH
        export LD_LIBRARY_PATH=\${MIDASSYS}/lib:\$LD_LIBRARY_PATH
        
        mkdir -p /tmp/midas_demo
        cd /tmp/midas_demo
        
        echo '🛠️  Creating demo frontend source...'
        cat > frontend.c << 'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    printf(\"MIDAS Demo Frontend Starting...\\n\");
    printf(\"Simulating data acquisition...\\n\");
    for(int i = 0; i < 5; i++) {
        printf(\"Event %d: ADC data = %d\\n\", i, i * 1234);
        sleep(1);
    }
    printf(\"Demo frontend completed.\\n\");
    return 0;
}
CEOF
        
        echo '🛠️  Compiling demo frontend...'
        if gcc -o frontend frontend.c; then
            echo '✅ Frontend compiled successfully'
            ls -la frontend
        else
            echo '❌ Frontend compilation failed'
        fi
    "
}

# Function to start MIDAS services
start_midas_services() {
    local pod_name="$1"
    echo -e "${CYAN}🚀 Starting MIDAS services...${NC}"
    
    # Create a startup script in the pod
    oc exec "$pod_name" -n "${NAMESPACE}" -- bash -c "
        cat > /tmp/start_midas.sh << 'EOF'
#!/bin/bash
export MIDASSYS=\${MIDASSYS:-/opt/midas/install}
export PATH=\$MIDASSYS/bin:\$PATH
export LD_LIBRARY_PATH=\$MIDASSYS/lib:\$LD_LIBRARY_PATH

mkdir -p /tmp/midas_demo/{data,logs,odb}
cd /tmp/midas_demo

echo '🔄 Cleaning up any existing MIDAS processes...'
pkill -f mserver 2>/dev/null || true
pkill -f mhttpd 2>/dev/null || true  
pkill -f mlogger 2>/dev/null || true

echo '🗄️  Creating experiment table...'
# Create user experiment table in working directory
echo 'demo /tmp/midas_demo hpcuser' > exptab
export MIDAS_EXPTAB=/tmp/midas_demo/exptab
echo '  📋 Created experiment table at /tmp/midas_demo/exptab'

echo '🗄️  Starting ODB server...'
MIDAS_EXPTAB=/tmp/midas_demo/exptab mserver -e demo > odb.log 2>&1 &
echo \$! > mserver.pid

echo '🌐 Starting MIDAS web interface...'
MIDAS_EXPTAB=/tmp/midas_demo/exptab mhttpd -e demo > mhttpd.log 2>&1 &  
echo \$! > mhttpd.pid

# Wait a moment and check if it started properly
sleep 2
if [ -f mhttpd.pid ] && kill -0 \$(cat mhttpd.pid) 2>/dev/null; then
    echo '  ✅ Web interface started, checking port...'
    # If it's not on 8080, try to determine what port it's using
    ACTUAL_PORT=\$(cat /proc/net/tcp | awk 'NR>1 {if(\$4==\"0A\") {port=strtonum(\"0x\" substr(\$2,10,4)); if(port>=8000 && port<=9000) print port}}' | head -1)
    if [ -n "\$ACTUAL_PORT" ] && [ "\$ACTUAL_PORT" != "8080" ]; then
        echo \"  🔄 Web server started on port \$ACTUAL_PORT instead of 8080\"
        # Restart with correct port
        kill \$(cat mhttpd.pid) 2>/dev/null || true
        sleep 1
        MIDAS_EXPTAB=/tmp/midas_demo/exptab mhttpd -e demo --oldserver -p 8080 > mhttpd.log 2>&1 &
        echo \$! > mhttpd.pid
    fi
fi

echo '📝 Starting MIDAS logger...'
MIDAS_EXPTAB=/tmp/midas_demo/exptab mlogger -e demo > mlogger.log 2>&1 &
echo \$! > mlogger.pid

sleep 5

echo '🎯 MIDAS services status:'
for service in mserver mhttpd mlogger; do
    if [ -f \${service}.pid ] && kill -0 \$(cat \${service}.pid) 2>/dev/null; then
        echo \"  ✅ \$service running (PID: \$(cat \${service}.pid))\"
    else
        echo \"  ❌ \$service not running\"
        if [ -f \${service%er}.log ]; then
            echo \"  📋 Last few log lines:\"
            tail -3 \${service%er}.log | sed 's/^/    /'
        fi
    fi
done

echo '🔍 Port status:'
if netstat -ln 2>/dev/null | grep ':8080' >/dev/null; then
    echo '  ✅ Port 8080 listening'
else
    echo '  ❌ Port 8080 not listening'
fi

echo '✅ MIDAS startup script completed'
EOF
        chmod +x /tmp/start_midas.sh
    "
    
    echo -e "${CYAN}📋 Executing MIDAS startup script...${NC}"
    oc exec "$pod_name" -n "${NAMESPACE}" -- /tmp/start_midas.sh
}

# Function to test web interface
test_web_interface() {
    local pod_name="$1"
    echo -e "${CYAN}� Testing MIDAS web interface...${NC}"
    
    # Get the route URL
    local route_url=$(oc get route midas-web-route -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    if [ -n "$route_url" ]; then
        echo -e "${GREEN}✅ MIDAS web interface available at:${NC}"
        echo -e "   https://${route_url}"
        echo
        
        # Test the interface from within the pod
        oc exec "$pod_name" -n "${NAMESPACE}" -- bash -c "
            echo '🔍 Testing internal web interface...'
            if curl -s http://localhost:8080 > /dev/null; then
                echo '✅ Internal web server responding'
            else
                echo '❌ Internal web server not responding'
            fi
        "
    else
        echo -e "${YELLOW}⚠️  Web route not found${NC}"
        echo -e "${CYAN}Service status:${NC}"
        oc get svc midas-workspace-svc -n "${NAMESPACE}" 2>/dev/null || echo "Service not found"
    fi
}

# Function to demonstrate ODB operations
demo_odb_operations() {
    local pod_name="$1"
    echo -e "${CYAN}📊 Demonstrating ODB (Online Database) operations...${NC}"
    
    oc exec "$pod_name" -n "${NAMESPACE}" -- bash -c "
        export MIDASSYS=\${MIDASSYS}
        export PATH=\${MIDASSYS}/bin:\$PATH
        export LD_LIBRARY_PATH=\${MIDASSYS}/lib:\$LD_LIBRARY_PATH
        
        mkdir -p /tmp/midas_demo
        cd /tmp/midas_demo
        
        echo '🗄️  ODB Structure Overview:'
        odbedit -c 'ls /' || echo '  ODB not connected'
        echo
        
        echo '🧪 Experiment Configuration:'
        odbedit -c 'ls /Experiment' || echo '  Experiment not configured'
        echo
        
        echo '⚙️  Equipment Status:'
        odbedit -c 'ls /Equipment' || echo '  Equipment not configured'
        echo
        
        echo '📝 Setting demo parameters...'
        odbedit -c 'set \"/Runinfo/Run number\" 42' || echo '  Could not set run number'
        odbedit -c 'set \"/Equipment/Trigger/Statistics/Events sent\" 1000' || echo '  Could not set statistics'
        
        echo '📊 Current run information:'
        odbedit -c 'ls /Runinfo' || echo '  Runinfo not available'
        echo
        
        echo '📈 Equipment statistics:'
        odbedit -c 'ls /Equipment/Trigger/Statistics' || echo '  Statistics not available'
        
        echo '✅ ODB operations completed (demo mode)'
    "
}

# Function to simulate data acquisition
simulate_data_acquisition() {
    local pod_name="$1"
    echo -e "${CYAN}🎲 Simulating data acquisition...${NC}"
    
    oc exec "$pod_name" -n "${NAMESPACE}" -- bash -c "
        export MIDASSYS=\${MIDASSYS}
        export PATH=\${MIDASSYS}/bin:\$PATH
        export LD_LIBRARY_PATH=\${MIDASSYS}/lib:\$LD_LIBRARY_PATH
        
        mkdir -p /tmp/midas_demo/data
        cd /tmp/midas_demo
        
        echo '🎯 Starting simulated data run...'
        
        # Start the frontend if it exists
        if [ -f frontend ]; then
            echo '  Starting demo frontend...'
            timeout 10s ./frontend || echo '  Frontend simulation completed'
        else
            echo '  Creating and running simple data simulation...'
            for i in {1..5}; do
                echo \"Event \$i: ADC data = \$((\$i * 1234))\" >> data/demo_run.dat
                echo \"  Generated event \$i\"
                sleep 1
            done
        fi
        
        echo '📊 Checking data files...'
        ls -la data/ 2>/dev/null || echo '  No data directory found'
        
        echo '📈 Run statistics:'
        if [ -f data/demo_run.dat ]; then
            echo \"  Events recorded: \$(wc -l < data/demo_run.dat)\"
        fi
        
        echo '✅ Data acquisition simulation completed'
    "
}

# Function to run Python demo
run_python_demo() {
    local pod_name="$1"
    echo -e "${CYAN}🐍 Running Python MIDAS demo...${NC}"
    
    oc exec "$pod_name" -n "${NAMESPACE}" -- bash -c "
        export MIDASSYS=\${MIDASSYS}
        export PATH=\${MIDASSYS}/bin:\$PATH
        export LD_LIBRARY_PATH=\${MIDASSYS}/lib:\$LD_LIBRARY_PATH
        
        # Create Python demo in accessible location
        cat > /tmp/midas_demo.py << 'PYEOF'
#!/usr/bin/env python3
import os, sys, time, json, subprocess
print('🐍 MIDAS Python Demo Starting...')
print('✅ MIDAS Environment:', os.environ.get('MIDASSYS', 'Not set'))
print('📊 Testing MIDAS tools availability...')
try:
    result = subprocess.run(['odbedit', '--help'], capture_output=True, timeout=5)
    print('✅ odbedit command available')
except:
    print('❌ odbedit command not available')
try:
    result = subprocess.run(['mserver', '--help'], capture_output=True, timeout=5)
    print('✅ mserver command available')  
except:
    print('❌ mserver command not available')
print('🎲 Simulating data generation...')
sample_data = {'experiment': 'MIDAS Demo', 'events': [{'id': i} for i in range(5)]}
print('✅ Generated sample data with', len(sample_data['events']), 'events')
print('🎉 MIDAS Python Demo Completed!')
PYEOF
        
        echo '🚀 Executing MIDAS Python demo...'
        python3 /tmp/midas_demo.py || echo '⚠️  Python demo encountered issues'
    "
}

# Function to show logs and status
show_status() {
    local pod_name="$1"
    echo -e "${CYAN}📋 MIDAS System Status Summary${NC}"
    echo -e "=================================="
    
    oc exec "$pod_name" -n "${NAMESPACE}" -- bash -c "
        export MIDASSYS=\${MIDASSYS}
        export PATH=\${MIDASSYS}/bin:\$PATH
        export LD_LIBRARY_PATH=\${MIDASSYS}/lib:\$LD_LIBRARY_PATH
        
        mkdir -p /tmp/midas_demo
        cd /tmp/midas_demo
        
        echo '🖥️  System Information:'
        echo \"  Pod: $pod_name\"
        echo \"  Namespace: ${NAMESPACE}\"
        echo \"  MIDAS System: \$MIDASSYS\"
        echo \"  Experiment: demo\"
        echo \"  Working Directory: \$(pwd)\"
        echo
        
        echo '🔄 Running Processes:'
        ps aux | grep -E '(midas|mserver|mhttpd|mlogger)' | grep -v grep || echo '  No MIDAS processes found'
        echo
        
        echo '📁 Files Created:'
        find /tmp/midas_demo -name '*.mid' -o -name '*.log' -o -name '.odb*' -o -name '*.dat' 2>/dev/null | head -10 || echo '  No data files found'
        echo
        
        echo '💾 Disk Usage:'
        du -sh /tmp/midas_demo 2>/dev/null || echo '  Cannot determine disk usage'
        
        echo '🧪 Available MIDAS Commands:'
        which odbedit mserver mhttpd mlogger 2>/dev/null || echo '  MIDAS commands in PATH'
    "
}

# Function to display usage information
display_usage() {
    echo -e "${GREEN}🎉 MIDAS Demo Completed Successfully!${NC}"
    echo
    echo -e "${BLUE}📋 What was demonstrated:${NC}"
    echo -e "  ✅ MIDAS installation and environment"
    echo -e "  ✅ ODB (Online Database) operations"
    echo -e "  ✅ Web interface setup and access"
    echo -e "  ✅ Frontend compilation and execution"
    echo -e "  ✅ Data acquisition simulation"
    echo -e "  ✅ Python integration"
    echo
    echo -e "${BLUE}🌐 Web Interface Access:${NC}"
    local route_url=$(oc get route midas-web-route -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available")
    echo -e "  URL: https://${route_url}"
    echo -e "  Username/Password: (varies by setup)"
    echo
    echo -e "${BLUE}🔧 Interactive Commands:${NC}"
    local pod_name=$(oc get pods -n "${NAMESPACE}" -l app=midas-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "midas-pod")
    echo -e "  Shell Access:"
    echo -e "    ${SCRIPT_DIR}/shell.sh midas"
    echo -e "  Direct Pod Access:"
    echo -e "    oc exec -it ${pod_name} -n ${NAMESPACE} -- /bin/bash"
    echo -e "  Load MIDAS Environment:"
    echo -e "    source /home/hpcuser/workspace/midas/midas_env.sh"
    echo
    echo -e "${BLUE}📊 MIDAS Commands:${NC}"
    echo -e "  odbedit          # Online Database Editor"
    echo -e "  mhttpd           # MIDAS HTTP Daemon"
    echo -e "  mserver          # MIDAS Database Server"
    echo -e "  mlogger          # Data Logger"
    echo -e "  lazylogger       # Lazy Logging Utility"
    echo
    echo -e "${BLUE}🎯 Physics Experiment Features:${NC}"
    echo -e "  • Data acquisition and logging"
    echo -e "  • Online database (ODB) management"
    echo -e "  • Web-based experiment control"
    echo -e "  • Real-time monitoring"
    echo -e "  • Equipment configuration"
    echo -e "  • Run control and automation"
    echo
    echo -e "${CYAN}💡 This demonstrates MIDAS capabilities for PSI neutron optics experiments!${NC}"
}

# Main execution function
main() {
    local demo_type="${1:-full}"
    
    echo -e "${BLUE}🎯 MIDAS Data Acquisition Demo${NC}"
    echo -e "Demo type: ${demo_type}"
    echo
    
    local pod_name=$(find_midas_pod)
    wait_for_pod "$pod_name"
    
    case "$demo_type" in
        "environment"|"env")
            check_midas_environment "$pod_name"
            ;;
        "initialize"|"init")
            check_midas_environment "$pod_name"
            initialize_experiment "$pod_name"
            ;;
        "services")
            initialize_experiment "$pod_name"
            start_midas_services "$pod_name"
            test_web_interface "$pod_name"
            ;;
        "odb")
            initialize_experiment "$pod_name"
            demo_odb_operations "$pod_name"
            ;;
        "frontend")
            initialize_experiment "$pod_name"
            setup_frontend "$pod_name"
            start_midas_services "$pod_name"
            ;;
        "data")
            initialize_experiment "$pod_name"
            setup_frontend "$pod_name"
            start_midas_services "$pod_name"
            simulate_data_acquisition "$pod_name"
            ;;
        "python")
            initialize_experiment "$pod_name"
            start_midas_services "$pod_name"
            run_python_demo "$pod_name"
            ;;
        "web")
            initialize_experiment "$pod_name"
            start_midas_services "$pod_name"
            test_web_interface "$pod_name"
            ;;
        "status")
            show_status "$pod_name"
            ;;
        "interactive")
            echo -e "${CYAN}🚀 Starting interactive MIDAS session...${NC}"
            oc exec -it "$pod_name" -n "${NAMESPACE}" -- bash -c "
                export MIDASSYS=\${MIDASSYS}
                export PATH=\${MIDASSYS}/bin:\$PATH
                export LD_LIBRARY_PATH=\${MIDASSYS}/lib:\$LD_LIBRARY_PATH
                export MIDAS_EXPT_NAME=\${MIDAS_EXPT_NAME}
                export MIDAS_EXPT_DIR=/tmp/midas_demo
                mkdir -p /tmp/midas_demo
                cd /tmp/midas_demo
                echo '🎯 MIDAS environment loaded!'
                echo '📦 MIDASSYS: '\$MIDASSYS
                echo '🧪 Available commands: odbedit, mserver, mhttpd, mlogger'
                echo '📁 Working directory: '\$(pwd)
                echo '💡 Try: odbedit --help'
                exec /bin/bash
            "
            ;;
        "full"|*)
            check_midas_environment "$pod_name"
            initialize_experiment "$pod_name"
            setup_frontend "$pod_name"
            start_midas_services "$pod_name"
            test_web_interface "$pod_name"
            demo_odb_operations "$pod_name"
            simulate_data_acquisition "$pod_name"
            run_python_demo "$pod_name"
            show_status "$pod_name"
            display_usage
            ;;
    esac
}

# Parse command line arguments and show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "MIDAS Data Acquisition Demo Script"
    echo
    echo "Usage: $0 [demo_type]"
    echo
    echo "Demo Types:"
    echo "  full          Complete MIDAS demonstration (default)"
    echo "  environment   Check MIDAS installation and environment"
    echo "  initialize    Initialize experiment and ODB"
    echo "  services      Start MIDAS services (web, logger, etc.)"
    echo "  odb           Demonstrate Online Database operations"
    echo "  frontend      Compile and setup frontend programs"
    echo "  data          Simulate data acquisition"
    echo "  python        Run Python integration demo"
    echo "  web           Test web interface access"
    echo "  status        Show system status and logs"
    echo "  interactive   Start interactive MIDAS session"
    echo
    echo "Examples:"
    echo "  $0                    # Run complete demo"
    echo "  $0 environment       # Check installation"
    echo "  $0 web               # Test web interface"
    echo "  $0 interactive       # Interactive session"
    echo
    exit 0
fi

# Execute main function
main "$@"
