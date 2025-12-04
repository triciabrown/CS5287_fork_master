#!/bin/bash
# WireGuard VPN Setup Script for CA4
# Generates WireGuard configs from templates and deploys to cloud/edge

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/keys"
GENERATED_DIR="${SCRIPT_DIR}/generated"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  WireGuard VPN Setup for CA4${NC}"
echo -e "${BLUE}  Edge-to-Cloud Plant Monitoring System${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# Usage
# ============================================================================
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <AWS_MANAGER_IP> [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  AWS_MANAGER_IP    Public IP of AWS manager node (VPN gateway)"
    echo ""
    echo "Options:"
    echo "  --deploy-cloud    Deploy config to cloud (requires SSH access)"
    echo "  --deploy-edge     Deploy config to edge (local machine)"
    echo "  --deploy-all      Deploy to both cloud and edge"
    echo ""
    echo "Examples:"
    echo "  $0 18.222.123.45                    # Generate configs only"
    echo "  $0 18.222.123.45 --deploy-all       # Generate and deploy"
    echo "  $0 18.222.123.45 --deploy-cloud     # Deploy to cloud only"
    echo ""
    exit 1
fi

AWS_MANAGER_IP="$1"
DEPLOY_CLOUD=false
DEPLOY_EDGE=false

# Parse options
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy-cloud)
            DEPLOY_CLOUD=true
            shift
            ;;
        --deploy-edge)
            DEPLOY_EDGE=true
            shift
            ;;
        --deploy-all)
            DEPLOY_CLOUD=true
            DEPLOY_EDGE=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# ============================================================================
# Pre-flight Checks
# ============================================================================
echo -e "${YELLOW}→ Running pre-flight checks...${NC}"

# Check if keys exist
if [ ! -f "${KEYS_DIR}/cloud-private.key" ]; then
    echo -e "${RED}❌ ERROR: Keys not found${NC}"
    echo "Run: ./generate-keys.sh first"
    exit 1
fi

echo -e "${GREEN}✓ VPN keys found${NC}"

# Check AWS IP format
if ! [[ "$AWS_MANAGER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}❌ ERROR: Invalid IP address format${NC}"
    echo "Expected: x.x.x.x (e.g., 18.222.123.45)"
    exit 1
fi

echo -e "${GREEN}✓ AWS Manager IP valid: ${AWS_MANAGER_IP}${NC}"
echo ""

# ============================================================================
# Load Keys
# ============================================================================
echo -e "${YELLOW}→ Loading VPN keys...${NC}"

CLOUD_PRIVATE_KEY=$(cat "${KEYS_DIR}/cloud-private.key")
CLOUD_PUBLIC_KEY=$(cat "${KEYS_DIR}/cloud-public.key")
EDGE_PRIVATE_KEY=$(cat "${KEYS_DIR}/edge-private.key")
EDGE_PUBLIC_KEY=$(cat "${KEYS_DIR}/edge-public.key")

echo -e "${GREEN}✓ Keys loaded${NC}"
echo ""

# ============================================================================
# Generate Configurations
# ============================================================================
echo -e "${YELLOW}→ Generating WireGuard configurations...${NC}"

mkdir -p "${GENERATED_DIR}"
chmod 700 "${GENERATED_DIR}"

# Generate Cloud Config
echo "  Generating cloud-wg0.conf..."
sed -e "s|{{CLOUD_PRIVATE_KEY}}|${CLOUD_PRIVATE_KEY}|g" \
    -e "s|{{EDGE_PUBLIC_KEY}}|${EDGE_PUBLIC_KEY}|g" \
    "${SCRIPT_DIR}/cloud-wg0.conf.template" > "${GENERATED_DIR}/cloud-wg0.conf"
chmod 600 "${GENERATED_DIR}/cloud-wg0.conf"

# Generate Edge Config
echo "  Generating edge-wg0.conf..."
sed -e "s|{{EDGE_PRIVATE_KEY}}|${EDGE_PRIVATE_KEY}|g" \
    -e "s|{{CLOUD_PUBLIC_KEY}}|${CLOUD_PUBLIC_KEY}|g" \
    -e "s|{{AWS_MANAGER_IP}}|${AWS_MANAGER_IP}|g" \
    "${SCRIPT_DIR}/edge-wg0.conf.template" > "${GENERATED_DIR}/edge-wg0.conf"
chmod 600 "${GENERATED_DIR}/edge-wg0.conf"

echo -e "${GREEN}✓ Configurations generated${NC}"
echo "  Cloud: ${GENERATED_DIR}/cloud-wg0.conf"
echo "  Edge:  ${GENERATED_DIR}/edge-wg0.conf"
echo ""

# ============================================================================
# Deploy to Cloud (Optional)
# ============================================================================
if [ "$DEPLOY_CLOUD" = true ]; then
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Deploying to Cloud (AWS Manager)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}→ Checking SSH access to AWS manager...${NC}"
    if ! ssh -i ~/.ssh/docker-swarm-key -o ConnectTimeout=5 ubuntu@${AWS_MANAGER_IP} 'echo connected' &>/dev/null; then
        echo -e "${RED}❌ ERROR: Cannot SSH to AWS manager${NC}"
        echo "Check:"
        echo "  - SSH key exists: ~/.ssh/docker-swarm-key"
        echo "  - AWS instance running: ${AWS_MANAGER_IP}"
        echo "  - Security group allows SSH from your IP"
        exit 1
    fi
    echo -e "${GREEN}✓ SSH access confirmed${NC}"
    
    echo -e "${YELLOW}→ Installing WireGuard on cloud...${NC}"
    ssh -i ~/.ssh/docker-swarm-key ubuntu@${AWS_MANAGER_IP} 'sudo apt update && sudo apt install -y wireguard'
    
    echo -e "${YELLOW}→ Deploying cloud VPN config...${NC}"
    scp -i ~/.ssh/docker-swarm-key "${GENERATED_DIR}/cloud-wg0.conf" ubuntu@${AWS_MANAGER_IP}:/tmp/wg0.conf
    ssh -i ~/.ssh/docker-swarm-key ubuntu@${AWS_MANAGER_IP} 'sudo mv /tmp/wg0.conf /etc/wireguard/wg0.conf && sudo chmod 600 /etc/wireguard/wg0.conf'
    
    echo -e "${YELLOW}→ Starting WireGuard on cloud...${NC}"
    ssh -i ~/.ssh/docker-swarm-key ubuntu@${AWS_MANAGER_IP} 'sudo wg-quick up wg0 || true'
    ssh -i ~/.ssh/docker-swarm-key ubuntu@${AWS_MANAGER_IP} 'sudo systemctl enable wg-quick@wg0'
    
    echo -e "${GREEN}✓ Cloud VPN deployed and started${NC}"
    echo ""
    
    echo -e "${YELLOW}→ Cloud VPN status:${NC}"
    ssh -i ~/.ssh/docker-swarm-key ubuntu@${AWS_MANAGER_IP} 'sudo wg show'
    echo ""
fi

# ============================================================================
# Deploy to Edge (Optional)
# ============================================================================
if [ "$DEPLOY_EDGE" = true ]; then
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Deploying to Edge (Local Machine)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}→ Checking WireGuard installation...${NC}"
    if ! command -v wg &> /dev/null; then
        echo -e "${RED}❌ ERROR: WireGuard not installed locally${NC}"
        echo "Install:"
        echo "  Ubuntu/Debian: sudo apt install wireguard"
        echo "  macOS:         brew install wireguard-tools"
        exit 1
    fi
    echo -e "${GREEN}✓ WireGuard found${NC}"
    
    echo -e "${YELLOW}→ Deploying edge VPN config...${NC}"
    sudo cp "${GENERATED_DIR}/edge-wg0.conf" /etc/wireguard/wg0.conf
    sudo chmod 600 /etc/wireguard/wg0.conf
    
    echo -e "${YELLOW}→ Starting WireGuard on edge...${NC}"
    sudo wg-quick up wg0 || true
    
    echo -e "${GREEN}✓ Edge VPN deployed and started${NC}"
    echo ""
    
    echo -e "${YELLOW}→ Edge VPN status:${NC}"
    sudo wg show
    echo ""
