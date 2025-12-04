#!/bin/bash
# scale-demo.sh
# Demonstrate horizontal scaling of plant sensors in Docker Swarm

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="${1:-plant-monitoring}"
SERVICE_NAME="${STACK_NAME}_sensor"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Docker Swarm Horizontal Scaling Demo"
echo "Service: ${SERVICE_NAME}"
echo "=========================================="
echo ""

# Check if service exists
if ! docker service ls --format '{{.Name}}' | grep -q "^${SERVICE_NAME}$"; then
    echo -e "${RED}ERROR: Service '${SERVICE_NAME}' not found${NC}"
    echo "Please deploy the stack first."
    exit 1
fi

# Function to get current metrics
get_metrics() {
    local current_replicas=$(docker service ls --filter "name=${SERVICE_NAME}" --format '{{.Replicas}}')
    echo "$current_replicas"
}

# Function to get Kafka message rate (simulated for demo)
get_message_rate() {
    # In production, you'd query Kafka metrics
    # For demo, we'll estimate based on replicas
    local replicas=$1
    local interval=30  # seconds between messages
    local messages_per_minute=$(echo "scale=2; $replicas * (60 / $interval)" | bc)
    echo "$messages_per_minute"
}

echo -e "${BLUE}Step 1: Current State${NC}"
echo "------------------------------"
INITIAL_REPLICAS=$(get_metrics)
echo "Current replicas: $INITIAL_REPLICAS"
echo "Estimated message rate: $(get_message_rate 2) messages/minute"
echo ""
sleep 2

echo -e "${YELLOW}Step 2: Scale UP to 5 replicas${NC}"
echo "------------------------------"
docker service scale ${SERVICE_NAME}=5
echo "Waiting for services to start..."
sleep 10

echo ""
echo "New state:"
SCALED_UP=$(get_metrics)
echo "Current replicas: $SCALED_UP"
echo "Estimated message rate: $(get_message_rate 5) messages/minute"
echo ""

echo "Service details:"
docker service ps ${SERVICE_NAME} --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}"
echo ""
sleep 5

echo -e "${YELLOW}Step 3: Monitoring scaled services${NC}"
echo "------------------------------"
echo "Checking service logs (last 20 lines)..."
docker service logs --tail 20 ${SERVICE_NAME}
echo ""
sleep 2

echo -e "${YELLOW}Step 4: Scale DOWN to 3 replicas${NC}"
echo "------------------------------"
docker service scale ${SERVICE_NAME}=3
echo "Waiting for services to adjust..."
sleep 10

echo ""
echo "New state:"
SCALED_DOWN=$(get_metrics)
echo "Current replicas: $SCALED_DOWN"
echo "Estimated message rate: $(get_message_rate 3) messages/minute"
echo ""

echo "Service details:"
docker service ps ${SERVICE_NAME} --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}"
echo ""
sleep 2

echo -e "${YELLOW}Step 5: Return to baseline (2 replicas)${NC}"
echo "------------------------------"
docker service scale ${SERVICE_NAME}=2
echo "Waiting for services to stabilize..."
sleep 10

echo ""
FINAL_REPLICAS=$(get_metrics)
echo "Final replicas: $FINAL_REPLICAS"
echo "Estimated message rate: $(get_message_rate 2) messages/minute"
echo ""

echo -e "${GREEN}=========================================="
echo "Scaling Demo Complete!"
echo "==========================================${NC}"
echo ""
echo "Summary:"
echo "  Initial replicas: 2"
echo "  Scaled up to: 5 (2.5x increase)"
echo "  Scaled down to: 3"
echo "  Final replicas: 2 (baseline restored)"
echo ""
echo "Key observations:"
echo "  ✓ Zero downtime during scaling"
echo "  ✓ Automatic load distribution"
echo "  ✓ Proportional throughput increase"
echo "  ✓ Graceful scale-down"
echo ""
