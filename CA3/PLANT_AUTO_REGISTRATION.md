# Plant Auto-Registration Architecture

## Overview

The Plant Monitoring System implements **IoT Auto-Discovery** pattern where plants automatically register themselves when they first send sensor data. This eliminates manual configuration and follows industry best practices for IoT device management.

## How It Works

### 1. Sensor Data Flow

```
Sensor Service → Kafka → Processor → MongoDB
                           ↓
                    Auto-Register Plant
                    (if not exists)
```

### 2. Auto-Registration Logic

When the processor receives sensor data:

1. **Check for existing plant**: Query MongoDB `plants` collection by `plantId`
2. **If plant exists**: Use existing care instructions for health analysis
3. **If plant NOT exists**: 
   - Create new plant record with defaults based on `plantType`
   - Use sensible care thresholds for that plant species
   - Mark as `autoRegistered: true`
   - Continue processing normally

### 3. Default Care Instructions

The processor includes built-in defaults for common plant types:

| Plant Type | Moisture Range | Temperature Range | Light Min | Watering Frequency |
|------------|---------------|-------------------|-----------|-------------------|
| **Monstera** | 40-60% | 18-24°C | 800 lux | 7 days |
| **Sansevieria** (Snake Plant) | 20-40% | 15-27°C | 200 lux | 14 days |
| **Pothos** | 30-50% | 17-30°C | 400 lux | 5-7 days |
| **Unknown** | 30-60% | 15-25°C | 500 lux | 7 days |

## Code Implementation

### Location
`CA3/applications/processor/app.js`

### Key Method: `autoRegisterPlant()`

```javascript
async autoRegisterPlant(sensorData) {
  const plantType = sensorData.plantType || 'unknown';
  const careInstructions = defaultCareInstructions[plantType];
  
  const newPlant = {
    plantId: sensorData.plantId,
    name: `${plantType} (${sensorData.plantId})`,
    location: sensorData.location || 'Unknown Location',
    plantType: plantType,
    careInstructions: careInstructions,
    addedDate: new Date(),
    autoRegistered: true,
    firstSeenTimestamp: sensorData.timestamp
  };

  await this.mongoClient.db('plant_monitoring')
    .collection('plants')
    .insertOne(newPlant);
    
  return newPlant;
}
```

### Integration in `processPlantData()`

```javascript
// Look for plant configuration
let plant = await db.collection('plants').findOne({ plantId });

// Auto-create if doesn't exist
if (!plant) {
  plant = await this.autoRegisterPlant(sensorData);
}

// Continue with health analysis
if (plant) {
  const healthAnalysis = this.analyzePlantHealth(sensorData, plant.careInstructions);
  // ... rest of processing
}
```

## Benefits

### ✅ Zero-Touch Provisioning
- New sensors start working immediately
- No manual database initialization required
- System is truly plug-and-play

### ✅ IoT Best Practices
- Follows industry standard auto-discovery pattern
- Similar to MQTT auto-discovery used by Home Assistant
- Scalable to hundreds/thousands of plants

### ✅ Graceful Defaults
- Sensible care thresholds based on plant species
- System remains functional even with unknown plant types
- Can be refined later through admin interface

### ✅ Deployment Simplicity
- Removed `init-plant-data.sh` script
- Fewer moving parts in deployment
- One less thing to fail

## Sensor Data Requirements

For auto-registration to work, sensor data must include:

```json
{
  "plantId": "plant-001",        // Required: Unique identifier
  "plantType": "monstera",       // Required: Plant species
  "location": "Living Room",     // Optional: Physical location
  "timestamp": "2025-11-07T...", // Required: ISO timestamp
  "sensors": {
    "soilMoisture": 45,
    "temperature": 22,
    "lightLevel": 850
  }
}
```

## MongoDB Schema

### Auto-Registered Plant Document

```javascript
{
  "_id": ObjectId("..."),
  "plantId": "plant-001",
  "name": "Monstera (plant-001)",
  "location": "Living Room",
  "plantType": "monstera",
  "careInstructions": {
    "moistureMin": 40,
    "moistureMax": 60,
    "lightMin": 800,
    "temperatureMin": 18,
    "temperatureMax": 24,
    "humidityMin": 50,
    "humidityMax": 70,
    "wateringFrequency": "7 days",
    "notes": "Keep soil moderately moist, indirect bright light"
  },
  "addedDate": ISODate("2025-11-07T..."),
  "autoRegistered": true,           // Flag indicating auto-creation
  "firstSeenTimestamp": "2025-11-07T...",
  "lastWatered": ISODate("2025-11-07T...")
}
```

## Manual Configuration (Optional)

