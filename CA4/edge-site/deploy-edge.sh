#!/bin/bash
# CA4 Edge Site Deployment Script
# Deploys edge sensors after verifying VPN connectivity to cloud

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLOUD_VPN_IP="10.20.0.1"
CLOUD_KAFKA_VPN="10.20.0.1:9092"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ============================================================================
# Pre-deployment Checks
# ============================================================================

check_vpn_connectivity() {
    print_header "Checking VPN Connectivity"
    
    # Check if WireGuard interface exists
    if ! ip link show wg0 &> /dev/null; then
        print_error "WireGuard interface 'wg0' not found"
        print_info "Run: sudo wg-quick up wg0"
        exit 1
    fi
    print_success "WireGuard interface 'wg0' is up"
    
    # Check if VPN IP is assigned
    if ! ip addr show wg0 | grep -q "10.20.0.2"; then
        print_error "VPN IP 10.20.0.2 not assigned to wg0"
        exit 1
    fi
    print_success "VPN IP 10.20.0.2 is assigned"
    
    # Ping cloud VPN gateway
    print_info "Testing connectivity to cloud VPN gateway (${CLOUD_VPN_IP})..."
    if ping -c 3 -W 5 "${CLOUD_VPN_IP}" &> /dev/null; then
        print_success "Cloud VPN gateway is reachable"
    else
        print_error "Cannot reach cloud VPN gateway at ${CLOUD_VPN_IP}"
        print_info "Check WireGuard configuration and cloud firewall rules"
        exit 1
    fi
    
    # Test Kafka connectivity via VPN
    print_info "Testing Kafka connectivity via VPN (${CLOUD_KAFKA_VPN})..."
    if timeout 5 bash -c "echo > /dev/tcp/10.20.0.1/9092" 2>/dev/null; then
        print_success "Kafka is reachable via VPN"
    else
        print_warning "Cannot establish TCP connection to Kafka on ${CLOUD_KAFKA_VPN}"
        print_info "This may be normal if Kafka hasn't started yet"
    fi
}

check_docker() {
    print_header "Checking Docker"
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    print_success "Docker is installed"
    
    if ! docker ps &> /dev/null; then
        print_error "Cannot connect to Docker daemon"
        print_info "Ensure Docker service is running and user has permissions"
        exit 1
    fi
    print_success "Docker daemon is accessible"
    
    # Check for Docker Compose (prefer v2)
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        print_success "docker compose (v2) is installed"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        print_success "docker-compose (v1) is installed"
    else
        print_error "Docker Compose is not installed"
        exit 1
    fi
}

check_compose_file() {
    print_header "Checking Compose File"
    
    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        print_error "Docker Compose file not found: ${COMPOSE_FILE}"
        exit 1
    fi
    print_success "Docker Compose file found"
    
    # Validate compose file
    if ${COMPOSE_CMD} -f "${COMPOSE_FILE}" config > /dev/null 2>&1; then
        print_success "Docker Compose file is valid"
    else
        print_error "Docker Compose file has errors"
        exit 1
    fi
}

# ============================================================================
# Deployment Functions
# ============================================================================

pull_images() {
    print_header "Pulling Docker Images"
    
    print_info "Pulling plant-sensor image..."
    ${COMPOSE_CMD} -f "${COMPOSE_FILE}" pull
    print_success "Images pulled successfully"
}

deploy_sensors() {
    print_header "Deploying Edge Sensors"
    
    print_info "Starting sensor containers..."
    ${COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d
    
    # Wait for containers to start
    sleep 5
    
    # Check container status
    if ${COMPOSE_CMD} -f "${COMPOSE_FILE}" ps | grep -q "Up"; then
        print_success "Edge sensors deployed successfully"
    else
        print_error "Some sensors failed to start"
        ${COMPOSE_CMD} -f "${COMPOSE_FILE}" ps
        exit 1
    fi
}

verify_deployment() {
    print_header "Verifying Deployment"
    
    # List running containers
    print_info "Running sensor containers:"
    ${COMPOSE_CMD} -f "${COMPOSE_FILE}" ps
    
    # Check sensor logs for Kafka connection
    print_info "\nChecking sensor logs for Kafka connectivity..."
    for sensor in plant-sensor-1 plant-sensor-2 plant-sensor-3; do
        if docker logs "${sensor}" 2>&1 | tail -20 | grep -qi "error\|failed\|connection refused"; then
            print_warning "Sensor ${sensor} may have connectivity issues - check logs:"
            print_info "  docker logs ${sensor}"
        else
            print_success "Sensor ${sensor} appears healthy"
        fi
    done
}

show_usage() {
    print_header "Edge Site Deployment Complete"
    
    echo -e "${GREEN}Sensors are now running and sending data to cloud Kafka via VPN${NC}\n"
    
    echo "Useful commands:"
    echo "  View sensor logs:     docker logs -f plant-sensor-1"
    echo "  View all sensors:     ${COMPOSE_CMD} -f ${COMPOSE_FILE} ps"
    echo "  Stop sensors:         ${COMPOSE_CMD} -f ${COMPOSE_FILE} down"
    echo "  Restart sensors:      ${COMPOSE_CMD} -f ${COMPOSE_FILE} restart"
    echo "  View VPN status:      sudo wg show"
    echo "  Test VPN connection:  ping ${CLOUD_VPN_IP}"
    echo ""
}

# ============================================================================
# Cleanup Function
# ============================================================================

cleanup_edge() {
    print_header "Cleaning Up Edge Deployment"
    
    print_info "Stopping and removing sensor containers..."
    ${COMPOSE_CMD} -f "${COMPOSE_FILE}" down -v
    
    print_success "Edge deployment cleaned up"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    print_header "CA4 Edge Site Deployment"
    
    # Parse command line arguments
    if [[ "$1" == "cleanup" ]] || [[ "$1" == "down" ]]; then
        cleanup_edge
        exit 0
    fi
    
    # Run pre-deployment checks
    check_docker
    check_compose_file
    check_vpn_connectivity
    
    # Deploy
    pull_images
    deploy_sensors
    
    # Verify
    verify_deployment
    show_usage
    
    print_success "\n${GREEN}Edge site deployment complete!${NC}"
}

# Run main function
main "$@"
