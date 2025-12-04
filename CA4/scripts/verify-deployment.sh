#!/bin/bash
# CA4 Deployment Verification Script
# Comprehensive checks for cloud, VPN, and edge components

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
CA4_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER_IP_FILE="${CA4_ROOT}/.manager-ip"
CLOUD_VPN_GATEWAY="10.20.0.1"
EDGE_VPN_CLIENT="10.20.0.2"

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_section() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC} - $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC} - $1"
    if [[ -n "$2" ]]; then
        echo -e "  ${RED}Error: $2${NC}"
    fi
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

test_warn() {
    echo -e "${YELLOW}⚠ WARN${NC} - $1"
    if [[ -n "$2" ]]; then
        echo -e "  ${YELLOW}Warning: $2${NC}"
    fi
    ((WARNING_TESTS++))
    ((TOTAL_TESTS++))
}

test_info() {
    echo -e "${BLUE}ℹ INFO${NC} - $1"
}

# ============================================================================
# Cloud Infrastructure Tests
# ============================================================================

test_cloud_infrastructure() {
    print_section "Cloud Infrastructure Tests"
    
    # Check if manager IP exists
    if [[ -f "${MANAGER_IP_FILE}" ]]; then
        MANAGER_IP=$(cat "${MANAGER_IP_FILE}")
        test_pass "Manager IP file found: ${MANAGER_IP}"
    else
        test_fail "Manager IP file not found" "Cloud infrastructure may not be deployed"
        return 1
    fi
    
    # Test SSH connectivity to manager
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key \
        ubuntu@"${MANAGER_IP}" "echo 'SSH OK'" &> /dev/null; then
        test_pass "SSH connectivity to manager (${MANAGER_IP})"
    else
        test_fail "Cannot SSH to manager" "Check SSH key and security groups"
        return 1
    fi
    
    # Check Docker Swarm status
    test_info "Checking Docker Swarm cluster..."
    SWARM_NODES=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker node ls --format '{{.Hostname}}' 2>/dev/null" | wc -l)
    
    if [[ "${SWARM_NODES}" -ge 5 ]]; then
        test_pass "Docker Swarm cluster has ${SWARM_NODES} nodes (expected: 5)"
    elif [[ "${SWARM_NODES}" -gt 0 ]]; then
        test_warn "Docker Swarm has ${SWARM_NODES} nodes (expected: 5)" "Some nodes may not be joined"
    else
        test_fail "Docker Swarm not initialized" "Run swarm initialization"
    fi
    
    # Check deployed services
    test_info "Checking deployed services..."
    SERVICES=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker service ls --format '{{.Name}}' 2>/dev/null")
    
    local expected_services=("home-assistant" "kafka" "zookeeper" "mongodb" "processor")
    for service in "${expected_services[@]}"; do
        if echo "${SERVICES}" | grep -q "${service}"; then
            test_pass "Service '${service}' is deployed"
        else
            test_fail "Service '${service}' not found" "Stack may not be fully deployed"
        fi
    done
    
    # Check service replicas
    test_info "Checking service health..."
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker service ls" | while read -r line; do
        if echo "${line}" | grep -q "0/"; then
            SERVICE_NAME=$(echo "${line}" | awk '{print $2}')
            test_fail "Service '${SERVICE_NAME}' has no running replicas"
        fi
    done
}

# ============================================================================
# VPN Tests
# ============================================================================

test_vpn_connectivity() {
    print_section "VPN Connectivity Tests"
    
    # Check WireGuard installation
    if command -v wg &> /dev/null; then
        test_pass "WireGuard is installed"
    else
        test_fail "WireGuard not installed" "Install with: sudo apt install wireguard"
        return 1
    fi
    
    # Check wg0 interface
    if ip link show wg0 &> /dev/null; then
        test_pass "WireGuard interface 'wg0' exists"
    else
        test_fail "WireGuard interface 'wg0' not found" "VPN may not be configured. Run: sudo wg-quick up wg0"
        return 1
    fi
    
    # Check edge VPN IP
    if ip addr show wg0 | grep -q "${EDGE_VPN_CLIENT}"; then
        test_pass "Edge VPN IP assigned: ${EDGE_VPN_CLIENT}"
    else
        test_fail "Edge VPN IP not assigned" "Expected ${EDGE_VPN_CLIENT} on wg0"
    fi
    
    # Test cloud VPN gateway connectivity
    if ping -c 3 -W 5 "${CLOUD_VPN_GATEWAY}" &> /dev/null; then
        test_pass "Cloud VPN gateway reachable (${CLOUD_VPN_GATEWAY})"
    else
        test_fail "Cannot ping cloud VPN gateway" "Check WireGuard config and firewall"
    fi
    
    # Test Kafka connectivity via VPN
    if timeout 5 bash -c "echo > /dev/tcp/${CLOUD_VPN_GATEWAY}/9092" 2>/dev/null; then
        test_pass "Kafka reachable via VPN (${CLOUD_VPN_GATEWAY}:9092)"
    else
        test_warn "Kafka TCP connection failed" "Service may not be ready yet"
    fi
    
    # Show WireGuard status
    test_info "WireGuard status:"
    sudo wg show | sed 's/^/  /'
}

