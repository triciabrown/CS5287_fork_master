#!/bin/bash
# Verify and create MongoDB application user if needed
# This script should be run ON THE NODE where MongoDB container is running

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== MongoDB User Verification Script ==="

# Find MongoDB container
MONGO_CONTAINER=$(sudo docker ps --filter "name=plant-monitoring_mongodb" --format "{{.ID}}" | head -1)

if [ -z "$MONGO_CONTAINER" ]; then
    echo -e "${RED}ERROR: MongoDB container not found on this node${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found MongoDB container: $MONGO_CONTAINER${NC}"

# Read credentials from Docker secrets
echo "Reading credentials from Docker secrets..."
APP_USER=$(sudo docker exec $MONGO_CONTAINER cat /run/secrets/mongo_app_username 2>/dev/null)
APP_PASS=$(sudo docker exec $MONGO_CONTAINER cat /run/secrets/mongo_app_password 2>/dev/null)
ROOT_USER=$(sudo docker exec $MONGO_CONTAINER cat /run/secrets/mongo_root_username 2>/dev/null)
ROOT_PASS=$(sudo docker exec $MONGO_CONTAINER cat /run/secrets/mongo_root_password 2>/dev/null)

if [ -z "$APP_USER" ] || [ -z "$APP_PASS" ] || [ -z "$ROOT_USER" ] || [ -z "$ROOT_PASS" ]; then
    echo -e "${RED}ERROR: Could not read secrets from MongoDB container${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Secrets loaded successfully${NC}"
echo "Creating/updating user '$APP_USER' in plant_monitoring database..."

# Use the admin database approach with single-line mongosh command
sudo docker exec $MONGO_CONTAINER mongosh admin --quiet --eval "
db.auth('$ROOT_USER', '$ROOT_PASS');
db = db.getSiblingDB('plant_monitoring');
try { db.dropUser('$APP_USER'); print('Dropped existing user'); } catch(e) { print('User did not exist'); }
db.createUser({user: '$APP_USER', pwd: '$APP_PASS', roles: [{role: 'readWrite', db: 'plant_monitoring'}]});
print('✓ User created');
print('Testing authentication...');
db.auth('$APP_USER', '$APP_PASS');
print('✓ Authentication successful!');
"

echo -e "${GREEN}✓ MongoDB user setup complete${NC}"
