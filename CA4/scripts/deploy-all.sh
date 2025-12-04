#!/bin/bash
# CA4 Complete Deployment Automation
# Orchestrates cloud infrastructure, VPN, edge sensors, and verification

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA4_ROOT="${SCRIPT_DIR}/.."
CLOUD_SITE="${CA4_ROOT}/cloud-site"
EDGE_SITE="${CA4_ROOT}/edge-site"
VPN_CONFIG="${CA4_ROOT}/vpn-config"
TERRAFORM_DIR="${CLOUD_SITE}/terraform"

# Deployment stages
DEPLOY_CLOUD=true
DEPLOY_VPN=true
DEPLOY_EDGE=true
SKIP_TERRAFORM=false

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

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

confirm_action() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "${default}" == "y" ]]; then
        read -p "${prompt} [Y/n]: " response
        response=${response:-y}
    else
        read -p "${prompt} [y/N]: " response
        response=${response:-n}
    fi
    
    [[ "${response}" =~ ^[Yy] ]]
}

# ============================================================================
# Phase 1: Cloud Infrastructure
# ============================================================================

deploy_cloud_infrastructure() {
    print_banner "PHASE 1: Cloud Infrastructure Deployment"
    
    if [[ "${SKIP_TERRAFORM}" == true ]]; then
        print_warning "Skipping Terraform deployment (--skip-terraform flag)"
        return 0
    fi
    
    cd "${TERRAFORM_DIR}"
    
    # Initialize Terraform
    print_header "Initializing Terraform"
    terraform init
    print_success "Terraform initialized"
    
    # Plan deployment
    print_header "Planning Terraform Deployment"
    terraform plan -out=tfplan
    print_success "Terraform plan created"
    
    # Confirm deployment
    if ! confirm_action "Deploy cloud infrastructure with Terraform?"; then
        print_warning "Cloud deployment skipped by user"
        return 1
    fi
    
    # Apply Terraform
    print_header "Deploying Cloud Infrastructure"
    terraform apply tfplan
    print_success "Cloud infrastructure deployed"
    
    # Save outputs
    print_info "Saving Terraform outputs..."
    terraform output -json > "${CA4_ROOT}/terraform-outputs.json"
    MANAGER_IP=$(terraform output -raw manager_public_ip)
    echo "${MANAGER_IP}" > "${CA4_ROOT}/.manager-ip"
    print_success "Manager IP saved: ${MANAGER_IP}"
    
    # Wait for instances to be ready
    print_info "Waiting for EC2 instances to initialize (60 seconds)..."
    sleep 60
    
    cd "${SCRIPT_DIR}"
}

initialize_swarm() {
    print_header "Initializing Docker Swarm"
    
    if [[ ! -f "${CA4_ROOT}/.manager-ip" ]]; then
        print_error "Manager IP not found. Run cloud deployment first."
        return 1
    fi
    
    MANAGER_IP=$(cat "${CA4_ROOT}/.manager-ip")
    print_info "Connecting to manager: ${MANAGER_IP}"
    
    # Copy SSH key to manager for worker access
    print_info "Copying SSH key to manager node..."
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    scp -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key \
        ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}":~/.ssh/
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "chmod 600 ~/.ssh/docker-swarm-key"
    print_success "SSH key copied to manager"
    
    # Initialize Swarm
    print_info "Initializing Swarm on manager node..."
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker swarm init --advertise-addr \$(hostname -I | awk '{print \$1}')"
    print_success "Docker Swarm initialized"
    
    # Get join token and manager private IP
    print_info "Retrieving worker join token..."
    WORKER_TOKEN=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker swarm join-token worker -q")
    echo "${WORKER_TOKEN}" > "${CA4_ROOT}/.worker-token"
    
    MANAGER_PRIVATE_IP=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "hostname -I | awk '{print \$1}'")
    print_success "Worker token saved"
    print_info "Manager private IP: ${MANAGER_PRIVATE_IP}"
    
    # Get worker IPs from Terraform
    cd "${TERRAFORM_DIR}"
    WORKER_IPS=$(terraform output -json worker_private_ips | jq -r '.[]')
    cd "${SCRIPT_DIR}"
    
    # Create worker join script on manager
    print_header "Joining Worker Nodes"
    print_info "Creating worker join script on manager..."
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" "cat > /tmp/join-workers.sh << 'EOF'
#!/bin/bash
WORKER_TOKEN=\"${WORKER_TOKEN}\"
MANAGER_PRIVATE_IP=\"${MANAGER_PRIVATE_IP}\"
WORKERS=(${WORKER_IPS})