# ============================================================================
# Edge Deployment Tests
# ============================================================================

test_edge_deployment() {
    print_section "Edge Deployment Tests"
    
    # Check Docker
    if command -v docker &> /dev/null; then
        test_pass "Docker is installed on edge"
    else
        test_fail "Docker not installed"
        return 1
    fi
    
    # Check for running sensors
    local sensors=("plant-sensor-1" "plant-sensor-2" "plant-sensor-3")
    for sensor in "${sensors[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${sensor}$"; then
            test_pass "Edge sensor '${sensor}' is running"
            
            # Check sensor logs for errors
            if docker logs "${sensor}" 2>&1 | tail -50 | grep -qi "error\|failed\|exception"; then
                test_warn "Sensor '${sensor}' has errors in logs" "Check: docker logs ${sensor}"
            fi
        else
            test_fail "Edge sensor '${sensor}' not running" "Deploy with: cd edge-site && ./deploy-edge.sh"
        fi
    done
    
    # Check sensor network
    if docker network ls | grep -q "edge-network"; then
        test_pass "Edge network 'edge-network' exists"
    else
        test_warn "Edge network not found" "May not be deployed yet"
    fi
}

# ============================================================================
# End-to-End Tests
# ============================================================================

test_end_to_end() {
    print_section "End-to-End Integration Tests"
    
    if [[ ! -f "${MANAGER_IP_FILE}" ]]; then
        test_warn "Skipping E2E tests - cloud not deployed"
        return
    fi
    
    MANAGER_IP=$(cat "${MANAGER_IP_FILE}")
    
    # Check Kafka topics
    test_info "Checking Kafka topics..."
    KAFKA_TOPICS=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker exec \$(sudo docker ps -q -f name=kafka) kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null" || echo "")
    
    if echo "${KAFKA_TOPICS}" | grep -q "plant-sensors"; then
        test_pass "Kafka topic 'plant-sensors' exists"
    else
        test_warn "Kafka topic 'plant-sensors' not found" "May be created on first message"
    fi
    
    # Check MongoDB collections
    test_info "Checking MongoDB collections..."
    MONGO_COLLECTIONS=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker exec \$(sudo docker ps -q -f name=mongodb) mongosh --quiet --eval 'db.getMongo().getDBNames()' 2>/dev/null" || echo "")
    
    if echo "${MONGO_COLLECTIONS}" | grep -q "plant_monitoring"; then
        test_pass "MongoDB database 'plant_monitoring' exists"
    else
        test_warn "MongoDB database not found" "Will be created on first write"
    fi
    
    # Check Home Assistant accessibility
    if [[ -n "${MANAGER_IP}" ]]; then
        if timeout 5 curl -s -o /dev/null -w "%{http_code}" "http://${MANAGER_IP}:8123" | grep -q "200\|301\|302"; then
            test_pass "Home Assistant UI accessible at http://${MANAGER_IP}:8123"
        else
            test_warn "Home Assistant UI not accessible" "Service may still be starting"
        fi
    fi
}

# ============================================================================
# Network Architecture Tests
# ============================================================================

test_network_architecture() {
    print_section "Network Architecture Tests"
    
    if [[ ! -f "${MANAGER_IP_FILE}" ]]; then
        test_warn "Skipping network tests - cloud not deployed"
        return
    fi
    
    MANAGER_IP=$(cat "${MANAGER_IP_FILE}")
    
    # Check overlay networks
    test_info "Checking Docker overlay networks..."
    NETWORKS=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker network ls --format '{{.Name}}' --filter driver=overlay 2>/dev/null")
    
    local expected_networks=("frontend-net" "messaging-net" "data-net")
    for network in "${expected_networks[@]}"; do
        if echo "${NETWORKS}" | grep -q "${network}"; then
            test_pass "Overlay network '${network}' exists"
        else
            test_fail "Overlay network '${network}' not found" "3-tier architecture not deployed"
        fi
    done
    
    # Verify network segmentation
    test_info "Verifying network segmentation..."
    
    # Home Assistant should only be on frontend-net
    HA_NETWORKS=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker service inspect plant-monitoring_home-assistant --format '{{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}' 2>/dev/null" || echo "")
    
    if echo "${HA_NETWORKS}" | grep -q "frontend-net" && ! echo "${HA_NETWORKS}" | grep -q "messaging-net\|data-net"; then
        test_pass "Home Assistant correctly isolated on frontend-net only"
    else
        test_warn "Home Assistant network segmentation unclear" "Check service networks"
    fi
}