While plants auto-register, you can still manually configure them:

### Via MongoDB Shell

```javascript
// Connect to MongoDB
docker exec -it <mongodb_container> mongosh \
  -u root -p <password> --authenticationDatabase admin

// Update plant configuration
use plant_monitoring
db.plants.updateOne(
  { plantId: "plant-001" },
  { 
    $set: { 
      name: "My Favorite Monstera",
      location: "Office Window",
      "careInstructions.moistureMin": 45,
      "careInstructions.moistureMax": 65
    },
    $unset: { autoRegistered: "" }
  }
)
```

### Via Home Assistant (Future Enhancement)

Could add UI in Home Assistant to edit plant configurations:
- Set custom names and locations
- Adjust care thresholds
- Set watering schedules
- Add care notes

## Comparison: Old vs New Approach

### ❌ Old Approach (init-plant-data.sh)
```
Deploy Infrastructure
    ↓
Deploy Application Stack
    ↓
Wait for MongoDB to be ready
    ↓
Run init-plant-data.sh script    ← Manual step, could fail
    ↓
Sensor data starts flowing
    ↓
Health scores calculated
```

**Problems:**
- Extra deployment step
- Timing dependency (MongoDB must be ready)
- Script could fail silently
- Hardcoded plant configurations
- Not scalable to dynamic sensors

### ✅ New Approach (Auto-Registration)
```
Deploy Infrastructure
    ↓
Deploy Application Stack
    ↓
Sensor data starts flowing
    ↓
Plants auto-register on first data    ← Automatic
    ↓
Health scores calculated immediately
```

**Benefits:**
- Fully automated
- No timing dependencies
- Self-healing (works even if MongoDB restarts)
- Dynamic and scalable
- Follows IoT standards

## Testing

### Verify Auto-Registration

1. **Check processor logs for auto-registration:**
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP>
docker service logs plant-monitoring_processor | grep "Auto-registered"
```

Expected output:
```
✅ Auto-registered plant plant-001 (monstera) with default care instructions
✅ Auto-registered plant plant-002 (sansevieria) with default care instructions
```

2. **Verify plants in MongoDB:**
```bash
docker exec $(docker ps -q -f name=plant-monitoring_mongodb) mongosh \
  -u root -p <password> --authenticationDatabase admin \
  plant_monitoring --eval "db.plants.find().pretty()"
```

Expected: 2 plant documents with `autoRegistered: true`

3. **Check health scores in Grafana:**
- Open Grafana: `http://<MANAGER_IP>:3000`
- Navigate to Plant Monitoring dashboard
- Panel: "Plant Health Scores"
- Should show health scores for auto-registered plants

## Future Enhancements

### 1. Learning from Historical Data
```javascript
// Adjust care thresholds based on plant performance
async optimizeCareInstructions(plantId) {
  const readings = await db.collection('sensor_readings')
    .find({ plantId })
    .sort({ timestamp: -1 })
    .limit(1000)
    .toArray();
    
  // Calculate optimal ranges from healthy periods
  const optimalMoisture = calculateOptimalRange(readings, 'soilMoisture');
  
  await db.collection('plants').updateOne(
    { plantId },
    { $set: { 'careInstructions.moistureMin': optimalMoisture.min } }
  );
}
```

### 2. Plant Type Detection via ML
```javascript
// Infer plant type from sensor patterns
async inferPlantType(readings) {
  const features = extractFeatures(readings);
  const predictedType = await mlModel.predict(features);
  return predictedType;
}
```

### 3. REST API for Plant Management
```javascript
// Express endpoint for updating plants
app.put('/api/plants/:plantId', async (req, res) => {
  const { name, location, careInstructions } = req.body;
  await db.collection('plants').updateOne(
    { plantId: req.params.plantId },
    { $set: { name, location, careInstructions } }
  );
  res.json({ success: true });
});
```

## Related Files

- **Processor Logic**: `CA3/applications/processor/app.js`
- **Sensor Data Generator**: `CA3/applications/sensor/app.js`
- **MongoDB Schema**: Defined in auto-registration code
- **Home Assistant Discovery**: `publishDiscoveryMessages()` in processor

## References

- [MQTT Auto-Discovery](https://www.home-assistant.io/docs/mqtt/discovery/)
- [IoT Device Provisioning Best Practices](https://aws.amazon.com/iot/solutions/device-provisioning/)
- [MongoDB Upsert Operations](https://www.mongodb.com/docs/manual/reference/method/db.collection.updateOne/)

---

**Last Updated**: November 7, 2025  
**Author**: CS5287 - Cloud Systems  
**Status**: ✅ Implemented and Production-Ready
