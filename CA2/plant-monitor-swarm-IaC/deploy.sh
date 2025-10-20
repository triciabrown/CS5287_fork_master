#!/bin/bash
# Complete IDEMPOTENT Deploy Script
# Provisions AWS infrastructure, configures Docker Swarm, and deploys applications
# Single command deployment as required by CA2 assignment
#
# Usage:
#   ./deploy.sh                    # AWS multi-node deployment (DEFAULT)
#   MODE=local ./deploy.sh         # Local single-node deployment (development)
#   BUILD_IMAGES=true ./deploy.sh  # Build images before deploying

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="${1:-plant-monitoring}"
MODE="${MODE:-aws}"  # DEFAULT: aws (use MODE=local for development)
BUILD_IMAGES="${BUILD_IMAGES:-false}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Plant Monitoring - Complete Deployment               ║${NC}"
echo -e "${BLUE}║     CA2: Container Orchestration (Docker Swarm)           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Deployment Mode: ${MODE} $([ "${MODE}" = "aws" ] && echo "(DEFAULT)" || echo "(override)")"
echo "Stack Name: ${STACK_NAME}"
echo "Build Images: ${BUILD_IMAGES}"
echo ""

# ============================================================================
# AWS INFRASTRUCTURE PROVISIONING (if MODE=aws)
# ============================================================================

if [ "${MODE}" = "aws" ]; then
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Phase 1: AWS Infrastructure Provisioning${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Check prerequisites
    echo "Checking prerequisites..."
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}ERROR: Terraform not installed${NC}"
        echo "Install from: https://www.terraform.io/downloads"
        exit 1
    fi
    
    if ! command -v ansible-playbook &> /dev/null; then
        echo -e "${RED}ERROR: Ansible not installed${NC}"
        echo "Install with: pip install ansible"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠ jq not installed (recommended)${NC}"
        echo "Install with: sudo apt-get install jq"
    fi
    
    echo -e "${GREEN}✓ Terraform installed${NC}"
    echo -e "${GREEN}✓ Ansible installed${NC}"
    echo ""
    
    # SSH Key Setup and Agent Configuration
    echo -e "${YELLOW}→ Configuring SSH key for cluster access...${NC}"
    SSH_KEY_PATH="${HOME}/.ssh/docker-swarm-key"
    
    # Check if SSH key exists, generate if not
    if [ ! -f "${SSH_KEY_PATH}" ]; then
        echo "SSH key not found at ${SSH_KEY_PATH}"
        echo "Generating new SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N "" -C "docker-swarm@aws"
        chmod 600 "${SSH_KEY_PATH}"
        chmod 644 "${SSH_KEY_PATH}.pub"
        echo -e "${GREEN}✓ SSH key pair generated${NC}"
    else
        echo -e "${GREEN}✓ SSH key exists${NC}"
    fi
    
    # Ensure SSH agent is running and key is added
    echo "Configuring SSH agent..."
    
    # Start ssh-agent if not already running
    if [ -z "$SSH_AUTH_SOCK" ]; then
        echo "Starting SSH agent..."
        eval $(ssh-agent -s)
    else
        echo "SSH agent already running (PID: $(pgrep ssh-agent || echo 'unknown'))"
    fi
    
    # Add key to agent if not already added
    if ! ssh-add -l 2>/dev/null | grep -q "${SSH_KEY_PATH}"; then
        echo "Adding SSH key to agent..."
        ssh-add "${SSH_KEY_PATH}"
        echo -e "${GREEN}✓ SSH key added to agent${NC}"
    else
        echo -e "${GREEN}✓ SSH key already in agent${NC}"
    fi
    
    # Verify key is loaded
    echo "Loaded SSH keys:"
    ssh-add -l | sed 's/^/  /'
    echo ""
    
    # Terraform: Provision AWS infrastructure
    echo -e "${YELLOW}→ Provisioning AWS EC2 instances with Terraform...${NC}"
    cd "${SCRIPT_DIR}/terraform"
    
    # Initialize Terraform (idempotent)
    if [ ! -d ".terraform" ]; then
        echo "Initializing Terraform..."
        terraform init
    else
        echo "Terraform already initialized"
    fi
    
    # Apply Terraform configuration (idempotent)
    echo "Applying Terraform configuration..."
    terraform apply -auto-approve
    
    # Extract outputs
    MANAGER_IP=$(terraform output -raw manager_public_ip)
    echo -e "${GREEN}✓ Infrastructure provisioned${NC}"
    echo -e "${GREEN}  Manager IP: ${MANAGER_IP}${NC}"
    echo ""
    
    # Generate Ansible inventory
    echo -e "${YELLOW}→ Generating Ansible inventory...${NC}"
    cd "${SCRIPT_DIR}"
    
    cat > ansible/inventory.ini <<EOF