# ============================================================================
# Security Tests
# ============================================================================

test_security() {
    print_section "Security Tests"
    
    # Check WireGuard encryption
    if sudo wg show | grep -q "ChaCha20Poly1305"; then
        test_pass "WireGuard using ChaCha20Poly1305 encryption"
    elif sudo wg show | grep -q "public key"; then
        test_warn "WireGuard active but encryption details unclear"
    else
        test_fail "WireGuard encryption not verified"
    fi
    
    # Check for private keys in version control
    if find "${CA4_ROOT}/vpn-config" -name "*.key" -o -name "*.conf" | grep -v template | grep -q .; then
        test_warn "Private keys found in vpn-config/" "Ensure .gitignore is working"
    else
        test_pass "No private keys found in vpn-config/ (or gitignored)"
    fi
    
    # Check VPN config files
    if [[ -f "${CA4_ROOT}/vpn-config/keys/cloud-private.key" ]]; then
        CLOUD_KEY_PERMS=$(stat -c "%a" "${CA4_ROOT}/vpn-config/keys/cloud-private.key")
        if [[ "${CLOUD_KEY_PERMS}" == "600" ]]; then
            test_pass "Cloud private key has secure permissions (600)"
        else
            test_warn "Cloud private key has loose permissions (${CLOUD_KEY_PERMS})" "Should be 600"
        fi
    fi
}

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    print_banner "VERIFICATION SUMMARY"
    
    echo -e "${CYAN}Test Results:${NC}"
    echo -e "  ${GREEN}Passed:  ${PASSED_TESTS}${NC}"
    echo -e "  ${RED}Failed:  ${FAILED_TESTS}${NC}"
    echo -e "  ${YELLOW}Warnings: ${WARNING_TESTS}${NC}"
    echo -e "  ${BLUE}Total:   ${TOTAL_TESTS}${NC}"
    echo ""
    
    local success_rate=0
    if [[ ${TOTAL_TESTS} -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    if [[ ${FAILED_TESTS} -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed! (${success_rate}% success rate)${NC}"
        echo -e "${GREEN}CA4 deployment is fully operational.${NC}"
    elif [[ ${success_rate} -ge 80 ]]; then
        echo -e "${YELLOW}⚠ Most tests passed (${success_rate}% success rate)${NC}"
        echo -e "${YELLOW}Review warnings and failures above.${NC}"
    else
        echo -e "${RED}✗ Multiple failures detected (${success_rate}% success rate)${NC}"
        echo -e "${RED}Review and fix failed tests above.${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Component Status:${NC}"
    [[ ${FAILED_TESTS} -eq 0 ]] && \
        echo -e "  ${GREEN}●${NC} Cloud Infrastructure" || \
        echo -e "  ${RED}●${NC} Cloud Infrastructure"
    
    if sudo wg show &> /dev/null && ping -c 1 -W 2 "${CLOUD_VPN_GATEWAY}" &> /dev/null; then
        echo -e "  ${GREEN}●${NC} VPN Connectivity"
    else
        echo -e "  ${RED}●${NC} VPN Connectivity"
    fi
    
    if docker ps | grep -q plant-sensor; then
        echo -e "  ${GREEN}●${NC} Edge Sensors"
    else
        echo -e "  ${YELLOW}●${NC} Edge Sensors"
    fi
    
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_banner "CA4 DEPLOYMENT VERIFICATION"
    
    echo -e "${BLUE}Starting comprehensive deployment verification...${NC}\n"
    
    # Run all test suites
    test_cloud_infrastructure || true
    test_vpn_connectivity || true
    test_edge_deployment || true
    test_network_architecture || true
    test_end_to_end || true
    test_security || true
    
    # Print summary
    print_summary
    
    # Exit with appropriate code
    if [[ ${FAILED_TESTS} -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
