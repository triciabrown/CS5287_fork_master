#!/bin/bash
# Create Docker Swarm Configs for CA4 Plant Monitoring System
# This script creates configs that are mounted into containers

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "Docker Swarm Configs Setup"
echo "=========================================="
echo ""

# ============================================================================
# Mosquitto Configuration
# ============================================================================
if ! sudo docker config inspect mosquitto_config &>/dev/null; then
    echo "listener 1883
allow_anonymous true" | sudo docker config create mosquitto_config - 2>&1
    echo -e "${GREEN}✓ Created config: mosquitto_config${NC}"
else
    echo -e "${CYAN}ℹ Config mosquitto_config already exists${NC}"
fi

# ============================================================================
# MongoDB Initialization - REMOVED
# ============================================================================
# NOTE: MongoDB user creation is now handled by verify_mongodb_users() in deploy-all.sh
# This ensures users are created with credentials from Docker secrets
# MongoDB's init scripts run before secrets are available, so we can't use them
echo -e "${CYAN}ℹ MongoDB users will be created by deploy-all.sh verify_mongodb_users()${NC}"

# ============================================================================
# Home Assistant Configuration
# ============================================================================
if ! sudo docker config inspect homeassistant_config_yaml &>/dev/null; then
    echo "default_config:
http:
  server_port: 8123" | sudo docker config create homeassistant_config_yaml - 2>&1
    echo -e "${GREEN}✓ Created config: homeassistant_config_yaml${NC}"
else
    echo -e "${CYAN}ℹ Config homeassistant_config_yaml already exists${NC}"
fi

echo ""
echo "=========================================="
echo "Configs Setup Complete"
echo "=========================================="
echo ""
echo "Created configs:"
sudo docker config ls

echo ""
echo -e "${CYAN}Note: MongoDB init config only runs on first container start${NC}"
echo -e "${CYAN}For existing deployments, deploy-all.sh will verify and create users${NC}"