fi

# ============================================================================
# Summary
# ============================================================================
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  VPN Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Configuration Files:${NC}"
echo "  Cloud: ${GENERATED_DIR}/cloud-wg0.conf"
echo "  Edge:  ${GENERATED_DIR}/edge-wg0.conf"
echo ""

if [ "$DEPLOY_CLOUD" = false ] && [ "$DEPLOY_EDGE" = false ]; then
    echo -e "${YELLOW}📝 Manual Deployment:${NC}"
    echo ""
    echo "Cloud (AWS Manager):"
    echo "  scp ${GENERATED_DIR}/cloud-wg0.conf ubuntu@${AWS_MANAGER_IP}:/tmp/"
    echo "  ssh ubuntu@${AWS_MANAGER_IP}"
    echo "  sudo mv /tmp/cloud-wg0.conf /etc/wireguard/wg0.conf"
    echo "  sudo chmod 600 /etc/wireguard/wg0.conf"
    echo "  sudo wg-quick up wg0"
    echo "  sudo systemctl enable wg-quick@wg0"
    echo ""
    echo "Edge (Local):"
    echo "  sudo cp ${GENERATED_DIR}/edge-wg0.conf /etc/wireguard/wg0.conf"
    echo "  sudo chmod 600 /etc/wireguard/wg0.conf"
    echo "  sudo wg-quick up wg0"
    echo ""
fi

echo -e "${BLUE}Verification:${NC}"
echo "  From edge:"
echo "    ping 10.20.0.1                # Test VPN connectivity"
echo "    telnet 10.20.0.1 9092         # Test Kafka access"
echo ""
echo "  From cloud:"
echo "    ping 10.20.0.2                # Test edge connectivity"
echo "    sudo wg show                  # Check VPN status"
echo ""

echo -e "${BLUE}VPN Network:${NC}"
echo "  Cloud Gateway: 10.20.0.1"
echo "  Edge Client:   10.20.0.2"
echo "  Kafka Access:  10.20.0.1:9092"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Verify VPN connectivity (ping 10.20.0.1)"
echo "  2. Deploy edge sensors: cd ../edge-site && ./deploy-edge.sh"
echo "  3. Verify data flow: ../scripts/monitor-metrics.sh"
echo ""