for i in \"\${!WORKERS[@]}\"; do
  WORKER_IP=\"\${WORKERS[\$i]}\"
  echo \"Joining worker \$((i+1)): \${WORKER_IP}\"
  ssh -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key ubuntu@\${WORKER_IP} \
    \"sudo docker swarm join --token \${WORKER_TOKEN} \${MANAGER_PRIVATE_IP}:2377\" || echo \"Failed to join worker \$((i+1))\"
done
EOF
chmod +x /tmp/join-workers.sh"
    
    # Execute worker join script on manager
    print_info "Executing worker join script..."
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "/tmp/join-workers.sh"
    
    # Verify cluster
    print_info "Verifying cluster status..."
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker node ls"
    
    # Label nodes for easier identification and service placement
    print_info "Labeling nodes with descriptive labels..."
    label_swarm_nodes
    
    print_success "Swarm cluster is ready"
}

# Label nodes for better organization and service placement
label_swarm_nodes() {
    if [[ ! -f "${CA4_ROOT}/.manager-ip" ]]; then
        print_error "Manager IP not found. Run cloud deployment first."
        return 1
    fi
    
    MANAGER_IP=$(cat "${CA4_ROOT}/.manager-ip")
    
    # Get node hostnames
    MANAGER_HOSTNAME=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" "hostname")
    
    # Get worker IPs and their hostnames
    cd "${TERRAFORM_DIR}"
    WORKER_IPS=$(terraform output -json worker_private_ips | jq -r '.[]')
    cd "${SCRIPT_DIR}"
    
    # Label manager node
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker node update --label-add role=manager --label-add mqtt=true ${MANAGER_HOSTNAME}"
    
    # Label worker nodes
    WORKER_NUM=1
    for WORKER_IP in ${WORKER_IPS}; do
        WORKER_HOSTNAME=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
            "ssh -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key ubuntu@${WORKER_IP} hostname")
        
        ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
            "sudo docker node update --label-add role=worker --label-add worker_id=${WORKER_NUM} ${WORKER_HOSTNAME}"
        
        WORKER_NUM=$((WORKER_NUM + 1))
    done
    
    print_success "Node labels applied (role, worker_id, mqtt)"
}

deploy_cloud_services() {
    print_header "Deploying Cloud Services"
    
    if [[ ! -f "${CA4_ROOT}/.manager-ip" ]]; then
        print_error "Manager IP not found. Run cloud deployment first."
        return 1
    fi
    
    MANAGER_IP=$(cat "${CA4_ROOT}/.manager-ip")
    
    # Create secrets if not exist
    print_header "Setting Up Secrets and Configs"
    print_info "Copying create-secrets script to manager..."
    scp -i ~/.ssh/docker-swarm-key \
        "${CLOUD_SITE}/scripts/create-secrets.sh" \
        ubuntu@"${MANAGER_IP}":/tmp/create-secrets.sh
    
    print_info "Creating Docker secrets..."
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "bash /tmp/create-secrets.sh" || print_warning "Some secrets may already exist"
    
    print_info "Creating Docker configs..."
    scp -i ~/.ssh/docker-swarm-key \
        "${CLOUD_SITE}/scripts/create-configs.sh" \
        ubuntu@"${MANAGER_IP}":/tmp/create-configs.sh
    
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "bash /tmp/create-configs.sh"
    
    print_success "Secrets and configs ready"
    
    # Copy docker-compose file
    print_header "Deploying Stack"
    print_info "Copying docker-compose to manager..."
    scp -i ~/.ssh/docker-swarm-key \
        "${CLOUD_SITE}/docker-compose.yml" \
        ubuntu@"${MANAGER_IP}":~/docker-compose.yml
    print_success "Docker Compose file copied"
    
    # Deploy stack
    print_info "Deploying plant-monitoring stack..."
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker stack deploy -c ~/docker-compose.yml plant-monitoring"
    print_success "Stack deployed"
    
    # Wait for services
    print_info "Waiting for services to start (30 seconds)..."
    sleep 30
    
    # Check service status
    print_info "Service status:"
    ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker service ls"
    
    # Verify and fix MongoDB initialization
    if verify_mongodb_users; then
        print_success "MongoDB and processor are ready"
    else
        print_warning "MongoDB user creation had issues, but continuing deployment"
        print_info "You may need to manually verify the processor later"
    fi
}

