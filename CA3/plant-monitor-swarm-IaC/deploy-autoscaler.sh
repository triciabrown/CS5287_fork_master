#!/bin/bash
#
# deploy-autoscaler.sh - Deploy Docker Swarm autoscaler for processor service
#
# This implements HPA-like functionality for Docker Swarm:
# - Monitors Kafka consumer lag via Prometheus
# - Scales processor service 1-5 replicas automatically
# - Scale up when lag > 100 messages
# - Scale down when lag < 20 messages
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STACK_NAME="autoscaler"

echo "=========================================="
echo "Docker Swarm Autoscaler Deployment"
echo "=========================================="
echo ""

# Check if running on manager node
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "❌ Error: Docker Swarm is not active"
    exit 1
fi

if ! docker info 2>/dev/null | grep -q "Is Manager: true"; then
    echo "❌ Error: This script must run on a Swarm manager node"
    exit 1
fi

echo "✅ Docker Swarm is active and this is a manager node"
echo ""

# Check if Prometheus is accessible
echo "Checking Prometheus availability..."
if docker service ls --filter name=monitoring_prometheus | grep -q prometheus; then
    echo "✅ Prometheus service found"
else
    echo "❌ Error: Prometheus service not found. Deploy monitoring stack first."
    exit 1
fi

echo ""
echo "Deploying autoscaler stack..."
echo "Configuration:"
echo "  Service to scale: plant-monitoring_processor"
echo "  Metric: kafka_consumergroup_lag"
echo "  Scale up threshold: lag > 100 messages"
echo "  Scale down threshold: lag < 20 messages"
echo "  Min replicas: 1"
echo "  Max replicas: 5"
echo "  Check interval: 30 seconds"
echo ""

# Deploy the autoscaler stack
docker stack deploy -c "${SCRIPT_DIR}/autoscaler-stack.yml" "$STACK_NAME"

echo ""
echo "✅ Autoscaler stack deployed"
echo ""

# Wait for service to start
echo "Waiting for autoscaler service to start..."
sleep 10

# Show service status
echo ""
echo "=========================================="
echo "Autoscaler Service Status"
echo "=========================================="
docker service ls --filter name=autoscaler

echo ""
echo "=========================================="
echo "Autoscaler Logs (last 20 lines)"
echo "=========================================="
docker service logs autoscaler_simple-autoscaler --tail 20 2>&1 || echo "Service starting..."

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Monitor autoscaler logs:"
echo "   docker service logs -f autoscaler_simple-autoscaler"
echo ""
echo "2. Generate load to trigger scaling:"
echo "   bash add-sensors.sh 10    # Add 10 sensors"
echo ""
echo "3. Watch processor replicas:"
echo "   watch -n 5 'docker service ls | grep processor'"
echo ""
echo "4. Check Kafka lag in Prometheus:"
echo "   http://<manager-ip>:9090"
echo "   Query: kafka_consumergroup_lag{consumergroup=\"plant-care-processor\"}"
echo ""
echo "5. Remove autoscaler when done:"
echo "   docker stack rm autoscaler"
echo ""
echo "=========================================="
echo "Autoscaler Deployment Complete!"
echo "=========================================="
