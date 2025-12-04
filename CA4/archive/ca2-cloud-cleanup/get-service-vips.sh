#!/bin/bash
set -e

# Script to extract VIP addresses from deployed services
# This allows us to update connection strings with actual IPs instead of relying on DNS

MANAGER_IP="${1:-$(terraform output -raw manager_public_ip 2>/dev/null || echo '18.217.181.87')}"
STACK_NAME="plant-monitoring"

echo "=== Extracting Service VIPs from Docker Swarm ==="
echo "Manager: $MANAGER_IP"
echo ""

# Function to get VIP for a service
get_vip() {
    local service_name=$1
    ssh -i ~/.ssh/docker-swarm-key -o StrictHostKeyChecking=no ubuntu@${MANAGER_IP} \
        "docker service inspect ${STACK_NAME}_${service_name} --format '{{range .Endpoint.VirtualIPs}}{{.Addr}}{{end}}' 2>/dev/null | head -1 | cut -d'/' -f1"
}

# Get VIPs for infrastructure services
echo "Getting VIPs for infrastructure services..."
ZOOKEEPER_VIP=$(get_vip zookeeper)
KAFKA_VIP=$(get_vip kafka)
MONGODB_VIP=$(get_vip mongodb)
MOSQUITTO_VIP=$(get_vip mosquitto)

echo ""
echo "=== Discovered VIPs ==="
echo "ZooKeeper: ${ZOOKEEPER_VIP}"
echo "Kafka:     ${KAFKA_VIP}"
echo "MongoDB:   ${MONGODB_VIP}"
echo "Mosquitto: ${MOSQUITTO_VIP}"
echo ""

# Validate all VIPs were found
if [ -z "$ZOOKEEPER_VIP" ] || [ -z "$KAFKA_VIP" ] || [ -z "$MONGODB_VIP" ] || [ -z "$MOSQUITTO_VIP" ]; then
    echo "ERROR: Failed to get all VIPs. Some services may not be running yet."
    echo "Wait for services to start and try again."
    exit 1
fi

# Create environment file for Ansible to use
cat > ansible/group_vars/vips.yml <<EOF
---
# Auto-generated VIP addresses from Docker Swarm
# Generated: $(date)

zookeeper_vip: "${ZOOKEEPER_VIP}"
kafka_vip: "${KAFKA_VIP}"
mongodb_vip: "${MONGODB_VIP}"
mosquitto_vip: "${MOSQUITTO_VIP}"
EOF

echo "VIPs saved to ansible/group_vars/vips.yml"
echo ""
echo "=== Next Steps ==="
echo "1. Update docker-compose.yml to use these VIPs in connection strings"
echo "2. Redeploy the stack: ./deploy.sh"
echo ""
echo "Connection strings should be:"
echo "  KAFKA_ZOOKEEPER_CONNECT: '${ZOOKEEPER_VIP}:2181'"
echo "  KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://${KAFKA_VIP}:9092'"
echo "  KAFKA_BROKER: '${KAFKA_VIP}:9092'"
echo "  MQTT_BROKER: 'mqtt://${MOSQUITTO_VIP}:1883'"
echo "  MongoDB: 'mongodb://user:pass@${MONGODB_VIP}:27017/...'"