# Verify MongoDB users are created, fix if not
verify_mongodb_users() {
    if [[ ! -f "${CA4_ROOT}/.manager-ip" ]]; then
        print_error "Manager IP not found."
        return 1
    fi
    
    MANAGER_IP=$(cat "${CA4_ROOT}/.manager-ip")
    
    print_header "Verifying MongoDB Initialization"
    print_info "Waiting for MongoDB service to be ready..."
    
    # Wait up to 120 seconds for MongoDB service to have a running task
    for i in {1..24}; do
        MONGO_RUNNING=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
            "sudo docker service ps plant-monitoring_mongodb --filter 'desired-state=running' --format '{{.CurrentState}}' | head -1")
        
        if echo "$MONGO_RUNNING" | grep -q "Running"; then
            print_success "MongoDB service is running"
            # Give MongoDB a few more seconds to fully initialize
            sleep 10
            break
        fi
        
        if [[ $i -eq 24 ]]; then
            print_error "MongoDB service not ready after 120 seconds"
            print_info "Current state: $MONGO_RUNNING"
            return 1
        fi
        
        echo -n "."
        sleep 5
    done
    
    print_info "Verifying MongoDB application user..."
    
    # Find which node MongoDB is running on
    MONGO_NODE=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker service ps plant-monitoring_mongodb --filter 'desired-state=running' --format '{{.Node}}' | head -1")
    
    if [ -z "$MONGO_NODE" ]; then
        print_error "MongoDB service not found"
        return 1
    fi
    
    MONGO_NODE_IP=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
        "sudo docker node inspect $MONGO_NODE --format '{{.Status.Addr}}'")
    
    print_info "MongoDB is running on node: $MONGO_NODE ($MONGO_NODE_IP)"
    
    # Copy verification script to manager node
    scp -q -i ~/.ssh/docker-swarm-key \
        "${CLOUD_SITE}/scripts/verify-mongodb-user.sh" \
        ubuntu@"${MANAGER_IP}":/tmp/verify-mongodb-user.sh
    
    # Get manager's private IP for comparison
    MANAGER_PRIVATE_IP=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" "hostname -I | awk '{print \$1}'")
    
    # If MongoDB is on a worker node, copy script there too
    if [ "$MONGO_NODE_IP" != "$MANAGER_PRIVATE_IP" ]; then
        print_info "Copying verification script to worker node..."
        ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
            "scp -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key /tmp/verify-mongodb-user.sh ubuntu@${MONGO_NODE_IP}:/tmp/"
        
        # Run verification script on worker node
        ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
            "ssh -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key ubuntu@${MONGO_NODE_IP} 'bash /tmp/verify-mongodb-user.sh'"
    else
        # Run verification script on manager node
        ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
            "bash /tmp/verify-mongodb-user.sh"
    fi
    
    if [ $? -eq 0 ]; then
        print_success "MongoDB user verified/created successfully"
        
        # Restart processor to ensure it picks up the MongoDB user
        print_info "Restarting processor service..."
        ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
            "sudo docker service update --force plant-monitoring_processor >/dev/null 2>&1"
        
        # Wait and check processor status
        sleep 15
        PROCESSOR_STATUS=$(ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
            "sudo docker service ps plant-monitoring_processor --filter 'desired-state=running' --format '{{.CurrentState}}' | head -1")
        
        if echo "$PROCESSOR_STATUS" | grep -q "Running"; then
            print_success "Processor service is now running!"
        else
            print_warning "Processor status: $PROCESSOR_STATUS"
            print_info "Check logs with: ssh ubuntu@${MANAGER_IP} 'sudo docker service logs plant-monitoring_processor'"
        fi
    else
        print_error "Failed to verify/create MongoDB user"
        return 1
    fi
}

