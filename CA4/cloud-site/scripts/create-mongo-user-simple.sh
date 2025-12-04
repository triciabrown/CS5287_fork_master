#!/bin/bash
# Simple script to create MongoDB user - run on the node where MongoDB container is
set -e

MONGO_CONTAINER=$(sudo docker ps --filter "name=plant-monitoring_mongodb" --format "{{.ID}}" | head -1)

if [ -z "$MONGO_CONTAINER" ]; then
    echo "ERROR: MongoDB container not found"
    exit 1
fi

echo "Found MongoDB container: $MONGO_CONTAINER"

# Read secrets
ROOT_USER=$(sudo docker exec $MONGO_CONTAINER cat /run/secrets/mongo_root_username)
ROOT_PASS=$(sudo docker exec $MONGO_CONTAINER cat /run/secrets/mongo_root_password)
APP_USER=$(sudo docker exec $MONGO_CONTAINER cat /run/secrets/mongo_app_username)
APP_PASS=$(sudo docker exec $MONGO_CONTAINER cat /run/secrets/mongo_app_password)

echo "Creating/updating user '$APP_USER' in plant_monitoring database..."

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

echo "✓ MongoDB user setup complete"
