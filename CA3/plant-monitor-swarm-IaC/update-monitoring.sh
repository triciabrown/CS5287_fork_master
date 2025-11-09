#!/bin/bash

# Update Monitoring Stack Configuration
# Fixes MongoDB and Kafka exporter connectivity issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGER_IP="${1:-$(cd "${SCRIPT_DIR}/terraform" && terraform output -raw manager_public_ip 2>/dev/null)}"

if [ -z "$MANAGER_IP" ]; then
    echo "❌ Error: Could not determine manager IP"
    echo "Usage: $0 [MANAGER_IP]"
    exit 1
fi

echo "=========================================="
echo "Update Monitoring Stack Configuration"
echo "=========================================="
echo "Manager IP: $MANAGER_IP"
echo ""

# Step 1: Copy updated configuration files to manager
echo "📤 Copying updated configuration files to manager..."
scp -i ~/.ssh/docker-swarm-key \
    "${SCRIPT_DIR}/configs/prometheus.yml" \
    "${SCRIPT_DIR}/observability-stack.yml" \
    ubuntu@${MANAGER_IP}:~/plant-monitor-swarm-IaC/

echo "✅ Configuration files copied"
echo ""

# Step 2: Update the observability stack on manager
echo "🔄 Updating observability stack on manager..."
ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP} << 'EOF'
    cd ~/plant-monitor-swarm-IaC
    
    echo "Removing old Prometheus config..."
    docker config rm prometheus-config 2>/dev/null || true
    
    echo "Creating new Prometheus config..."
    docker config create prometheus-config configs/prometheus.yml
    
    echo "Redeploying monitoring stack..."
    docker stack deploy -c observability-stack.yml monitoring
    
    echo ""
    echo "Waiting for services to stabilize..."
    sleep 15
    
    echo ""
    echo "📊 Monitoring Stack Services:"
    docker stack services monitoring
    
    echo ""
    echo "🔍 Checking Prometheus targets in 10 seconds..."
    sleep 10
    
    echo ""
    echo "Kafka Exporter logs:"
    docker service logs monitoring_kafka-exporter --tail 20 2>&1 | head -20 || echo "  (service may still be starting)"
    
    echo ""
    echo "MongoDB Exporter logs:"
    docker service logs monitoring_mongodb-exporter --tail 20 2>&1 | head -20 || echo "  (service may still be starting)"
EOF

echo ""
echo "✅ Monitoring stack updated!"
echo ""
echo "🌐 Access Points:"
echo "  Grafana:    http://${MANAGER_IP}:3000 (admin/admin)"
echo "  Prometheus: http://${MANAGER_IP}:9090"
echo ""
echo "📊 Check Prometheus Targets:"
echo "  http://${MANAGER_IP}:9090/targets"
echo ""
echo "🔧 Troubleshooting:"
echo "  View Prometheus config:"
echo "    ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP} 'docker service logs monitoring_prometheus --tail 50'"
echo ""
echo "  View Kafka Exporter logs:"
echo "    ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP} 'docker service logs monitoring_kafka-exporter --tail 50'"
echo ""
echo "  View MongoDB Exporter logs:"
echo "    ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP} 'docker service logs monitoring_mongodb-exporter --tail 50'"
echo ""

