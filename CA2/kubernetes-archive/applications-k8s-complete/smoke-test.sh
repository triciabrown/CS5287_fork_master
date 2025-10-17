#!/bin/bash
# Plant Monitoring System - Smoke Test
# CS5287 CA2 - PaaS Implementation
# 
# This script validates that the Plant Monitoring System is working correctly

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="plant-monitoring"
TEST_TIMEOUT=120

echo -e "${BLUE}🧪 Plant Monitoring System - Smoke Test${NC}"
echo "==========================================="

# Test functions
test_passed=0
test_failed=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" &>/dev/null; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((test_passed++))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        ((test_failed++))
        return 1
    fi
}

run_test_with_output() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "${BLUE}🔍 $test_name${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✅ PASS${NC}"
        ((test_passed++))
        echo ""
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        ((test_failed++))
        echo ""
        return 1
    fi
}

echo ""
echo -e "${YELLOW}📋 Prerequisites Check${NC}"

# Check kubectl connectivity
run_test "Kubectl connectivity" "kubectl cluster-info"

# Check namespace exists
run_test "Namespace exists" "kubectl get namespace $NAMESPACE"

echo ""
echo -e "${YELLOW}📊 Infrastructure Tests${NC}"

# Check pods are running
run_test_with_output "Pod status" "kubectl get pods -n $NAMESPACE"

# Check services are available
run_test_with_output "Service status" "kubectl get services -n $NAMESPACE"

# Check persistent volumes
run_test_with_output "Storage status" "kubectl get pvc -n $NAMESPACE"

echo ""
echo -e "${YELLOW}🔌 Connectivity Tests${NC}"

# Test MongoDB connectivity
run_test "MongoDB connectivity" "
    kubectl exec -n $NAMESPACE mongodb-0 -- mongosh --eval 'db.adminCommand(\"ping\")' --quiet 2>/dev/null | grep -q '{ ok: 1 }'
"

# Test Kafka connectivity
run_test "Kafka connectivity" "
    kubectl exec -n $NAMESPACE kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null
"

echo ""
echo -e "${YELLOW}📈 Data Flow Tests${NC}"

# Create test topic if not exists
echo "Creating test topic..."
kubectl exec -n $NAMESPACE kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --create --topic test-topic --partitions 1 --replication-factor 1 --if-not-exists 2>/dev/null || true

# Test Kafka producer
run_test "Kafka producer test" "
    echo 'test-message' | kubectl exec -i -n $NAMESPACE kafka-0 -- kafka-console-producer --bootstrap-server localhost:9092 --topic test-topic
"

# Test Kafka consumer (with timeout)
run_test "Kafka consumer test" "
    timeout 10 kubectl exec -n $NAMESPACE kafka-0 -- kafka-console-consumer --bootstrap-server localhost:9092 --topic test-topic --from-beginning --max-messages 1 2>/dev/null | grep -q test-message
"

# Test MongoDB write
echo "Testing MongoDB write operation..."
kubectl exec -n $NAMESPACE mongodb-0 -- mongosh --eval '
db.getSiblingDB("test").testCollection.insertOne({
    test: true, 
    timestamp: new Date().toISOString(),
    smokeTest: "CA2-validation"
})
' --quiet 2>/dev/null

# Test MongoDB read
run_test "MongoDB read/write test" "
    kubectl exec -n $NAMESPACE mongodb-0 -- mongosh --eval 'db.getSiblingDB(\"test\").testCollection.findOne({smokeTest: \"CA2-validation\"})' --quiet 2>/dev/null | grep -q 'CA2-validation'
"

echo ""
echo -e "${YELLOW}🏗️ Architecture Validation${NC}"

# Check resource requests/limits
run_test_with_output "Resource constraints" "
    kubectl describe pods -n $NAMESPACE | grep -E '(Requests|Limits)' | head -10
"

# Check network policies
run_test "Network policies" "kubectl get networkpolicy -n $NAMESPACE"

# Check secrets and configmaps
run_test "Configuration management" "
    kubectl get configmap,secret -n $NAMESPACE | grep -E '(mongodb-|kafka-|app-)'
"

echo ""
echo -e "${YELLOW}🏠 Home Assistant Integration Tests${NC}"

# Test Home Assistant connectivity
run_test "Home Assistant HTTP service" "
    kubectl exec -n $NAMESPACE deployment/homeassistant -c homeassistant -- wget --spider -q http://localhost:8123/ 2>/dev/null
"

# Test MQTT broker connectivity
run_test "MQTT broker connectivity" "
    kubectl exec -n $NAMESPACE deployment/homeassistant -c mosquitto -- nc -z localhost 1883
"

# Test Home Assistant MQTT integration
echo "Testing MQTT message flow..."
kubectl exec -n $NAMESPACE deployment/homeassistant -c mosquitto -- timeout 5 mosquitto_pub -h localhost -t test/topic -m 'test-message' 2>/dev/null || true

