const { Kafka } = require('kafkajs');
const { MongoClient } = require('mongodb');
const mqtt = require('mqtt');
const fs = require('fs');
const express = require('express');
const promClient = require('prom-client');

// Prometheus metrics setup
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

// Custom metrics for CA3
const messagesProcessedTotal = new promClient.Counter({
  name: 'plant_processor_messages_processed_total',
  help: 'Total number of messages processed from Kafka',
  labelNames: ['plant_id', 'plant_type', 'status'],
  registers: [register]
});

const processingDuration = new promClient.Histogram({
  name: 'plant_processor_processing_duration_seconds',
  help: 'Time spent processing each message',
  labelNames: ['plant_id', 'operation'],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 2, 5],
  registers: [register]
});

const pipelineLatency = new promClient.Histogram({
  name: 'plant_data_pipeline_latency_seconds',
  help: 'End-to-end latency from sensor timestamp to processing completion',
  labelNames: ['plant_id'],
  buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60],
  registers: [register]
});

const kafkaConnectionErrors = new promClient.Counter({
  name: 'plant_kafka_connection_errors_total',
  help: 'Total number of Kafka connection errors',
  labelNames: ['error_type'],
  registers: [register]
});

const mongodbConnectionErrors = new promClient.Counter({
  name: 'plant_mongodb_connection_errors_total',
  help: 'Total number of MongoDB connection errors',
  labelNames: ['error_type'],
  registers: [register]
});

const mongodbInsertsPerSecond = new promClient.Gauge({
  name: 'plant_mongodb_inserts_per_second',
  help: 'Current rate of MongoDB inserts per second',
  registers: [register]
});

const healthScoreGauge = new promClient.Gauge({
  name: 'plant_health_score',
  help: 'Current health score of each plant (0-100)',
  labelNames: ['plant_id', 'plant_type'],
  registers: [register]
});

