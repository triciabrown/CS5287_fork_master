// MongoDB Initialization Script
// Run this after MongoDB container is started

// Connect as admin
db = db.getSiblingDB('admin');
db.auth('{{MONGO_ROOT_USERNAME}}', '{{MONGO_ROOT_PASSWORD}}');

// Create plant monitoring database and user
db = db.getSiblingDB('plant_monitoring');
db.createUser({
  user: "{{MONGO_APP_USERNAME}}",
  pwd: "{{MONGO_APP_PASSWORD}}",
  roles: [
    { role: "readWrite", db: "plant_monitoring" },
    { role: "dbAdmin", db: "plant_monitoring" }
  ]
});

// Create collections
db.createCollection("plants");
db.createCollection("sensor_readings");
db.createCollection("alerts");
db.createCollection("care_events");

// Insert sample plant data
db.plants.insertMany([
  {
    plantId: "plant-001",
    species: "Monstera Deliciosa",
    commonName: "Monstera",
    location: "Living Room",
    plantedDate: new Date("2024-03-15"),
    careInstructions: {
      moistureMin: 40,
      moistureMax: 60,
      lightRequirement: "bright-indirect",
      wateringFrequency: "weekly"
    }
  },
  {
    plantId: "plant-002",
    species: "Sansevieria trifasciata",
    commonName: "Snake Plant",
    location: "Bedroom",
    plantedDate: new Date("2024-01-10"),
    careInstructions: {
      moistureMin: 20,
      moistureMax: 40,
      lightRequirement: "low-to-bright",
      wateringFrequency: "bi-weekly"
    }
  }
]);

// Create indexes for performance
db.sensor_readings.createIndex({ "plantId": 1, "timestamp": -1 });
db.alerts.createIndex({ "plantId": 1, "timestamp": -1 });

// Verify data
db.plants.find().pretty();
db.getCollectionNames();