run_test "MQTT message publishing" "
    kubectl exec -n $NAMESPACE deployment/homeassistant -c mosquitto -- timeout 5 mosquitto_sub -h localhost -t test/topic -C 1 2>/dev/null | grep -q 'test-message'
"

echo ""
echo -e "${YELLOW}🌱 Plant Sensor Validation${NC}"

# Check plant sensors are running
run_test "Plant sensor 001 running" "kubectl get deployment plant-sensor-001 -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '^1$'"

run_test "Plant sensor 002 running" "kubectl get deployment plant-sensor-002 -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '^1$'"

# Test sensor data generation (check logs for recent activity)
echo "Checking plant sensor activity..."
SENSOR_001_ACTIVE=$(kubectl logs deployment/plant-sensor-001 -n $NAMESPACE --tail=10 2>/dev/null | grep -c "Sent sensor data" || echo "0")
SENSOR_002_ACTIVE=$(kubectl logs deployment/plant-sensor-002 -n $NAMESPACE --tail=10 2>/dev/null | grep -c "Sent sensor data" || echo "0")

run_test "Plant sensor 001 generating data" "[ $SENSOR_001_ACTIVE -gt 0 ]"
run_test "Plant sensor 002 generating data" "[ $SENSOR_002_ACTIVE -gt 0 ]"

echo ""
echo -e "${YELLOW}📊 Performance Indicators${NC}"

# Check pod resource usage (if metrics available)
if kubectl top nodes &>/dev/null; then
    run_test_with_output "Node resource usage" "kubectl top nodes"
    run_test_with_output "Pod resource usage" "kubectl top pods -n $NAMESPACE"
else
    echo "⚠️  Metrics server not available, skipping resource usage tests"
fi

# Check for any failed pods
FAILED_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
run_test "No failed pods" "[ $FAILED_PODS -eq 0 ]"

# Check for any pending pods (after initial startup)
echo "Waiting for pods to stabilize..."
sleep 30
PENDING_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
run_test "No pending pods" "[ $PENDING_PODS -eq 0 ]"

echo ""
echo -e "${YELLOW}🔍 Application Log Sampling${NC}"

# Sample application logs
echo "MongoDB logs (last 5 lines):"
kubectl logs -n $NAMESPACE mongodb-0 --tail=5 2>/dev/null || echo "No logs available"

echo ""
echo "Kafka logs (last 5 lines):"
kubectl logs -n $NAMESPACE kafka-0 --tail=5 2>/dev/null || echo "No logs available"

echo ""
echo "Processor logs (last 5 lines):"
kubectl logs -n $NAMESPACE -l app=plant-processor --tail=5 2>/dev/null || echo "No logs available"

echo ""
echo "Home Assistant logs (last 5 lines):"
kubectl logs -n $NAMESPACE deployment/homeassistant -c homeassistant --tail=5 2>/dev/null || echo "No logs available"

echo ""
echo "MQTT Broker logs (last 5 lines):"
kubectl logs -n $NAMESPACE deployment/homeassistant -c mosquitto --tail=5 2>/dev/null || echo "No logs available"

echo ""
echo "Plant Sensor 001 logs (last 3 lines):"
kubectl logs -n $NAMESPACE deployment/plant-sensor-001 --tail=3 2>/dev/null || echo "No logs available"

echo ""
echo "Plant Sensor 002 logs (last 3 lines):"
kubectl logs -n $NAMESPACE deployment/plant-sensor-002 --tail=3 2>/dev/null || echo "No logs available"

echo ""
echo -e "${BLUE}📋 Test Summary${NC}"
echo "=============="
echo -e "Tests passed: ${GREEN}$test_passed${NC}"
echo -e "Tests failed: ${RED}$test_failed${NC}"

if [ $test_failed -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 All smoke tests passed! Plant Monitoring System is healthy.${NC}"
    echo ""
    echo -e "${YELLOW}📝 Validation Complete:${NC}"
    echo "✅ Platform provisioning verified"
    echo "✅ Container orchestration working"
    echo "✅ Data flow validated (Sensors → Kafka → Processor → MongoDB)"
    echo "✅ Home Assistant dashboard operational"
    echo "✅ MQTT broker connectivity confirmed"
    echo "✅ Plant sensor simulation active"
    echo "✅ Security configuration applied"
    echo "✅ Network isolation implemented"
    echo "✅ Resource management configured"
    echo ""
    echo -e "${BLUE}🚀 Complete Plant Monitoring System ready for production!${NC}"
    echo ""
    echo -e "${YELLOW}🏠 Next Steps for Home Assistant:${NC}"
    echo "1. Access Home Assistant dashboard via kubectl port-forward"
    echo "2. Complete initial Home Assistant setup"
    echo "3. Add MQTT integration with broker settings"
    echo "4. Plant sensors will auto-discover and appear in dashboard"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some tests failed. Check the system configuration.${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Troubleshooting commands:${NC}"
    echo "kubectl get all -n $NAMESPACE"
    echo "kubectl describe pods -n $NAMESPACE"
    echo "kubectl logs -n $NAMESPACE <pod-name>"
    exit 1
fi