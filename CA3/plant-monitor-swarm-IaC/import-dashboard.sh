#!/bin/bash
# Import Grafana Dashboard via API

GRAFANA_URL="http://18.219.157.100:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"
DASHBOARD_FILE="/home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC/configs/grafana-plant-monitoring-dashboard.json"

echo "Importing Grafana dashboard..."

# Read the dashboard JSON
DASHBOARD_JSON=$(cat "$DASHBOARD_FILE")

# Create the import payload
IMPORT_PAYLOAD=$(cat <<EOF
{
  "dashboard": $DASHBOARD_JSON,
  "overwrite": true,
  "inputs": [
    {
      "name": "DS_PROMETHEUS",
      "type": "datasource",
      "pluginId": "prometheus",
      "value": "Prometheus"
    }
  ]
}
EOF
)

# Import via API
curl -X POST \
  -H "Content-Type: application/json" \
  -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  -d "$IMPORT_PAYLOAD" \
  "${GRAFANA_URL}/api/dashboards/import"

echo ""
echo "✅ Dashboard imported!"
echo "Access it at: ${GRAFANA_URL}/dashboards"
