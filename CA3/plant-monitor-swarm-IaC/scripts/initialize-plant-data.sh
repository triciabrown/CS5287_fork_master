#!/bin/bash
# Initialize plant data in MongoDB for health score calculation

MANAGER_IP="18.219.157.100"
SSH_KEY="~/.ssh/docker-swarm-key"

echo "=========================================="
echo "  Initialize Plant Data in MongoDB"
echo "=========================================="
echo ""

echo "Creating plant records for health score calculation..."

# Get MongoDB container ID
echo "Finding MongoDB container..."
MONGO_CONTAINER=$(ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" 'docker ps -q -f name=plant-monitor_mongodb' | head -1)

if [ -z "$MONGO_CONTAINER" ]; then
    echo "❌ MongoDB container not found"
    exit 1
fi

echo "✅ Found MongoDB container: $MONGO_CONTAINER"
echo ""

# Create plant documents with care instructions
echo "Inserting plant records..."
ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" << 'ENDSSH'
docker exec $(docker ps -q -f name=plant-monitor_mongodb | head -1) mongosh \
  --quiet \
  --eval '
// Read connection string from secret
const fs = require("fs");
const connString = fs.readFileSync("/run/secrets/mongodb_connection_string", "utf8").trim();

// Connect using the secret
const db = connect(connString);

// Switch to plant_monitoring database
const plantDb = db.getSiblingDB("plant_monitoring");

print("Current plants in database:");
print(plantDb.plants.countDocuments());

// Insert plant configurations if they don'\''t exist
const plants = [
  {
    plantId: "plant-001",
    name: "Monstera Deliciosa",
    plantType: "monstera",
    location: "Living Room",
    careInstructions: {
      moistureMin: 40,
      moistureMax: 60,
      lightMin: 800,
      optimalTemperature: 22,
      temperatureMin: 18,
      temperatureMax: 27
    },
    createdAt: new Date(),
    updatedAt: new Date()
  },
  {
    plantId: "plant-002",
    name: "Snake Plant",
    plantType: "sansevieria",
    location: "Bedroom",
    careInstructions: {
      moistureMin: 20,
      moistureMax: 40,
      lightMin: 200,
      optimalTemperature: 21,
      temperatureMin: 15,
      temperatureMax: 29
    },
    createdAt: new Date(),
    updatedAt: new Date()
  }
];

// Upsert plants (insert if not exists, update if exists)
plants.forEach(plant => {
  const result = plantDb.plants.updateOne(
    { plantId: plant.plantId },
    { $set: plant },
    { upsert: true }
  );
  
  if (result.upsertedCount > 0) {
    print("✅ Inserted plant: " + plant.plantId + " (" + plant.name + ")");
  } else if (result.modifiedCount > 0) {
    print("✅ Updated plant: " + plant.plantId + " (" + plant.name + ")");
  } else {
    print("ℹ️  Plant already exists: " + plant.plantId + " (" + plant.name + ")");
  }
});

print("");
print("Total plants in database: " + plantDb.plants.countDocuments());
print("");
print("Plant records:");
plantDb.plants.find().forEach(plant => {
  print("  - " + plant.plantId + ": " + plant.name + " (" + plant.plantType + ")");
  print("    Moisture range: " + plant.careInstructions.moistureMin + "-" + plant.careInstructions.moistureMax + "%");
  print("    Light min: " + plant.careInstructions.lightMin + " lux");
});
' 2>&1
ENDSSH

echo ""
echo "=========================================="
echo "✅ Plant data initialization complete"
echo "=========================================="
echo ""
echo "The processor will now calculate health scores for:"
echo "  - plant-001 (Monstera Deliciosa)"
echo "  - plant-002 (Snake Plant)"
echo ""
echo "Health scores will appear in Prometheus within 1-2 minutes."
echo "Check Grafana dashboard for the 'Plant Health Scores' panel."
echo ""
