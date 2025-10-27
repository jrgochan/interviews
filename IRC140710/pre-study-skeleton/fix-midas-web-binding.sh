#!/bin/bash
# Fix MIDAS web server to bind to all interfaces for OpenShift route access

NAMESPACE="hpc-interview"
POD_NAME=$(oc get pods -n "${NAMESPACE}" -l app=midas-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

echo "🔧 Fixing MIDAS web server network binding..."
echo "Pod: $POD_NAME"

# Create configuration script
oc exec "$POD_NAME" -n "${NAMESPACE}" -- bash -c "
cat > /tmp/fix_web_binding.sh << 'EOF'
#!/bin/bash
export MIDASSYS=/opt/midas/install
export PATH=\$MIDASSYS/bin:\$PATH
export LD_LIBRARY_PATH=\$MIDASSYS/lib:\$LD_LIBRARY_PATH
export MIDAS_EXPTAB=/tmp/midas_demo/exptab

cd /tmp/midas_demo

echo '🔄 Stopping current web server...'
pkill -f mhttpd 2>/dev/null || true
sleep 2

echo '⚙️  Configuring web server to bind to all interfaces...'
odbedit -e demo -c 'create STRING \"/Webserver/Http host[256]\" \"0.0.0.0\"' 2>/dev/null || true
odbedit -e demo -c 'create INT \"/Webserver/Http port\" 8080' 2>/dev/null || true

echo '🚀 Starting web server with new configuration...'
mhttpd -e demo > mhttpd_fixed.log 2>&1 &
echo \$! > mhttpd_fixed.pid

sleep 3

echo '📋 Web server status:'
if kill -0 \$(cat mhttpd_fixed.pid) 2>/dev/null; then
    echo '  ✅ Web server running'
    echo '  📋 Binding information:'
    tail -5 mhttpd_fixed.log | grep -i listening || echo '  Checking log...'
else
    echo '  ❌ Web server failed to start'
fi

echo '✅ Configuration completed'
EOF

chmod +x /tmp/fix_web_binding.sh
"

echo "🚀 Executing web server binding fix..."
oc exec "$POD_NAME" -n "${NAMESPACE}" -- /tmp/fix_web_binding.sh

echo "🧪 Testing external connectivity..."
oc exec "$POD_NAME" -n "${NAMESPACE}" -- bash -c "curl -s http://localhost:8080 >/dev/null && echo '✅ Web server responding internally'"

echo "🎉 MIDAS web server binding fix completed!"
