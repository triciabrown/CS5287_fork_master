#!/bin/bash
# create-secrets.sh
# Create Docker Swarm secrets for the plant monitoring system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================="
echo "Docker Swarm Secrets Setup"
echo "=================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running in swarm mode
if ! docker info | grep -q "Swarm: active"; then
    echo -e "${RED}ERROR: Docker Swarm is not active${NC}"
    echo "Please initialize swarm first with: docker swarm init"
    exit 1
fi

echo -e "${YELLOW}Creating Docker secrets...${NC}"
echo ""

# Function to create secret if it doesn't exist
create_secret() {
    local secret_name=$1
    local secret_value=$2
    
    if docker secret ls --format '{{.Name}}' | grep -q "^${secret_name}$"; then
        echo -e "${YELLOW}Secret '${secret_name}' already exists, skipping${NC}"
    else
        echo "$secret_value" | docker secret create "$secret_name" -
        echo -e "${GREEN}✓ Created secret: ${secret_name}${NC}"
    fi
}

# MongoDB Root Credentials
MONGO_ROOT_USER="${MONGO_ROOT_USER:-admin}"
MONGO_ROOT_PASS="${MONGO_ROOT_PASS:-$(openssl rand -base64 32)}"

create_secret "mongo_root_username" "$MONGO_ROOT_USER"
create_secret "mongo_root_password" "$MONGO_ROOT_PASS"

# MongoDB Application Credentials
MONGO_APP_USER="${MONGO_APP_USER:-plant_app}"
MONGO_APP_PASS="${MONGO_APP_PASS:-$(openssl rand -base64 24)}"

create_secret "mongo_app_username" "$MONGO_APP_USER"
create_secret "mongo_app_password" "$MONGO_APP_PASS"

# MongoDB Connection String
MONGO_CONN_STRING="mongodb://${MONGO_APP_USER}:${MONGO_APP_PASS}@mongodb:27017/plant_monitoring?authSource=plant_monitoring"
create_secret "mongodb_connection_string" "$MONGO_CONN_STRING"

# MQTT Credentials (for future enhancement)
MQTT_USER="${MQTT_USER:-mqtt_user}"
MQTT_PASS="${MQTT_PASS:-$(openssl rand -base64 16)}"

create_secret "mqtt_username" "$MQTT_USER"
create_secret "mqtt_password" "$MQTT_PASS"

echo ""
echo -e "${GREEN}=================================="
echo "Secrets Created Successfully!"
echo "==================================${NC}"
echo ""
echo "Created secrets:"
docker secret ls --format "table {{.Name}}\t{{.CreatedAt}}"
echo ""

# Optionally save credentials to file for emergency recovery
# NOTE: This is ONLY for local development/recovery. Never commit to git!
if [ "${SAVE_CREDENTIALS_FILE:-false}" = "true" ]; then
    CREDS_FILE="${SCRIPT_DIR}/.credentials"
    cat > "$CREDS_FILE" <<EOF
# Plant Monitoring System Credentials
# Generated: $(date)
# WARNING: This is a BACKUP ONLY - Keep this file secure and never commit to git!
# The actual secrets are stored securely in Docker Swarm's encrypted Raft store.

MONGO_ROOT_USER=$MONGO_ROOT_USER
MONGO_ROOT_PASS=$MONGO_ROOT_PASS

MONGO_APP_USER=$MONGO_APP_USER
MONGO_APP_PASS=$MONGO_APP_PASS

MQTT_USER=$MQTT_USER
MQTT_PASS=$MQTT_PASS
EOF

    chmod 600 "$CREDS_FILE"
    echo -e "${YELLOW}Backup credentials saved to: ${CREDS_FILE}${NC}"
    echo -e "${RED}IMPORTANT: This file is for emergency recovery only!${NC}"
    echo -e "${RED}Consider deleting it after deployment verification.${NC}"
else
    echo -e "${BLUE}ℹ Credentials NOT saved to file (secure by default)${NC}"
    echo -e "${BLUE}To save backup: SAVE_CREDENTIALS_FILE=true ./create-secrets.sh${NC}"
fi

echo ""
echo -e "${BLUE}How Docker Swarm Secrets Work (like CA1's Ansible Vault):${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Secrets encrypted at rest in Swarm's Raft log"
echo "✓ Secrets encrypted in transit (TLS) to containers"  
echo "✓ Secrets only available to authorized services"
echo "✓ Secrets mounted as files in /run/secrets/ (in-memory tmpfs)"
echo "✓ Secrets never written to disk in containers"
echo ""
echo -e "${BLUE}Accessing secrets in containers:${NC}"
echo "  MongoDB: Reads /run/secrets/mongo_root_password"
echo "  Processor: Reads /run/secrets/mongodb_connection_string"
echo ""
echo -e "${BLUE}Managing secrets:${NC}"
echo "  View:   docker secret ls"
echo "  Inspect: docker secret inspect <name> (shows metadata only)"
echo "  Remove: docker secret rm <name>"
echo ""