# Auto-generated by deploy.sh
# Do not edit manually

[managers]
manager1 ansible_host=$(cd terraform && terraform output -raw manager_public_ip) ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/docker-swarm-key ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[workers]
EOF
    
    # Add worker nodes (using private IPs, accessed via manager bastion)
    # Note: Workers are in private subnet and don't have public IPs
    # Future: Add workers with ProxyJump through manager or modify for single-node deployment
    if command -v jq &> /dev/null; then
        # Check if worker_private_ips output exists (for multi-node clusters)
        if (cd terraform && terraform output -json worker_private_ips 2>&1) | grep -q '\['; then
            WORKER_COUNT=$(cd terraform && terraform output -json worker_private_ips | jq '. | length')
            MANAGER_IP=$(cd terraform && terraform output -raw manager_public_ip)
            for i in $(seq 0 $((WORKER_COUNT-1))); do
                WORKER_IP=$(cd terraform && terraform output -json worker_private_ips | jq -r ".[$i]")
                # Workers accessible via manager as bastion (ProxyJump)
                echo "worker$((i+1)) ansible_host=${WORKER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/docker-swarm-key ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyJump=ubuntu@${MANAGER_IP}'" >> ansible/inventory.ini
            done
        fi
    fi
    
    echo -e "${GREEN}✓ Inventory generated${NC}"
    cat ansible/inventory.ini
    echo ""
    
    # Wait for instances to be ready
    echo -e "${YELLOW}→ Waiting for AWS instances to be fully initialized...${NC}"
    echo "This takes about 2-3 minutes for cloud-init and Docker installation..."
    sleep 120
    echo -e "${GREEN}✓ Instances ready${NC}"
    echo ""
    
    # Ansible: Configure Docker Swarm
    echo -e "${YELLOW}→ Configuring Docker Swarm cluster with Ansible...${NC}"
    echo "Using SSH agent forwarding for worker node access..."
    ansible-playbook -i ansible/inventory.ini ansible/setup-swarm.yml \
      --ssh-common-args='-o ForwardAgent=yes -o StrictHostKeyChecking=no'
    echo -e "${GREEN}✓ Docker Swarm cluster configured${NC}"
    echo ""
    
    # Ansible: Deploy application stack
    echo -e "${YELLOW}→ Deploying application stack with Ansible...${NC}"
    ansible-playbook -i ansible/inventory.ini ansible/deploy-stack.yml \
      --ssh-common-args='-o ForwardAgent=yes -o StrictHostKeyChecking=no'
    echo -e "${GREEN}✓ Application stack deployed${NC}"
    echo ""
    
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     AWS Deployment Complete! 🎉                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Public Access:${NC}"
    echo "  🏠 Home Assistant:  http://${MANAGER_IP}:8123"
    echo ""
    echo -e "${BLUE}SSH Access (Bastion):${NC}"
    echo "  🔑 Manager:  ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP}"
    echo ""
    echo -e "${YELLOW}Internal Services (accessible via SSH tunnel only):${NC}"
    echo "  📡 MQTT:     mosquitto:1883"
    echo "  📊 Kafka:    kafka:9092"
    echo "  🗄️  MongoDB:  mongodb:27017"
    echo ""
    echo -e "${YELLOW}SSH Tunneling Examples:${NC}"
    echo "  MongoDB:  ssh -i ~/.ssh/docker-swarm-key -L 27017:mongodb:27017 ubuntu@${MANAGER_IP}"
    echo "  Kafka:    ssh -i ~/.ssh/docker-swarm-key -L 9092:kafka:9092 ubuntu@${MANAGER_IP}"
    echo "  MQTT:     ssh -i ~/.ssh/docker-swarm-key -L 1883:mosquitto:1883 ubuntu@${MANAGER_IP}"
    echo ""
    echo -e "${YELLOW}Management Commands:${NC}"
    echo "  View services:      ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP} 'docker stack services ${STACK_NAME}'"
    echo "  Scale sensors:      ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP} 'docker service scale ${STACK_NAME}_sensor=5'"
    echo "  Teardown:           ./teardown.sh"
    echo ""
    exit 0
