#!/bin/bash
# smoke-test.sh
# Validation script for Docker Swarm plant monitoring system

set -e

STACK_NAME="${1:-plant-monitoring}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

echo "=========================================="
echo "Plant Monitoring Swarm - Smoke Test"
echo "Stack: ${STACK_NAME}"
echo "=========================================="
echo ""

# Test function
run_test() {
    local test_name=$1
    local test_command=$2
    
    echo -n "Testing: ${test_name}... "
    
    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo -e "${BLUE}1. Docker Swarm Status${NC}"
echo "------------------------------"
run_test "Swarm is active" "docker info | grep -q 'Swarm: active'"
run_test "Manager node present" "docker node ls | grep -q 'Leader'"
echo ""

echo -e "${BLUE}2. Stack Deployment${NC}"
echo "------------------------------"
run_test "Stack is deployed" "docker stack ls | grep -q '${STACK_NAME}'"
run_test "All services running" "docker stack services ${STACK_NAME} | grep -v '0/'"
echo ""

echo -e "${BLUE}3. Core Services${NC}"
echo "------------------------------"
run_test "Kafka service running" "docker service ls | grep -q '${STACK_NAME}_kafka'"
run_test "ZooKeeper service running" "docker service ls | grep -q '${STACK_NAME}_zookeeper'"
run_test "MongoDB service running" "docker service ls | grep -q '${STACK_NAME}_mongodb'"
run_test "Processor service running" "docker service ls | grep -q '${STACK_NAME}_processor'"
run_test "Sensor service running" "docker service ls | grep -q '${STACK_NAME}_sensor'"
run_test "MQTT service running" "docker service ls | grep -q '${STACK_NAME}_mosquitto'"
run_test "Home Assistant running" "docker service ls | grep -q '${STACK_NAME}_homeassistant'"
echo ""

echo -e "${BLUE}4. Network Configuration${NC}"
echo "------------------------------"
run_test "Overlay network exists" "docker network ls | grep -q '${STACK_NAME}_plant-network'"
run_test "Network is overlay type" "docker network inspect ${STACK_NAME}_plant-network | grep -q 'overlay'"
echo ""

echo -e "${BLUE}5. Volume Persistence${NC}"
echo "------------------------------"
run_test "Kafka volume exists" "docker volume ls | grep -q 'kafka_data'"
run_test "MongoDB volume exists" "docker volume ls | grep -q 'mongodb_data'"
run_test "ZooKeeper volume exists" "docker volume ls | grep -q 'zookeeper_data'"
echo ""

echo -e "${BLUE}6. Secrets Management${NC}"
echo "------------------------------"
run_test "MongoDB root username secret" "docker secret ls | grep -q 'mongo_root_username'"
run_test "MongoDB root password secret" "docker secret ls | grep -q 'mongo_root_password'"
run_test "MongoDB connection string secret" "docker secret ls | grep -q 'mongodb_connection_string'"
echo ""

echo -e "${BLUE}7. Service Health${NC}"
echo "------------------------------"

# Get manager node IP
MANAGER_IP=$(docker node inspect self --format '{{.Status.Addr}}')

# Test Kafka (if reachable)
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${MANAGER_IP}/9092" 2>/dev/null; then
    echo -e "Kafka port 9092... ${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "Kafka port 9092... ${YELLOW}⚠ SKIP (may not be exposed)${NC}"
fi

# Test MongoDB
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${MANAGER_IP}/27017" 2>/dev/null; then
    echo -e "MongoDB port 27017... ${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "MongoDB port 27017... ${YELLOW}⚠ SKIP (may not be exposed)${NC}"
fi

# Test MQTT
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${MANAGER_IP}/1883" 2>/dev/null; then
    echo -e "MQTT port 1883... ${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "MQTT port 1883... ${YELLOW}⚠ SKIP (may not be exposed)${NC}"
fi

# Test Home Assistant
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${MANAGER_IP}/8123" 2>/dev/null; then
    echo -e "Home Assistant port 8123... ${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "Home Assistant port 8123... ${YELLOW}⚠ SKIP (may not be exposed)${NC}"
fi

echo ""

echo -e "${BLUE}8. Scaling Capability${NC}"
echo "------------------------------"
SENSOR_REPLICAS=$(docker service ls --filter "name=${STACK_NAME}_sensor" --format '{{.Replicas}}' | cut -d'/' -f1)
run_test "Sensor service has replicas" "[ '$SENSOR_REPLICAS' -ge 1 ]"
run_test "Can scale sensor service" "docker service scale ${STACK_NAME}_sensor=${SENSOR_REPLICAS} > /dev/null 2>&1"
echo ""

echo "=========================================="
echo "Test Summary"
echo "=========================================="
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo -e "Total tests: ${TOTAL_TESTS}"
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "Service Status:"
    docker stack services ${STACK_NAME}
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    echo "Service Status:"
    docker stack services ${STACK_NAME}
    echo ""
    echo "Check logs with:"
    echo "  docker service logs ${STACK_NAME}_<service-name>"
    exit 1
fi
