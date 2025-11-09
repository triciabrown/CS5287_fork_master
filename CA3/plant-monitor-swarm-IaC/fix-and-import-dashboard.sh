#!/bin/bash
# Fix and Import Grafana Dashboard with proper data source configuration

MANAGER_IP="18.219.157.100"
GRAFANA_URL="http://${MANAGER_IP}:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

echo "============================================"
echo "  Grafana Dashboard Import Fix"
echo "============================================"
echo ""

# Step 1: Check Grafana accessibility
echo "[1/4] Checking Grafana accessibility..."
HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "${GRAFANA_URL}/api/health")
if [ "$HEALTH_CHECK" != "200" ]; then
    echo "❌ ERROR: Grafana is not accessible at ${GRAFANA_URL}"
    echo "   Please verify the service is running: docker service ls | grep grafana"
    exit 1
fi
echo "✅ Grafana is accessible"
echo ""

# Step 2: Get Prometheus data source UID
echo "[2/4] Getting Prometheus data source UID..."
DATASOURCES=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" "${GRAFANA_URL}/api/datasources")
PROMETHEUS_UID=$(echo "$DATASOURCES" | grep -o '"uid":"[^"]*"' | grep -A1 '"type":"prometheus"' | head -1 | cut -d'"' -f4)

if [ -z "$PROMETHEUS_UID" ]; then
    echo "⚠️  Prometheus data source not found. Creating it..."
    
    # Create Prometheus data source
    CREATE_DS=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
        -d '{
          "name": "Prometheus",
          "type": "prometheus",
          "url": "http://prometheus:9090",
          "access": "proxy",
          "isDefault": true,
          "jsonData": {
            "timeInterval": "5s"
          }
        }' \
        "${GRAFANA_URL}/api/datasources")
    
    PROMETHEUS_UID=$(echo "$CREATE_DS" | grep -o '"uid":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$PROMETHEUS_UID" ]; then
        echo "✅ Created Prometheus data source (UID: ${PROMETHEUS_UID})"
    else
        echo "❌ Failed to create Prometheus data source"
        echo "   Response: $CREATE_DS"
        exit 1
    fi
else
    echo "✅ Found Prometheus data source (UID: ${PROMETHEUS_UID})"
fi
echo ""

# Step 3: Fix dashboard JSON with proper data source references
echo "[3/4] Fixing dashboard JSON with data source references..."

# Read the original dashboard
ORIGINAL_DASHBOARD=$(cat configs/grafana-plant-monitoring-dashboard.json)

# Create a properly formatted dashboard with datasource UIDs
cat > /tmp/fixed-dashboard.json << EOF
{
  "dashboard": $(echo "$ORIGINAL_DASHBOARD" | jq --arg uid "$PROMETHEUS_UID" '
    .dashboard |
    # Add datasource to each panel target
    .panels |= map(
      if .targets then
        .targets |= map(. + {"datasource": {"type": "prometheus", "uid": $uid}})
      else . end
    )
  '),
  "overwrite": true,
  "message": "CA3 Plant Monitoring Dashboard - Fixed Import"
}
EOF

echo "✅ Dashboard JSON fixed with Prometheus UID: ${PROMETHEUS_UID}"
echo ""

# Step 4: Import the dashboard
echo "[4/4] Importing dashboard to Grafana..."
IMPORT_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -d @/tmp/fixed-dashboard.json \
    "${GRAFANA_URL}/api/dashboards/db")

DASHBOARD_UID=$(echo "$IMPORT_RESPONSE" | grep -o '"uid":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$DASHBOARD_UID" ]; then
    echo "✅ Dashboard imported successfully!"
    echo ""
    echo "============================================"
    echo "  Dashboard is ready to view!"
    echo "============================================"
    echo ""
    echo "🌐 Access URL: ${GRAFANA_URL}/d/${DASHBOARD_UID}/ca3-plant-monitoring-system"
    echo "🔑 Login: ${GRAFANA_USER} / ${GRAFANA_PASS}"
    echo ""
    echo "📊 The dashboard should now show all 11 panels with live data"
    echo "   Wait 30 seconds for data to populate if panels are empty"
    echo ""
else
    echo "❌ Dashboard import failed"
    echo "Response: $IMPORT_RESPONSE"
    echo ""
    echo "Manual import fallback:"
    echo "1. Open: ${GRAFANA_URL}"
    echo "2. Login: ${GRAFANA_USER} / ${GRAFANA_PASS}"
    echo "3. Click '+' → Import"
    echo "4. Upload: /tmp/fixed-dashboard.json"
    echo "5. Select 'Prometheus' data source"
    echo "6. Click 'Import'"
fi

# Cleanup
rm -f /tmp/fixed-dashboard.json
