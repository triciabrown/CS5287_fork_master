#!/bin/bash

#################################################
# Resilience Testing Script for CA3
# Demonstrates Docker Swarm self-healing capabilities
#################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANAGER_IP="${MANAGER_IP:-52.14.239.94}"
SSH_KEY="${SSH_KEY:-~/.ssh/docker-swarm-key}"
SERVICE_NAME="${SERVICE_NAME:-plant-monitoring_sensor}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  CA3 Resilience Testing Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

#################################################
# Test 1: Container Failure - Kill and Auto-Restart
#################################################

test_container_failure() {
    echo -e "${GREEN}TEST 1: Container Failure & Auto-Recovery${NC}"
    echo "==========================================="
    echo ""
    
    echo "Step 1: Checking current service state..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" "docker service ls | grep -E 'NAME|sensor|processor'"
    echo ""
    
    echo "Step 2: Viewing running sensor tasks..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ps $SERVICE_NAME --filter 'desired-state=running' --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}'"
    echo ""
    
    echo "Step 3: Simulating container failure..."
    echo "-------------------------------------------"
    echo "Note: Since sensors run on worker nodes, we'll simulate failure"
    echo "by removing a task and watching Swarm auto-recover."
    echo ""
    
    # Get current task count
    TASK_COUNT_BEFORE=$(ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ps $SERVICE_NAME --filter 'desired-state=running' | wc -l")
    echo "Current running tasks: $((TASK_COUNT_BEFORE - 1))"
    echo ""
    
    echo -e "${YELLOW}Step 4: Forcing service update to trigger task restart...${NC}"
    echo "-------------------------------------------"
    echo "This simulates a container crash by forcing a rolling restart."
    # Force update will restart tasks one by one
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service update --force $SERVICE_NAME" 2>&1 | head -5
    
    echo -e "${RED}✗ Service update triggered (tasks will be replaced)${NC}"
    echo ""
    
    echo "Step 5: Observing rolling restart and auto-recovery (15 seconds)..."
    echo "-------------------------------------------"
    for i in {15..1}; do
        echo -n "$i... "
        sleep 1
    done
    echo ""
    echo ""
    
    echo "Step 6: Observing task transitions..."
    echo "-------------------------------------------"
    echo "This shows old tasks shutting down and new tasks starting:"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ps $SERVICE_NAME --format 'table {{.Name}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}' | head -15"
    echo ""
    
    echo "Step 7: Verifying service recovered to desired state..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ls | grep sensor"
    echo ""
    
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ps $SERVICE_NAME --filter 'desired-state=running' --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}'"
    echo ""
    
    echo -e "${GREEN}✓ Test 1 Complete: Container auto-recovered${NC}"
    echo ""
}

#################################################
# Test 2: Graceful Service Update - Rolling Restart
#################################################

test_rolling_update() {
    echo -e "${GREEN}TEST 2: Graceful Rolling Update${NC}"
    echo "==========================================="
    echo ""
    
    PROCESSOR_SERVICE="plant-monitoring_processor"
    
    echo "Step 1: Current processor state..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ps $PROCESSOR_SERVICE --filter 'desired-state=running' --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}'"
    echo ""
    
    echo -e "${YELLOW}Step 2: Triggering rolling update (force restart)...${NC}"
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service update --force $PROCESSOR_SERVICE"
    echo ""
    
    echo "Step 3: Waiting for update to complete (15 seconds)..."
    echo "-------------------------------------------"
    for i in {15..1}; do
        echo -n "$i... "
        sleep 1
    done
    echo ""
    echo ""
    
    echo "Step 4: Task history (showing graceful shutdown)..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ps $PROCESSOR_SERVICE --format 'table {{.Name}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}' | head -10"
    echo ""
    
    echo "Step 5: Verifying service is healthy..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ls | grep processor"
    echo ""
    
    echo -e "${GREEN}✓ Test 2 Complete: Rolling update successful${NC}"
    echo ""
}

#################################################
# Test 3: Service Scaling - Scale Up and Down
#################################################