# ============================================================================
# Phase 2: VPN Configuration
# ============================================================================

deploy_vpn() {
    print_banner "PHASE 2: VPN Configuration"
    
    cd "${VPN_CONFIG}"
    
    # Generate keys if not exists
    if [[ ! -d "keys" ]]; then
        print_header "Generating WireGuard Keys"
        bash generate-keys.sh
        print_success "WireGuard keys generated"
    else
        print_info "Using existing WireGuard keys"
    fi
    
    # Get manager IP
    if [[ ! -f "${CA4_ROOT}/.manager-ip" ]]; then
        print_error "Manager IP not found. Run cloud deployment first."
        return 1
    fi
    
    MANAGER_IP=$(cat "${CA4_ROOT}/.manager-ip")
    
    # Setup VPN configurations
    print_header "Setting Up VPN"
    print_info "Deploying VPN to cloud (${MANAGER_IP})..."
    bash setup-vpn.sh "${MANAGER_IP}" --deploy-cloud
    print_success "Cloud VPN configured"
    
    # Prompt for edge deployment
    if confirm_action "Deploy VPN to edge (local machine)?"; then
        print_info "Deploying VPN to edge..."
        bash setup-vpn.sh "${MANAGER_IP}" --deploy-edge
        print_success "Edge VPN configured"
        
        # Check if VPN interface already exists
        if ip link show wg0 &> /dev/null; then
            print_warning "WireGuard interface 'wg0' already exists"
            if confirm_action "Restart VPN interface?"; then
                print_info "Restarting edge VPN..."
                sudo wg-quick down wg0 || true
                sudo wg-quick up wg0
                print_success "Edge VPN restarted"
            else
                print_info "Using existing VPN connection"
            fi
        else
            print_info "Starting edge VPN..."
            sudo wg-quick up wg0
            print_success "Edge VPN is up"
        fi
        
        # Test connectivity
        print_info "Testing VPN connectivity..."
        if ping -c 3 10.20.0.1; then
            print_success "VPN connectivity verified"
        else
            print_warning "VPN connectivity test failed"
        fi
    else
        print_warning "Edge VPN deployment skipped"
        print_info "To deploy edge VPN later:"
        print_info "  cd ${VPN_CONFIG}"
        print_info "  bash setup-vpn.sh --deploy-edge"
        print_info "  sudo wg-quick up wg0"
    fi
    
    cd "${SCRIPT_DIR}"
}

# ============================================================================
# Phase 3: Edge Deployment
# ============================================================================

deploy_edge_sensors() {
    print_banner "PHASE 3: Edge Sensor Deployment"
    
    cd "${EDGE_SITE}"
    
    # Check VPN connectivity
    print_header "Checking VPN Connectivity"
    if ! ping -c 3 -W 5 10.20.0.1 &> /dev/null; then
        print_error "Cannot reach cloud VPN gateway (10.20.0.1)"
        print_info "Ensure edge VPN is configured and running:"
        print_info "  sudo wg-quick up wg0"
        return 1
    fi
    print_success "Cloud VPN gateway is reachable"
    
    # Deploy edge sensors
    print_header "Deploying Edge Sensors"
    bash deploy-edge.sh
    
    cd "${SCRIPT_DIR}"
}

# ============================================================================
# Verification
# ============================================================================

