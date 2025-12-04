const { Kafka } = require('kafkajs');
const { MongoClient } = require('mongodb');
const mqtt = require('mqtt');
const fs = require('fs');

class PlantCareProcessor {
  constructor() {
    // Use environment variables for configuration
    const kafkaBroker = process.env.KAFKA_BROKER || '10.0.143.200:9092';
    
    // Read MongoDB URL from Docker secret file if available
    let mongoUrl = process.env.MONGODB_URL;
    if (process.env.MONGODB_URL_FILE) {
      try {
        mongoUrl = fs.readFileSync(process.env.MONGODB_URL_FILE, 'utf8').trim();
        console.log('✅ Loaded MongoDB URL from secret file');
      } catch (error) {
        console.error('⚠️  Failed to read MongoDB secret file:', error.message);
        mongoUrl = 'mongodb://plantuser:PlantUserPass123!@mongodb:27017/plant_monitoring';
      }
    }
    if (!mongoUrl) {
      mongoUrl = 'mongodb://plantuser:PlantUserPass123!@mongodb:27017/plant_monitoring';
    }
    
    const mqttBroker = process.env.MQTT_BROKER || 'mqtt://mosquitto:1883';
    
    // Kafka configuration
    this.kafka = new Kafka({
      clientId: 'plant-care-processor',
      brokers: [kafkaBroker]
    });
    this.consumer = this.kafka.consumer({ groupId: 'plant-processor-group' });
    this.producer = this.kafka.producer();

    // MongoDB configuration
    this.mongoUrl = mongoUrl;
    this.mongoClient = new MongoClient(this.mongoUrl);

    // MQTT configuration
    this.mqttClient = mqtt.connect(mqttBroker);

    // Default care instructions by plant type
    this.plantProfiles = {
      'monstera': { 
        moistureMin: 40, moistureMax: 60, 
        lightMin: 500, lightMax: 700,
        tempMin: 18, tempMax: 26
      },
      'sansevieria': { 
        moistureMin: 20, moistureMax: 40, 
        lightMin: 200, lightMax: 400,
        tempMin: 16, tempMax: 24
      },
      'tomato': {
        moistureMin: 40, moistureMax: 70,
        lightMin: 400, lightMax: 800,
        tempMin: 18, tempMax: 28
      },
      'basil': {
        moistureMin: 35, moistureMax: 65,
        lightMin: 600, lightMax: 1000,
        tempMin: 20, tempMax: 30
      },
      'lettuce': {
        moistureMin: 45, moistureMax: 75,
        lightMin: 300, lightMax: 600,
        tempMin: 15, tempMax: 22
      }
    };
    
    console.log('🔧 Configuration loaded:');
    console.log('  📡 Kafka Broker:', kafkaBroker);
    console.log('  🗄️  MongoDB URL:', mongoUrl.replace(/\/\/.*@/, '//***:***@')); // Hide credentials in logs
    console.log('  📨 MQTT Broker:', mqttBroker);
  }

