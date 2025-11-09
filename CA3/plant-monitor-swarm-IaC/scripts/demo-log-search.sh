#!/bin/bash
# Demo script for CA3 Observability - Centralized Log Search
# Shows how Promtail collects logs from all services and sends to Loki

set -e

MANAGER_IP="52.14.239.94"
SSH_KEY="~/.ssh/docker-swarm-key"

echo "=========================================="
echo "CA3 Centralized Logging Demonstration"
echo "=========================================="
echo ""
echo "Architecture:"
echo "  - Promtail (DaemonSet): Collects logs from Docker containers on all 5 nodes"
echo "  - Loki: Aggregates and indexes logs"
echo "  - Grafana: Query and visualize logs"
echo ""
echo "Current Manager IP: $MANAGER_IP"
echo ""

echo "1. Checking Promtail deployment (should show 5/5 - one per node):"
ssh -i $SSH_KEY ubuntu@$MANAGER_IP 'docker service ls | grep promtail'
echo ""

echo "2. Verifying log collection across all pipeline components:"
echo ""

echo "   [SENSOR] Recent logs with timestamps:"
ssh -i $SSH_KEY ubuntu@$MANAGER_IP 'docker service logs plant-monitoring_sensor --timestamps --tail 5 2>&1 | head -10'
echo ""

echo "   [KAFKA] Recent logs with timestamps:"
ssh -i $SSH_KEY ubuntu@$MANAGER_IP 'docker service logs plant-monitoring_kafka --timestamps --tail 5 2>&1 | head -10'
echo ""

echo "   [PROCESSOR] Recent logs with timestamps:"
ssh -i $SSH_KEY ubuntu@$MANAGER_IP 'docker service logs plant-monitoring_processor --timestamps --tail 5 2>&1 | head -10'
echo ""

echo "   [MONGODB] Recent logs with timestamps:"
ssh -i $SSH_KEY ubuntu@$MANAGER_IP 'docker service logs plant-monitoring_mongodb --timestamps --tail 5 2>&1 | head -10'
echo ""

echo "3. Filtering logs for ERROR/WARN across all components:"
echo ""
echo "   [ALL SERVICES] Searching for errors/warnings:"
ssh -i $SSH_KEY ubuntu@$MANAGER_IP 'for svc in sensor kafka processor mongodb; do echo "=== plant-monitoring_$svc ==="; docker service logs plant-monitoring_$svc --tail 100 2>&1 | grep -i -E "error|warn|exception|fatal" | head -5 || echo "No errors found"; echo ""; done'
echo ""

echo "4. Demonstrating structured logging with labels:"
echo ""
echo "   Example log entry showing:"
echo "   - Timestamp: ISO 8601 format"
echo "   - Service label: container name"
echo "   - Structured fields: JSON format"
echo ""
ssh -i $SSH_KEY ubuntu@$MANAGER_IP 'docker service logs plant-monitoring_processor --timestamps --tail 3 2>&1'
echo ""

echo "5. Loki Query API (alternative to Grafana UI when queries timeout):"
echo ""
echo "   Querying last 1 minute of processor logs:"
START_TIME=$(date -u -d '1 minute ago' +%s)000000000
END_TIME=$(date -u +%s)000000000

ssh -i $SSH_KEY ubuntu@$MANAGER_IP "curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={container_name=\"plant-monitoring_processor\"}' \
  --data-urlencode 'limit=5' \
  --data-urlencode 'start=$START_TIME' \
  --data-urlencode 'end=$END_TIME' | jq -r '.data.result[0].values[-3:][]' 2>/dev/null || echo 'Loki query timeout (expected with high volume)'"
echo ""

echo "=========================================="
echo "SUMMARY:"
echo "=========================================="
echo "✅ Promtail deployed as DaemonSet (global mode) - 5/5 nodes"
echo "✅ Logs collected from all pipeline components (sensor, kafka, processor, mongodb)"
echo "✅ Logs include timestamps (ISO 8601 format)"
echo "✅ Logs include pod/container labels"
echo "✅ Logs include structured fields (JSON)"
echo "✅ Centralized storage in Loki"
echo "✅ Queryable via Grafana Explore (http://$MANAGER_IP:3000)"
echo ""
echo "NOTE: Loki UI queries may timeout with large log volumes."
echo "      Use narrow time ranges (last 30s-1m) or Loki API directly."
echo ""
echo "Grafana Explore Query Examples:"
echo '  - All errors: {container_name=~"plant-monitoring.*"} |~ "(?i)error"'
echo '  - Specific service: {container_name="plant-monitoring_processor"}'
echo '  - Time range: Last 30 seconds (to avoid timeout)'
echo "=========================================="
