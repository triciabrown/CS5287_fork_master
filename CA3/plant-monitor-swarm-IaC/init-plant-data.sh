#!/bin/bash
# Initialize Plant Configuration Data in MongoDB
# This script populates the plants collection with initial plant configurations
# Required for health score calculations by the processor service

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Plant Data Initialization${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if MongoDB is accessible
echo -e "${YELLOW}→ Checking MongoDB availability...${NC}"
MONGODB_CONTAINER=$(docker ps -q -f name=plant-monitoring_mongodb)

if [ -z "$MONGODB_CONTAINER" ]; then
    echo -e "${RED}❌ MongoDB container not found${NC}"
    echo "Please ensure the plant-monitoring stack is deployed"
    exit 1
fi

echo -e "${GREEN}✓ MongoDB container found${NC}"
echo ""

# Get MongoDB credentials from secrets
echo -e "${YELLOW}→ Reading MongoDB credentials...${NC}"
MONGO_USER=$(docker exec $MONGODB_CONTAINER cat /run/secrets/mongo_root_username 2>/dev/null || echo "root")
MONGO_PASS=$(docker exec $MONGODB_CONTAINER cat /run/secrets/mongo_root_password 2>/dev/null)

if [ -z "$MONGO_PASS" ]; then
    echo -e "${RED}❌ Failed to read MongoDB credentials${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Credentials loaded from secrets${NC}"
echo ""

# Create MongoDB initialization script
echo -e "${YELLOW}→ Creating initialization script...${NC}"
cat > /tmp/init-plants.js << 'EOJS'
// Initialize plant configuration data
print('========================================');
print('Initializing Plant Configuration Data');
print('========================================');

db = db.getSiblingDB('plant_monitoring');

// Check if plants already exist
const existingCount = db.plants.countDocuments();
print('Existing plants in database: ' + existingCount);

if (existingCount > 0) {
    print('⚠️  Plants already configured, skipping initialization');
    quit(0);
}

// Plant configurations
const plants = [
    {
        plantId: 'plant-001',
        name: 'Monstera Deliciosa',
        location: 'Living Room',
        plantType: 'monstera',
        careInstructions: {
            moistureMin: 40,
            moistureMax: 60,
            lightMin: 800,
            wateringFrequency: '7 days',
            notes: 'Keep soil moderately moist, indirect bright light'
        },
        addedDate: new Date(),
        lastWatered: new Date()
    },
    {
        plantId: 'plant-002',
        name: 'Snake Plant',
        location: 'Bedroom',
        plantType: 'sansevieria',
        careInstructions: {
            moistureMin: 20,
            moistureMax: 40,
            lightMin: 200,
            wateringFrequency: '14 days',
            notes: 'Drought tolerant, low light tolerant'
        },
        addedDate: new Date(),
        lastWatered: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) // 7 days ago
    }
];

// Insert plants
print('\nInserting plant configurations...');
const result = db.plants.insertMany(plants);
print('✅ Inserted ' + result.insertedIds.length + ' plant configurations');

// Verify insertion
plants.forEach(plant => {
    const found = db.plants.findOne({ plantId: plant.plantId });
    if (found) {
        print('  ✓ ' + plant.name + ' (ID: ' + plant.plantId + ')');
        print('    Location: ' + plant.location);
        print('    Type: ' + plant.plantType);
        print('    Moisture range: ' + plant.careInstructions.moistureMin + '-' + plant.careInstructions.moistureMax + '%');
        print('    Min light: ' + plant.careInstructions.lightMin + ' lux');
    } else {
        print('  ✗ Failed to insert: ' + plant.plantId);
    }
});

print('\n========================================');
print('Initialization Complete!');
print('Health score calculations now enabled');
print('========================================');
EOJS

echo -e "${GREEN}✓ Initialization script created${NC}"
echo ""

# Copy script into container
echo -e "${YELLOW}→ Copying script to MongoDB container...${NC}"
docker cp /tmp/init-plants.js $MONGODB_CONTAINER:/tmp/init-plants.js
echo -e "${GREEN}✓ Script copied${NC}"
echo ""

# Execute the initialization script
echo -e "${YELLOW}→ Executing MongoDB initialization...${NC}"
docker exec $MONGODB_CONTAINER mongosh \
    mongodb://localhost:27017/plant_monitoring \
    --authenticationDatabase admin \
    -u "$MONGO_USER" \
    -p "$MONGO_PASS" \
    --quiet \
    /tmp/init-plants.js

INIT_RESULT=$?

# Cleanup
rm -f /tmp/init-plants.js
docker exec $MONGODB_CONTAINER rm -f /tmp/init-plants.js 2>/dev/null || true

if [ $INIT_RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Plant data initialized successfully${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  • Health scores will now calculate based on sensor readings"
    echo "  • View in Grafana: http://<MANAGER_IP>:3000"
    echo "  • Check processor logs: docker service logs plant-monitoring_processor"
    echo ""
else
    echo ""
    echo -e "${RED}❌ Plant initialization failed${NC}"
    exit 1
fi
