#!/bin/bash
# Final MIDAS web server fix - make it accessible externally

NAMESPACE="hpc-interview"
POD_NAME=$(oc get pods -n "${NAMESPACE}" -l app=midas-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

echo "🎯 Final MIDAS Web Server Fix"
echo "Pod: $POD_NAME"

# Create the ultimate fix script
oc exec "$POD_NAME" -n "${NAMESPACE}" -- bash -c "
cat > /tmp/ultimate_midas_fix.sh << 'EOF'
#!/bin/bash
export MIDASSYS=/opt/midas/install
export PATH=\$MIDASSYS/bin:\$PATH
export LD_LIBRARY_PATH=\$MIDASSYS/lib:\$LD_LIBRARY_PATH
export MIDAS_EXPTAB=/tmp/midas_demo/exptab

cd /tmp/midas_demo

echo '🔄 Stopping all web servers...'
pkill -f mhttpd 2>/dev/null || true
sleep 3

echo '⚙️ Configuring ODB for external access...'
odbedit -e demo -c 'create STRING \"/Webserver/Http host[256]\" \"0.0.0.0\"' 2>/dev/null || odbedit -e demo -c 'set \"/Webserver/Http host\" \"0.0.0.0\"' 2>/dev/null || true
odbedit -e demo -c 'create UINT32 \"/Webserver/Http port\" 8080' 2>/dev/null || odbedit -e demo -c 'set \"/Webserver/Http port\" 8080' 2>/dev/null || true

echo '🚀 Starting web server for external access...'
# Try mongoose web server with explicit binding
mhttpd -e demo --http 8080 --no-hostlist > mhttpd_external.log 2>&1 &
WEB_PID=\$!
sleep 4

# Check if it worked, if not try old server
if ! kill -0 \$WEB_PID 2>/dev/null; then
    echo '  🔄 Trying old server mode...'
    mhttpd -e demo --oldserver -p 8080 > mhttpd_external.log 2>&1 &
    WEB_PID=\$!
    sleep 3
fi

echo '📊 Web server status:'
if kill -0 \$WEB_PID 2>/dev/null; then
    echo \"  ✅ Web server running (PID: \$WEB_PID)\"
    echo '  📋 Binding information:'
    tail -10 mhttpd_external.log | grep -i listening || echo '  Check log manually'
    
    echo '  🔍 Port check:'
    if cat /proc/net/tcp | grep -q ':1F90.*0A'; then
        echo '  ✅ Port 8080 listening'
    else
        echo '  ❌ Port 8080 not found'
    fi
else
    echo '  ❌ Web server failed to start'
    echo '  📋 Error log:'
    tail -5 mhttpd_external.log
fi

echo '✅ Ultimate fix completed'
EOF

chmod +x /tmp/ultimate_midas_fix.sh
"

echo "🚀 Executing ultimate MIDAS web fix..."
oc exec "$POD_NAME" -n "${NAMESPACE}" -- /tmp/ultimate_midas_fix.sh

echo
echo "🧪 Final verification..."
oc exec "$POD_NAME" -n "${NAMESPACE}" -- bash -c "cd /tmp/midas_demo; ps aux | grep mhttpd | grep -v grep; echo '---'; curl -s http://localhost:8080 >/dev/null && echo '✅ Internal web server working' || echo '❌ Internal web server not responding'"

echo "🎉 MIDAS web server fix process completed!"