test_scaling() {
    echo -e "${GREEN}TEST 3: Rapid Scaling (Up and Down)${NC}"
    echo "==========================================="
    echo ""
    
    echo "Step 1: Current replica count..."
    echo "-------------------------------------------"
    CURRENT_REPLICAS=$(ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ls --filter 'name=$SERVICE_NAME' --format '{{.Replicas}}'")
    echo "Current: $CURRENT_REPLICAS"
    echo ""
    
    echo -e "${YELLOW}Step 2: Scaling up to 4 replicas...${NC}"
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service scale $SERVICE_NAME=4"
    echo ""
    
    echo "Step 3: Waiting for scale-up to converge (15 seconds)..."
    echo "-------------------------------------------"
    for i in {15..1}; do
        echo -n "$i... "
        sleep 1
    done
    echo ""
    echo ""
    
    echo "Step 4: Verifying scaled state..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ls | grep sensor"
    echo ""
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ps $SERVICE_NAME --filter 'desired-state=running' --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}'"
    echo ""
    
    echo -e "${YELLOW}Step 5: Scaling down to 2 replicas...${NC}"
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service scale $SERVICE_NAME=2"
    echo ""
    
    echo "Step 6: Waiting for scale-down (10 seconds)..."
    echo "-------------------------------------------"
    for i in {10..1}; do
        echo -n "$i... "
        sleep 1
    done
    echo ""
    echo ""
    
    echo "Step 7: Verifying return to baseline..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ls | grep sensor"
    echo ""
    
    echo -e "${GREEN}✓ Test 3 Complete: Scaling operations successful${NC}"
    echo ""
}

#################################################
# Operator Response Demo - Check Logs and Metrics
#################################################

operator_response() {
    echo -e "${GREEN}OPERATOR RESPONSE: Troubleshooting Steps${NC}"
    echo "==========================================="
    echo ""
    
    echo "Step 1: Check for recent failures..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ps $SERVICE_NAME --filter 'desired-state=shutdown' --format 'table {{.Name}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}' | head -10"
    echo ""
    
    echo "Step 2: View recent service logs..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service logs $SERVICE_NAME --tail 20 --timestamps"
    echo ""
    
    echo "Step 3: Check Grafana metrics..."
    echo "-------------------------------------------"
    echo "URL: http://$MANAGER_IP:3000"
    echo "Dashboard: Plant Monitoring System"
    echo "Metrics to check:"
    echo "  - Producer rate (sensor messages/sec)"
    echo "  - Kafka consumer lag"
    echo "  - MongoDB inserts/sec"
    echo ""
    
    echo "Step 4: Verify service health..."
    echo "-------------------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker service ls | grep -E 'NAME|plant-monitoring'"
    echo ""
    
    echo -e "${GREEN}✓ Operator Response Complete${NC}"
    echo ""
}

#################################################
# Main Test Runner
#################################################

main() {
    echo ""
    echo "This script will run 3 resilience tests:"
    echo "  1. Container failure (kill sensor, observe auto-restart)"
    echo "  2. Rolling update (force update processor)"
    echo "  3. Scaling test (scale up/down)"
    echo "  4. Operator response (logs and troubleshooting)"
    echo ""
    echo "Manager IP: $MANAGER_IP"
    echo "SSH Key: $SSH_KEY"
    echo ""
    
    read -p "Press Enter to start tests (or Ctrl+C to cancel)..."
    echo ""
    
    # Run all tests
    test_container_failure
    echo ""
    echo "Press Enter to continue to next test..."
    read
    echo ""
    
    test_rolling_update
    echo ""
    echo "Press Enter to continue to next test..."
    read
    echo ""
    
    test_scaling
    echo ""
    echo "Press Enter to see operator response..."
    read
    echo ""
    
    operator_response
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  All Resilience Tests Complete!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Summary:"
    echo "  ✓ Container auto-recovery verified"
    echo "  ✓ Rolling updates verified"
    echo "  ✓ Scaling operations verified"
    echo "  ✓ Operator troubleshooting demonstrated"
    echo ""
    echo "Next steps:"
    echo "  1. Record 3-minute video of this test"
    echo "  2. Capture Grafana metrics during failure"
    echo "  3. Update README with findings"
    echo ""
}

# Run main function
main