  async start() {
    try {
      console.log('🚀 Starting Plant Care Processor...');
      
      // CA4: Add startup delay to wait for Kafka DNS propagation
      const startupDelay = parseInt(process.env.STARTUP_DELAY || '0', 10);
      if (startupDelay > 0) {
        console.log(`⏳ Waiting ${startupDelay} seconds for services to initialize...`);
        await new Promise(resolve => setTimeout(resolve, startupDelay * 1000));
        console.log('✅ Startup delay complete');
      }
      
      console.log('📡 Connecting to Kafka...');
      await this.consumer.connect();
      await this.producer.connect();
      console.log('✅ Connected to Kafka');
      
      console.log('🗄️  Connecting to MongoDB...');
      await this.mongoClient.connect();
      console.log('✅ Connected to MongoDB');
      
      console.log('✅ All services connected successfully');
      
      // Track which sensors we've published discovery for
      this.discoveredSensors = new Set();
      
      await this.consumer.subscribe({ topic: 'plant-sensors' });
      
      await this.consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          const sensorData = JSON.parse(message.value.toString());
          await this.processPlantData(sensorData);
        },
      });
    } catch (error) {
      console.error('Failed to start processor:', error);
      process.exit(1);
    }
  }

  async publishDiscoveryForSensor(sensorId) {
    // Only publish once per sensor
    if (this.discoveredSensors.has(sensorId)) {
      return;
    }

    console.log(`Publishing MQTT discovery for sensor: ${sensorId}`);
    const sensors = [
      { name: 'Moisture', key: 'moisture', unit: '%', deviceClass: 'humidity', icon: 'mdi:water-percent' },
      { name: 'Health', key: 'health', unit: 'pts', deviceClass: null, icon: 'mdi:leaf' },
      { name: 'Light', key: 'light', unit: 'lux', deviceClass: 'illuminance', icon: 'mdi:lightbulb' },
      { name: 'Temperature', key: 'temperature', unit: '°C', deviceClass: 'temperature', icon: 'mdi:thermometer' },
      { name: 'Humidity', key: 'humidity', unit: '%', deviceClass: 'humidity', icon: 'mdi:water' },
      { name: 'Status', key: 'status', unit: null, deviceClass: null, icon: 'mdi:sprout' }
    ];

    for (const sensor of sensors) {
      await this.publishDiscovery(sensorId, sensor);
    }
    
    this.discoveredSensors.add(sensorId);
    console.log(`Discovery complete for ${sensorId}`);
  }

  async publishDiscovery(sensorId, sensor) {
    // Normalize sensor ID for topic (replace - with _)
    const normalizedId = sensorId.replace(/-/g, '_');
    
    // Create friendly display name (e.g., "Plant 001" instead of "plant-001")
    const displayName = sensorId.split('-').map((part, idx) => 
      idx === 0 ? part.charAt(0).toUpperCase() + part.slice(1) : part.toUpperCase()
    ).join(' ');
    
    const discoveryTopic = `homeassistant/sensor/${normalizedId}_${sensor.key}/config`;
    const config = {
      name: `${displayName} ${sensor.name}`,
      state_topic: `homeassistant/sensor/plant_${normalizedId}/state`,
      value_template: `{{ value_json.${sensor.key} }}`,
      unique_id: `${normalizedId}_${sensor.key}`,
      device: {
        identifiers: [normalizedId],
        name: displayName,
        manufacturer: 'CS5287 IoT',
        model: 'Smart Plant Monitor'
      }
    };

    if (sensor.unit) config.unit_of_measurement = sensor.unit;
    if (sensor.deviceClass) config.device_class = sensor.deviceClass;
    if (sensor.icon) config.icon = sensor.icon;

    this.mqttClient.publish(discoveryTopic, JSON.stringify(config), { retain: true });
  }

  async processPlantData(sensorData) {
    // Publish discovery messages for this sensor (only once)
    await this.publishDiscoveryForSensor(sensorData.plantId);
    
    console.log(`Processing data for ${sensorData.plantId}:`, {
      plantId: sensorData.plantId,
      timestamp: sensorData.timestamp,
      location: sensorData.location,
      plantType: sensorData.plantType,
      sensors: sensorData.sensors
    });
    
    try {
      // Store raw sensor data
      console.log('Storing sensor data to MongoDB...');
      const result = await this.mongoClient.db('plant_monitoring')
        .collection('sensor_readings')
        .insertOne({
          ...sensorData,
          processedAt: new Date()
        });
      console.log('Sensor data stored successfully:', result.insertedId);

      // Always publish sensor data to Home Assistant (even without plant config)
      const basicMqttData = {
        moisture: sensorData.sensors.soilMoisture,
        light: sensorData.sensors.lightLevel,
        temperature: sensorData.sensors.temperature,
        humidity: sensorData.sensors.humidity
      };

      // Analyze plant health (only if plant configuration exists)
      console.log('Looking for plant configuration...');
      const plant = await this.mongoClient.db('plant_monitoring')
        .collection('plants')
        .findOne({ plantId: sensorData.plantId });
      console.log('Plant found:', plant ? 'Yes' : 'No');

      if (plant) {
        const healthAnalysis = this.analyzePlantHealth(sensorData, plant.careInstructions);
        
        console.log(`Health analysis for ${sensorData.plantId}:`, healthAnalysis);
        
        // Send alerts if needed
        if (healthAnalysis.alerts.length > 0) {
          await this.sendAlerts(sensorData.plantId, healthAnalysis.alerts);
        }

        // Add health data to MQTT payload
        basicMqttData.health = healthAnalysis.healthScore;
        basicMqttData.status = healthAnalysis.status;
      } else if (this.plantProfiles[sensorData.plantType]) {
        // No plant config in DB - use default profile based on plant type
        console.log(`Using default care profile for ${sensorData.plantType}`);
        const healthAnalysis = this.analyzePlantHealth(sensorData, this.plantProfiles[sensorData.plantType]);
        
        console.log(`Health analysis for ${sensorData.plantId}:`, healthAnalysis);
        
        // Add health data to MQTT payload
        basicMqttData.health = healthAnalysis.healthScore;
        basicMqttData.status = healthAnalysis.status;
      } else {
        // No plant config and unknown plant type
        console.log(`Unknown plant type: ${sensorData.plantType}`);
        basicMqttData.health = 'unknown';
        basicMqttData.status = 'unconfigured';
      }

      // Update Home Assistant via MQTT (always, regardless of plant config)
      await this.updateHomeAssistant(sensorData.plantId, basicMqttData);
      console.log(`Published MQTT data for ${sensorData.plantId}`);
    } catch (error) {
      console.error('Error processing plant data:', error);
    }
  }

  analyzePlantHealth(sensorData, careInstructions) {
    const alerts = [];
    let healthScore = 100;

    // Check moisture levels
    if (sensorData.sensors.soilMoisture < careInstructions.moistureMin) {
      alerts.push({ type: 'WATER_NEEDED', severity: 'HIGH', message: 'Soil moisture too low' });
      healthScore -= 30;
    }

    if (sensorData.sensors.soilMoisture > careInstructions.moistureMax) {
      alerts.push({ type: 'OVERWATERED', severity: 'MEDIUM', message: 'Soil moisture too high' });
      healthScore -= 20;
    }

    // Check light levels
    if (sensorData.sensors.lightLevel < 200) {
      alerts.push({ type: 'INSUFFICIENT_LIGHT', severity: 'MEDIUM', message: 'Light level too low' });
      healthScore -= 15;
    }

    const status = healthScore > 80 ? 'healthy' : healthScore > 60 ? 'needs_attention' : 'critical';

    return { healthScore, status, alerts };
  }

  async sendAlerts(plantId, alerts) {
    for (const alert of alerts) {
      // Store alert in MongoDB
      await this.mongoClient.db('plant_monitoring')
        .collection('alerts')
        .insertOne({
          plantId,
          timestamp: new Date(),
          ...alert
        });

      // Send to Kafka for other processors
      await this.producer.send({
        topic: 'plant-alerts',
        messages: [{
          key: plantId,
          value: JSON.stringify({
            plantId,
            timestamp: new Date(),
            ...alert
          })
        }]
      });
    }
  }

  async updateHomeAssistant(plantId, data) {
    const topic = `homeassistant/sensor/plant_${plantId.replace(/-/g, '_')}/state`;
    this.mqttClient.publish(topic, JSON.stringify(data));
  }
}

// Start the processor
const processor = new PlantCareProcessor();
processor.start().catch(console.error);

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('Shutting down processor...');
  await processor.consumer.disconnect();
  await processor.producer.disconnect();
  await processor.mongoClient.close();
  processor.mqttClient.end();
  process.exit(0);
});