fi

# ============================================================================
# LOCAL DEPLOYMENT (MODE=local)
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Local Docker Swarm Deployment${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Pre-flight checks
echo -e "${YELLOW}→ Running pre-flight checks...${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not running${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker is running${NC}"

# Check if Swarm is initialized
if ! docker info | grep -q "Swarm: active"; then
    echo -e "${YELLOW}⚠ Docker Swarm not initialized${NC}"
    echo "Initializing Docker Swarm..."
    
    # Get the primary network interface IP (eth0, or fallback to first non-loopback)
    ADVERTISE_ADDR=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    if [ -z "$ADVERTISE_ADDR" ]; then
        # Fallback: get first non-loopback IP
        ADVERTISE_ADDR=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | grep -v '^10\.255\.' | head -1)
    fi
    
    if [ -n "$ADVERTISE_ADDR" ]; then
        echo "Using advertise address: ${ADVERTISE_ADDR}"
        docker swarm init --advertise-addr "${ADVERTISE_ADDR}"
    else
        echo -e "${YELLOW}Could not detect IP address, trying without --advertise-addr${NC}"
        docker swarm init
    fi
    
    echo -e "${GREEN}✓ Docker Swarm initialized${NC}"
else
    echo -e "${GREEN}✓ Docker Swarm is active${NC}"
fi

# Check for required files
if [ ! -f "${SCRIPT_DIR}/docker-compose.yml" ]; then
    echo -e "${RED}ERROR: docker-compose.yml not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker Compose file found${NC}"

echo ""

# Step 1: Create secrets
echo -e "${BLUE}Step 1: Setting up secrets${NC}"
echo "------------------------------"
if [ -f "${SCRIPT_DIR}/scripts/create-secrets.sh" ]; then
    bash "${SCRIPT_DIR}/scripts/create-secrets.sh"
else
    echo -e "${YELLOW}⚠ create-secrets.sh not found, skipping${NC}"
fi
echo ""

# Step 2: Build custom images (optional)
echo -e "${BLUE}Step 2: Application images${NC}"
echo "------------------------------"

if [ "${BUILD_IMAGES}" = "true" ]; then
    echo "Building custom images..."
    cd "${SCRIPT_DIR}/../applications"
    
    if [ -f "build-images.sh" ]; then
        bash build-images.sh
        echo -e "${GREEN}✓ Images built successfully${NC}"
    else
        echo -e "${YELLOW}⚠ build-images.sh not found${NC}"
        echo "Building images manually..."
        
        if [ -d "processor" ]; then
            docker build -t docker.io/triciab221/plant-processor:latest processor/
            echo -e "${GREEN}✓ Processor image built${NC}"
        fi
        
        if [ -d "sensor" ]; then
            docker build -t docker.io/triciab221/plant-sensor:latest sensor/
            echo -e "${GREEN}✓ Sensor image built${NC}"
        fi
    fi
    
    cd "${SCRIPT_DIR}"
else
    echo -e "${YELLOW}Skipping image build (using existing images)${NC}"
    echo -e "${BLUE}ℹ To build images: BUILD_IMAGES=true ./deploy.sh${NC}"
    echo ""
    echo "Checking for required images..."
    
    PROCESSOR_EXISTS=$(docker images -q docker.io/triciab221/plant-processor:latest 2>/dev/null)
    SENSOR_EXISTS=$(docker images -q docker.io/triciab221/plant-sensor:latest 2>/dev/null)
    
    if [ -z "$PROCESSOR_EXISTS" ]; then
        echo -e "${YELLOW}⚠ plant-processor:latest not found locally${NC}"
        echo "  Swarm will attempt to pull from Docker Hub"
    else
        echo -e "${GREEN}✓ plant-processor:latest found locally${NC}"
    fi
    
    if [ -z "$SENSOR_EXISTS" ]; then
        echo -e "${YELLOW}⚠ plant-sensor:latest not found locally${NC}"
        echo "  Swarm will attempt to pull from Docker Hub"
    else
        echo -e "${GREEN}✓ plant-sensor:latest found locally${NC}"
    fi