const alertsGeneratedTotal = new promClient.Counter({
  name: 'plant_alerts_generated_total',
  help: 'Total number of alerts generated',
  labelNames: ['plant_id', 'alert_type', 'severity'],
  registers: [register]
});

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

    this.plantProfiles = {
      'monstera': { moistureMin: 40, moistureMax: 60, lightMin: 800 },
      'sansevieria': { moistureMin: 20, moistureMax: 40, lightMin: 200 }
    };
    
    // Metrics tracking
    this.insertCount = 0;
    this.lastMetricUpdate = Date.now();
    
    console.log('🔧 Configuration loaded:');
    console.log('  📡 Kafka Broker:', kafkaBroker);
    console.log('  🗄️  MongoDB URL:', mongoUrl.replace(/\/\/.*@/, '//***:***@')); // Hide credentials in logs
    console.log('  📨 MQTT Broker:', mqttBroker);
  }

  async start() {
    try {
      console.log('🚀 Starting Plant Care Processor...');
      
      // Start Prometheus metrics server
      this.startMetricsServer();
      
      console.log('📡 Connecting to Kafka...');
      await this.consumer.connect();
      await this.producer.connect();
      console.log('✅ Connected to Kafka');
      
      console.log('🗄️  Connecting to MongoDB...');
      await this.mongoClient.connect();
      console.log('✅ Connected to MongoDB');
      
      console.log('✅ All services connected successfully');
      
      // Publish MQTT discovery messages for automatic sensor setup
      await this.publishDiscoveryMessages();
      
      await this.consumer.subscribe({ topic: 'plant-sensors' });
      
      // Update rate metrics every 10 seconds
      setInterval(() => {
        this.updateRateMetrics();
      }, 10000);
      
      await this.consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          const sensorData = JSON.parse(message.value.toString());
          await this.processPlantData(sensorData);
        },
      });
    } catch (error) {
      console.error('Failed to start processor:', error);
      
      // Track connection errors
      if (error.message && error.message.includes('kafka')) {
        kafkaConnectionErrors.inc({ error_type: error.name || 'UnknownError' });
      } else if (error.message && error.message.includes('mongo')) {
        mongodbConnectionErrors.inc({ error_type: error.name || 'UnknownError' });
      }
      
      process.exit(1);
    }
  }

  startMetricsServer() {
    const app = express();
    const metricsPort = process.env.METRICS_PORT || 9091;

    app.get('/metrics', async (req, res) => {
      res.set('Content-Type', register.contentType);
      res.end(await register.metrics());
    });

    app.get('/health', (req, res) => {
      res.json({ status: 'healthy', service: 'plant-processor' });
    });

    app.listen(metricsPort, '0.0.0.0', () => {
      console.log(`📊 Metrics server listening on port ${metricsPort}`);
    });
  }

  updateRateMetrics() {
    const now = Date.now();
    const elapsed = (now - this.lastMetricUpdate) / 1000; // seconds
    const rate = this.insertCount / elapsed;
    
    mongodbInsertsPerSecond.set(rate);
    
    this.insertCount = 0;
    this.lastMetricUpdate = now;
  }

  async publishDiscoveryMessages() {
    console.log('Publishing MQTT discovery messages...');
    const plants = ['001', '002'];
    const sensors = [
      { name: 'Moisture', key: 'moisture', unit: '%', deviceClass: 'humidity', icon: 'mdi:water-percent' },
      { name: 'Health', key: 'health', unit: 'pts', deviceClass: null, icon: 'mdi:leaf' },
      { name: 'Light', key: 'light', unit: 'lux', deviceClass: 'illuminance', icon: 'mdi:lightbulb' },
      { name: 'Temperature', key: 'temperature', unit: '°C', deviceClass: 'temperature', icon: 'mdi:thermometer' },
      { name: 'Status', key: 'status', unit: null, deviceClass: null, icon: 'mdi:sprout' }
    ];

    for (const plant of plants) {
      for (const sensor of sensors) {
        await this.publishDiscovery(plant, sensor);
        console.log(`Published discovery for Plant ${plant} ${sensor.name}`);
      }
    }
    console.log('MQTT discovery messages published successfully');
  }

  async publishDiscovery(plantId, sensor) {
    const discoveryTopic = `homeassistant/sensor/plant_${plantId}_${sensor.key}/config`;
    const config = {
      name: `Plant ${plantId} ${sensor.name}`,
      state_topic: `homeassistant/sensor/plant_plant_${plantId}/state`,
      value_template: `{{ value_json.${sensor.key} }}`,
      unique_id: `plant_${plantId}_${sensor.key}`,
      device: {
        identifiers: [`plant_${plantId}`],
        name: `Plant ${plantId}`,
        manufacturer: 'CS5287 IoT',
        model: 'Smart Plant Monitor'
      }
    };

    if (sensor.unit) config.unit_of_measurement = sensor.unit;
    if (sensor.deviceClass) config.device_class = sensor.deviceClass;
    if (sensor.icon) config.icon = sensor.icon;

    this.mqttClient.publish(discoveryTopic, JSON.stringify(config), { retain: true });
  }

  async autoRegisterPlant(sensorData) {
    // Auto-register new plant with default care instructions based on plant type
    // This implements IoT auto-discovery pattern - plants self-register on first sensor data
    
    const plantType = sensorData.plantType || 'unknown';
    
    // Default care instructions by plant type
    const defaultCareInstructions = {
      'monstera': {
        moistureMin: 40,
        moistureMax: 60,
        lightMin: 800,
        temperatureMin: 18,
        temperatureMax: 24,
        humidityMin: 50,
        humidityMax: 70,
        wateringFrequency: '7 days',
        notes: 'Keep soil moderately moist, indirect bright light'
      },
      'sansevieria': {
        moistureMin: 20,
        moistureMax: 40,
        lightMin: 200,
        temperatureMin: 15,
        temperatureMax: 27,
        humidityMin: 30,
        humidityMax: 50,
        wateringFrequency: '14 days',
        notes: 'Drought tolerant, low light tolerant'
      },
      'pothos': {
        moistureMin: 30,
        moistureMax: 50,
        lightMin: 400,
        temperatureMin: 17,
        temperatureMax: 30,
        humidityMin: 40,
        humidityMax: 60,
        wateringFrequency: '5-7 days',
        notes: 'Easy care, tolerates low light'
      },
      'unknown': {
        moistureMin: 30,
        moistureMax: 60,
        lightMin: 500,
        temperatureMin: 15,
        temperatureMax: 25,
        humidityMin: 40,
        humidityMax: 70,
        wateringFrequency: '7 days',
        notes: 'Generic plant care defaults - configure for specific needs'
      }
    };

    const careInstructions = defaultCareInstructions[plantType] || defaultCareInstructions['unknown'];
    
    const newPlant = {
      plantId: sensorData.plantId,
      name: `${plantType.charAt(0).toUpperCase() + plantType.slice(1)} (${sensorData.plantId})`,
      location: sensorData.location || 'Unknown Location',
      plantType: plantType,
      careInstructions: careInstructions,
      addedDate: new Date(),
      autoRegistered: true,
      firstSeenTimestamp: sensorData.timestamp,
      lastWatered: new Date() // Assume recently watered
    };

    try {
      const result = await this.mongoClient.db('plant_monitoring')
        .collection('plants')
        .insertOne(newPlant);
      
      console.log(`✅ Auto-registered plant ${sensorData.plantId} (${plantType}) with default care instructions`);
      
      // Return the newly created plant document
      return newPlant;
    } catch (error) {
      console.error(`❌ Failed to auto-register plant ${sensorData.plantId}:`, error);
      return null;
    }
  }

  async processPlantData(sensorData) {
    const startTime = Date.now();
    const sensorTimestamp = new Date(sensorData.timestamp).getTime();
    
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
      const dbStartTime = Date.now();
      const result = await this.mongoClient.db('plant_monitoring')
        .collection('sensor_readings')
        .insertOne({
          ...sensorData,
          processedAt: new Date()
        });
      const dbDuration = (Date.now() - dbStartTime) / 1000;
      
      processingDuration.observe(
        { plant_id: sensorData.plantId, operation: 'mongodb_insert' },
        dbDuration
      );
      
      this.insertCount++;
      console.log('Sensor data stored successfully:', result.insertedId);

      // Analyze plant health
      console.log('Looking for plant configuration...');
      let plant = await this.mongoClient.db('plant_monitoring')
        .collection('plants')
        .findOne({ plantId: sensorData.plantId });
      
      // Auto-create plant record if it doesn't exist (IoT auto-discovery pattern)
      if (!plant) {
        console.log(`Plant ${sensorData.plantId} not found - auto-creating configuration...`);
        plant = await this.autoRegisterPlant(sensorData);
        console.log('Plant auto-registered:', plant ? 'Yes' : 'No');
      } else {
        console.log('Plant found:', 'Yes');
      }

      if (plant) {
        const healthAnalysis = this.analyzePlantHealth(sensorData, plant.careInstructions);
        
        console.log(`Health analysis for ${sensorData.plantId}:`, healthAnalysis);
        
        // Update health score metric
        healthScoreGauge.set(
          { plant_id: sensorData.plantId, plant_type: sensorData.plantType },
          healthAnalysis.healthScore
        );
        
        // Send alerts if needed
        if (healthAnalysis.alerts.length > 0) {
          await this.sendAlerts(sensorData.plantId, healthAnalysis.alerts);
        }

        // Update Home Assistant via MQTT
        await this.updateHomeAssistant(sensorData.plantId, {
          moisture: sensorData.sensors.soilMoisture,
          health: healthAnalysis.healthScore,
          light: sensorData.sensors.lightLevel,
          temperature: sensorData.sensors.temperature,
          status: healthAnalysis.status
        });
      }
      
      // Track successful processing
      messagesProcessedTotal.inc({
        plant_id: sensorData.plantId,
        plant_type: sensorData.plantType,
        status: 'success'
      });
      
      // Calculate and record end-to-end latency
      const totalLatency = (Date.now() - sensorTimestamp) / 1000;
      pipelineLatency.observe(
        { plant_id: sensorData.plantId },
        totalLatency
      );
      
      // Record total processing duration
      const processingTime = (Date.now() - startTime) / 1000;
      processingDuration.observe(
        { plant_id: sensorData.plantId, operation: 'total_processing' },
        processingTime
      );
      
    } catch (error) {
      console.error('Error processing plant data:', error);
      
      // Track failed processing
      messagesProcessedTotal.inc({
        plant_id: sensorData.plantId,
        plant_type: sensorData.plantType || 'unknown',
        status: 'error'
      });
      
      // Track specific error types
      if (error.message && error.message.toLowerCase().includes('mongo')) {
        mongodbConnectionErrors.inc({ error_type: error.name || 'UnknownError' });
      } else if (error.message && error.message.toLowerCase().includes('kafka')) {
        kafkaConnectionErrors.inc({ error_type: error.name || 'UnknownError' });
      }
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
      // Track alert generation
      alertsGeneratedTotal.inc({
        plant_id: plantId,
        alert_type: alert.type,
        severity: alert.severity
      });
      
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