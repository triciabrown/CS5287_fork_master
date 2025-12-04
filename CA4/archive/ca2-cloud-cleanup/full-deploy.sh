#!/bin/bash
# full-deploy.sh
# Complete end-to-end deployment: Infrastructure + Applications
# Single command deployment as required by CA2 assignment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="${1:-plant-monitoring}"
MODE="${MODE:-local}"  # local, aws-single, aws-multi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Plant Monitoring - Complete Deployment               ║${NC}"
echo -e "${BLUE}║     CA2: Container Orchestration Assignment               ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Deployment Mode: ${MODE}"
echo "Stack Name: ${STACK_NAME}"
echo ""

# ============================================================================
# Mode Selection
# ============================================================================

case ${MODE} in
    local)
        echo -e "${BLUE}📍 LOCAL MODE: Single-node Docker Swarm${NC}"
        echo "This mode deploys on the current machine only"
        echo "Perfect for development and testing"
        echo ""
        ;;
    
    aws-single)
        echo -e "${BLUE}☁️  AWS SINGLE-NODE MODE${NC}"
        echo "Provisions 1 AWS EC2 instance and deploys"
        echo "Uses Terraform + Ansible"
        echo ""
        echo -e "${YELLOW}Note: This requires AWS credentials configured${NC}"
        ;;
    
    aws-multi)
        echo -e "${BLUE}☁️  AWS MULTI-NODE MODE (3-5 nodes)${NC}"
        echo "Provisions AWS infrastructure and deploys"
        echo "Uses Terraform + Ansible"
        echo ""
        echo -e "${YELLOW}Note: This requires AWS credentials configured${NC}"
        ;;
    
    *)
        echo -e "${RED}ERROR: Invalid MODE: ${MODE}${NC}"
        echo "Valid modes: local, aws-single, aws-multi"
        exit 1
        ;;
esac

# ============================================================================
# Step 1: Infrastructure Provisioning
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 1: Infrastructure Provisioning${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

if [ "${MODE}" = "local" ]; then
    echo -e "${YELLOW}Using existing local machine${NC}"
    echo "✓ Infrastructure: localhost"
    echo ""
    
    # Check Docker installed
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}ERROR: Docker not installed${NC}"
        echo "Please install Docker first:"
        echo "  https://docs.docker.com/engine/install/"
        exit 1
    fi
    
    # Check Docker running
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}ERROR: Docker is not running${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker installed and running${NC}"
    echo ""
    
elif [ "${MODE}" = "aws-single" ] || [ "${MODE}" = "aws-multi" ]; then
    echo -e "${BLUE}Provisioning AWS infrastructure...${NC}"
    echo ""
    
    # Check prerequisites
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}ERROR: Terraform not installed${NC}"
        echo "Install from: https://www.terraform.io/downloads"
        exit 1
    fi
    
    if ! command -v ansible &> /dev/null; then
        echo -e "${RED}ERROR: Ansible not installed${NC}"
        echo "Install with: pip install ansible"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Terraform installed${NC}"
    echo -e "${GREEN}✓ Ansible installed${NC}"
    echo ""
    
    # TODO: Implement AWS provisioning
    echo -e "${YELLOW}⚠️  AWS provisioning not yet implemented${NC}"
    echo ""
    echo "To implement:"
    echo "1. cd terraform/"
    echo "2. terraform init"
    echo "3. terraform apply -auto-approve"
    echo "4. Extract outputs to ansible inventory"
    echo "5. ansible-playbook -i inventory ansible/setup-swarm.yml"
    echo ""
    echo -e "${YELLOW}For now, please provision AWS infrastructure manually${NC}"
    echo "Then run: MODE=local ./full-deploy.sh"
    exit 1
fi

# ============================================================================
# Step 2: Application Deployment
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 2: Application Deployment${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Executing deploy.sh...${NC}"
echo ""

# Run the application deployment script
bash "${SCRIPT_DIR}/deploy.sh" "${STACK_NAME}"

# ============================================================================
# Step 3: Verification
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 3: Deployment Verification${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Get manager IP
if [ "${MODE}" = "local" ]; then
    MANAGER_IP=$(hostname -I | awk '{print $1}')
else
    MANAGER_IP=$(docker node inspect self --format '{{.Status.Addr}}' 2>/dev/null || echo "localhost")
fi

echo -e "${GREEN}✓ Deployment Complete!${NC}"
echo ""
echo -e "${BLUE}Access Points:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🏠 Home Assistant:  http://${MANAGER_IP}:8123"
echo "  📊 Kafka Broker:    ${MANAGER_IP}:9092"
echo "  🗄️  MongoDB:         ${MANAGER_IP}:27017"
echo "  📡 MQTT Broker:     ${MANAGER_IP}:1883"
echo ""

echo -e "${BLUE}Service Status:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker stack services ${STACK_NAME}
echo ""

echo -e "${BLUE}Useful Commands:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  View all services:     docker stack services ${STACK_NAME}"
echo "  Scale sensors:         docker service scale ${STACK_NAME}_sensor=5"
echo "  View logs:             docker service logs ${STACK_NAME}_<service>"
echo "  Run scaling demo:      bash scripts/scale-demo.sh"
echo "  Teardown:              bash teardown.sh"
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║             Deployment Successful! 🎉                     ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