fi

echo ""

# Step 3: Create configs
echo -e "${BLUE}Step 3: Creating Docker configs${NC}"
echo "------------------------------"

# Remove old configs if they exist
docker config rm mosquitto_config 2>/dev/null || true
docker config rm sensor_config 2>/dev/null || true

# Create mosquitto config
if [ -f "../applications/mosquitto-config/mosquitto.conf" ]; then
    docker config create mosquitto_config ../applications/mosquitto-config/mosquitto.conf
    echo -e "${GREEN}✓ Mosquitto config created${NC}"
else
    echo -e "${YELLOW}⚠ mosquitto.conf not found${NC}"
fi

# Create sensor config
if [ -f "sensor-config.json" ]; then
    docker config create sensor_config sensor-config.json
    echo -e "${GREEN}✓ Sensor config created${NC}"
else
    echo -e "${YELLOW}⚠ sensor-config.json not found${NC}"
fi

echo ""

# Step 4: Label nodes for placement
echo -e "${BLUE}Step 4: Labeling nodes${NC}"
echo "------------------------------"
# Get manager node ID
MANAGER_NODE=$(docker node ls --filter "role=manager" --format "{{.ID}}" | head -n1)
docker node update --label-add mqtt=true ${MANAGER_NODE}
echo -e "${GREEN}✓ Manager node labeled for MQTT/HA placement${NC}"
echo ""

# Step 5: Deploy stack
echo -e "${BLUE}Step 5: Deploying stack${NC}"
echo "------------------------------"
docker stack deploy -c docker-compose.yml ${STACK_NAME}
echo -e "${GREEN}✓ Stack deployment initiated${NC}"
echo ""

# Step 6: Wait for services to start
echo -e "${BLUE}Step 6: Waiting for services to start${NC}"
echo "------------------------------"
echo "This may take 1-2 minutes..."
sleep 30

# Show service status
docker stack services ${STACK_NAME}
echo ""

# Step 7: Run smoke tests
echo -e "${BLUE}Step 7: Running smoke tests${NC}"
echo "------------------------------"
if [ -f "${SCRIPT_DIR}/scripts/smoke-test.sh" ]; then
    sleep 30  # Give services more time
    bash "${SCRIPT_DIR}/scripts/smoke-test.sh" ${STACK_NAME}
else
    echo -e "${YELLOW}⚠ smoke-test.sh not found, skipping validation${NC}"
fi
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Deployment Complete! 🎉                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Stack name: ${STACK_NAME}"
echo ""
echo "Access points:"
MANAGER_IP=$(hostname -I | awk '{print $1}')
echo "  🏠 Home Assistant:  http://${MANAGER_IP}:8123"
echo "  📡 MQTT Broker:     ${MANAGER_IP}:1883"
echo "  📊 Kafka:           ${MANAGER_IP}:9092"
echo "  🗄️  MongoDB:         ${MANAGER_IP}:27017"
echo ""
echo "Useful commands:"
echo "  View services: docker stack services ${STACK_NAME}"
echo "  View logs: docker service logs ${STACK_NAME}_<service-name>"
echo "  Scale sensors: docker service scale ${STACK_NAME}_sensor=<N>"
echo "  Run scaling demo: bash scripts/scale-demo.sh ${STACK_NAME}"
echo "  Remove stack: docker stack rm ${STACK_NAME}"
echo ""
echo -e "${BLUE}Build & Deploy Options:${NC}"
echo "  Build images during deploy: BUILD_IMAGES=true ./deploy.sh"
echo "  Use existing/pulled images:  ./deploy.sh (default)"
echo "  Build images separately:     cd ../applications && ./build-images.sh"
echo "  Push to Docker Hub:          cd ../applications && PUSH_IMAGES=true ./build-images.sh"
echo "  AWS deployment:              MODE=aws ./deploy.sh"
echo ""
