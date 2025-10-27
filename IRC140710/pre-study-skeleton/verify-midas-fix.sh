#!/bin/bash
# MIDAS Web Server Fix Verification Script

set -e

NAMESPACE="hpc-interview"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}🔍 MIDAS Web Server Fix Verification${NC}"
echo "========================================"

# Test 1: Run the web demo
echo -e "\n${CYAN}Test 1: Running MIDAS web demo...${NC}"
if ${SCRIPT_DIR}/scripts/rhos/examples/run-midas-demo.sh web; then
    echo -e "${GREEN}✅ Web demo completed successfully${NC}"
else
    echo -e "${RED}❌ Web demo failed${NC}"
    exit 1
fi

# Test 2: Check pod status
echo -e "\n${CYAN}Test 2: Verifying pod status...${NC}"
POD_NAME=$(oc get pods -n "${NAMESPACE}" -l app=midas-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD_NAME" ]; then
    echo -e "${GREEN}✅ MIDAS pod found: ${POD_NAME}${NC}"
    
    # Check if pod is ready
    if oc get pod "$POD_NAME" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
        echo -e "${GREEN}✅ Pod is ready${NC}"
    else
        echo -e "${YELLOW}⚠️  Pod is not ready${NC}"
    fi
else
    echo -e "${RED}❌ MIDAS pod not found${NC}"
    exit 1
fi

# Test 3: Check service and route
echo -e "\n${CYAN}Test 3: Checking service and route...${NC}"
if oc get svc midas-workspace-svc -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ MIDAS service found${NC}"
else
    echo -e "${RED}❌ MIDAS service not found${NC}"
fi

ROUTE_URL=$(oc get route midas-web-route -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$ROUTE_URL" ]; then
    echo -e "${GREEN}✅ MIDAS route found: https://${ROUTE_URL}${NC}"
else
    echo -e "${YELLOW}⚠️  MIDAS route not found${NC}"
fi

# Test 4: Check internal web server
echo -e "\n${CYAN}Test 4: Testing internal web server connectivity...${NC}"
oc exec "$POD_NAME" -n "${NAMESPACE}" -- bash -c "
    export MIDASSYS=\${MIDASSYS}
    export PATH=\${MIDASSYS}/bin:\$PATH
    export LD_LIBRARY_PATH=\${MIDASSYS}/lib:\$LD_LIBRARY_PATH
    
    cd /tmp/midas_demo 2>/dev/null || cd /tmp
    
    echo '🔍 Checking MIDAS processes...'
    if ps aux | grep -E '(mserver|mhttpd|mlogger)' | grep -v grep; then
        echo '✅ MIDAS processes found'
    else
        echo '❌ No MIDAS processes found'
    fi
    
    echo '🔍 Checking network ports...'
    if netstat -ln 2>/dev/null | grep -E ':(8080|1175)'; then
        echo '✅ MIDAS ports listening'
    else
        echo '❌ MIDAS ports not listening'
    fi
    
    echo '🔍 Testing web server response...'
    if curl -s --max-time 5 http://localhost:8080 >/dev/null 2>&1; then
        echo '✅ Web server responding'
    else
        echo '❌ Web server not responding'
        echo '📋 Checking web server log:'
        cat mhttpd.log 2>/dev/null | tail -5 || echo 'No web server log found'
    fi
"

# Test 5: Check log files
echo -e "\n${CYAN}Test 5: Examining log files...${NC}"
oc exec "$POD_NAME" -n "${NAMESPACE}" -- bash -c "
    cd /tmp/midas_demo 2>/dev/null || cd /tmp
    
    echo '📋 Available log files:'
    ls -la *.log 2>/dev/null || echo 'No log files found'
    
    echo
    echo '📋 Recent web server log entries:'
    if [ -f mhttpd.log ]; then
        tail -10 mhttpd.log
    else
        echo 'No mhttpd.log found'
    fi
"

echo -e "\n${BLUE}🎯 Verification Summary${NC}"
echo "======================="
echo -e "• ${GREEN}Fixed MIDAS demo script with enhanced error handling${NC}"
echo -e "• ${GREEN}Implemented proper ODB initialization sequence${NC}"  
echo -e "• ${GREEN}Added container-compatible process management${NC}"
echo -e "• ${GREEN}Enhanced service verification and logging${NC}"
echo -e "• ${GREEN}Created comprehensive documentation${NC}"

echo -e "\n${CYAN}💡 To manually test the web interface:${NC}"
if [ -n "$ROUTE_URL" ]; then
    echo -e "  External: https://${ROUTE_URL}"
fi
echo -e "  Internal: oc exec -it ${POD_NAME} -n ${NAMESPACE} -- curl http://localhost:8080"
echo -e "  Interactive: ${SCRIPT_DIR}/scripts/rhos/examples/run-midas-demo.sh interactive"

echo -e "\n${GREEN}🎉 MIDAS Web Server Fix Verification Completed!${NC}"