verify_deployment() {
    print_banner "DEPLOYMENT VERIFICATION"
    
    print_header "Cloud Services"
    if [[ -f "${CA4_ROOT}/.manager-ip" ]]; then
        MANAGER_IP=$(cat "${CA4_ROOT}/.manager-ip")
        ssh -i ~/.ssh/docker-swarm-key ubuntu@"${MANAGER_IP}" \
            "sudo docker service ls"
    else
        print_warning "Manager IP not found"
    fi
    
    print_header "VPN Status"
    sudo wg show || print_warning "WireGuard not configured on this machine"
    
    print_header "Edge Sensors"
    docker compose -f "${EDGE_SITE}/docker-compose.yml" ps || print_warning "No edge sensors running"
    
    print_header "Connectivity Tests"
    print_info "Testing VPN connectivity..."
    ping -c 3 10.20.0.1 || print_warning "Cannot reach cloud VPN"
    
    print_info "Testing Kafka connectivity..."
    timeout 5 bash -c "echo > /dev/tcp/10.20.0.1/9092" 2>/dev/null && \
        print_success "Kafka is reachable" || \
        print_warning "Kafka connectivity test failed"
}

# ============================================================================
# Cleanup
# ============================================================================

cleanup_all() {
    print_banner "CLEANING UP CA4 DEPLOYMENT"
    
    if confirm_action "This will destroy all CA4 resources. Continue?" "n"; then
        # Stop edge sensors
        print_header "Stopping Edge Sensors"
        cd "${EDGE_SITE}"
        docker compose down -v || true
        
        # Stop edge VPN
        print_header "Stopping Edge VPN"
        sudo wg-quick down wg0 || true
        
        # Destroy cloud infrastructure
        print_header "Destroying Cloud Infrastructure"
        cd "${TERRAFORM_DIR}"
        terraform destroy -auto-approve
        
        # Clean up generated files
        rm -f "${CA4_ROOT}/.manager-ip"
        rm -f "${CA4_ROOT}/.worker-token"
        rm -f "${CA4_ROOT}/terraform-outputs.json"
        rm -rf "${VPN_CONFIG}/keys"
        rm -rf "${VPN_CONFIG}/generated"
        
        print_success "Cleanup complete"
    else
        print_info "Cleanup cancelled"
    fi
}

# ============================================================================
# Usage
# ============================================================================

show_usage() {
    cat << EOF
CA4 Deployment Automation

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    deploy          Full deployment (cloud + VPN + edge)
    cloud           Deploy cloud infrastructure only
    vpn             Deploy VPN only (requires cloud)
    edge            Deploy edge sensors only (requires cloud + VPN)
    verify          Verify deployment
    cleanup         Destroy all resources

Options:
    --skip-terraform    Skip Terraform deployment (use existing infrastructure)
    --no-cloud         Skip cloud deployment
    --no-vpn           Skip VPN deployment
    --no-edge          Skip edge deployment
    -h, --help         Show this help message

Examples:
    $0 deploy                    # Full deployment
    $0 cloud                     # Deploy cloud only
    $0 --skip-terraform vpn      # Deploy VPN to existing infrastructure
    $0 verify                    # Check deployment status
    $0 cleanup                   # Destroy everything

EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Parse arguments
    COMMAND="deploy"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-terraform)
                SKIP_TERRAFORM=true
                shift
                ;;
            --no-cloud)
                DEPLOY_CLOUD=false
                shift
                ;;
            --no-vpn)
                DEPLOY_VPN=false
                shift
                ;;
            --no-edge)
                DEPLOY_EDGE=false
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            deploy|cloud|vpn|edge|verify|cleanup)
                COMMAND="$1"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute command
    case "${COMMAND}" in
        deploy)
            print_banner "CA4 FULL DEPLOYMENT"
            [[ "${DEPLOY_CLOUD}" == true ]] && deploy_cloud_infrastructure && initialize_swarm && deploy_cloud_services
            [[ "${DEPLOY_VPN}" == true ]] && deploy_vpn
            [[ "${DEPLOY_EDGE}" == true ]] && deploy_edge_sensors
            verify_deployment
            print_success "\n${GREEN}Full deployment complete!${NC}"
            ;;
        cloud)
            deploy_cloud_infrastructure
            initialize_swarm
            deploy_cloud_services
            ;;
        vpn)
            deploy_vpn
            ;;
        edge)
            deploy_edge_sensors
            ;;
        verify)
            verify_deployment
            ;;
        cleanup)
            cleanup_all
            ;;
    esac
}

main "$@"
