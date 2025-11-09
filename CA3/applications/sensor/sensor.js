const { Kafka } = require('kafkajs');
const fs = require('fs');
const path = require('path');
const express = require('express');
const promClient = require('prom-client');

// Prometheus metrics setup
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

// Custom metrics for CA3
const sensorReadingsTotal = new promClient.Counter({
  name: 'plant_sensor_readings_total',
  help: 'Total number of sensor readings sent',
  labelNames: ['plant_id', 'plant_type', 'location'],
  registers: [register]
});

const sensorReadingsPerSecond = new promClient.Gauge({
  name: 'plant_sensor_readings_per_second',
  help: 'Current rate of sensor readings per second',
  labelNames: ['plant_id', 'plant_type'],
  registers: [register]
});

const kafkaPublishErrors = new promClient.Counter({
  name: 'plant_sensor_kafka_errors_total',
  help: 'Total number of Kafka publish errors',
  labelNames: ['plant_id', 'error_type'],
  registers: [register]
});

const sensorValueGauges = {
  moisture: new promClient.Gauge({
    name: 'plant_sensor_soil_moisture',
    help: 'Current soil moisture reading (0-100%)',
    labelNames: ['plant_id', 'plant_type'],
    registers: [register]
  }),
  light: new promClient.Gauge({
    name: 'plant_sensor_light_level',
    help: 'Current light level reading (lux)',
    labelNames: ['plant_id', 'plant_type'],
    registers: [register]
  }),
  temperature: new promClient.Gauge({
    name: 'plant_sensor_temperature_celsius',
    help: 'Current temperature reading (°C)',
    labelNames: ['plant_id', 'plant_type'],
    registers: [register]
  }),
  humidity: new promClient.Gauge({
    name: 'plant_sensor_humidity_percent',
    help: 'Current humidity reading (0-100%)',
    labelNames: ['plant_id', 'plant_type'],
    registers: [register]
  })
};

class PlantSensorSimulator {
  constructor() {
    // Load configuration from file or environment variables
    this.loadConfig();
    
    this.interval = (this.sensorInterval || parseInt(process.env.SENSOR_INTERVAL) || 30) * 1000;

    this.kafka = new Kafka({
      clientId: `plant-sensor-${this.plantId}`,
      brokers: [process.env.KAFKA_BROKERS]
    });
    this.producer = this.kafka.producer();

    // Metrics tracking
    this.readingsCount = 0;
    this.lastMetricUpdate = Date.now();

    // Plant-specific characteristics
    this.plantProfiles = {
      'monstera': {
        moistureBase: 50,
        moistureVariation: 20,
        lightBase: 600,
        tempBase: 22,
        humidityBase: 50
      },
      'sansevieria': {
        moistureBase: 30,
        moistureVariation: 15,
        lightBase: 300,
        tempBase: 20,
        humidityBase: 40
      }
    };
    
    console.log(`🌱 Initializing sensor for ${this.plantId} (${this.plantType}) at ${this.location}`);
    console.log(`📡 Kafka brokers: ${process.env.KAFKA_BROKERS}`);
    console.log(`⏱️  Sensor interval: ${this.interval / 1000} seconds`);
  }

  loadConfig() {
    // Try to load from config file first (Docker config)
    const configPaths = [
      '/app/sensor-config.json',
      '/sensor-config.json',
      path.join(__dirname, 'sensor-config.json')
    ];

    let config = null;
    for (const configPath of configPaths) {
      try {
        if (fs.existsSync(configPath)) {
          const configData = fs.readFileSync(configPath, 'utf8');
          config = JSON.parse(configData);
          console.log(`✅ Loaded config from ${configPath}`);
          break;
        }
      } catch (error) {
        console.log(`⚠️  Could not load config from ${configPath}: ${error.message}`);
      }
    }

    if (config && config.sensors && config.sensors.length > 0) {
      // Use task slot number to select sensor config (for scaling)
      const taskSlot = parseInt(process.env.TASK_SLOT || '0');
      const sensorIndex = taskSlot % config.sensors.length;
      const sensorConfig = config.sensors[sensorIndex];

      this.plantId = sensorConfig.plantId;
      this.plantType = sensorConfig.plantType;
      this.location = sensorConfig.location;
      this.sensorInterval = sensorConfig.sensorInterval;

      console.log(`📋 Using sensor config index ${sensorIndex}: ${this.plantId}`);
    } else {
      // Fallback to environment variables
      console.log('⚠️  No config file found, using environment variables');
      this.plantId = process.env.PLANT_ID || 'plant-default';
      this.plantType = process.env.PLANT_TYPE || 'monstera';
      this.location = process.env.LOCATION || 'Unknown';
      this.sensorInterval = parseInt(process.env.SENSOR_INTERVAL) || 30;
    }
  }

  async start() {
    try {
      await this.producer.connect();
      console.log(`🚀 Starting sensor simulation for ${this.plantId}`);
      
      // Start Prometheus metrics server
      this.startMetricsServer();
      
      // Send initial data immediately
      await this.generateAndSendSensorData();
      
      // Then continue at intervals
      setInterval(() => {
        this.generateAndSendSensorData();
      }, this.interval);

      // Update rate metrics every 10 seconds
      setInterval(() => {
        this.updateRateMetrics();
      }, 10000);
    } catch (error) {
      console.error('❌ Failed to start sensor:', error);
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
      res.json({ status: 'healthy', plantId: this.plantId });
    });

    app.listen(metricsPort, '0.0.0.0', () => {
      console.log(`📊 Metrics server listening on port ${metricsPort}`);
    });
  }

  updateRateMetrics() {
    const now = Date.now();
    const elapsed = (now - this.lastMetricUpdate) / 1000; // seconds
    const rate = this.readingsCount / elapsed;
    
    sensorReadingsPerSecond.set(
      { plant_id: this.plantId, plant_type: this.plantType },
      rate
    );
    
    this.readingsCount = 0;
    this.lastMetricUpdate = now;
  }

  generateRealisticSensorData() {
    const profile = this.plantProfiles[this.plantType];
    const now = new Date();
    const hourOfDay = now.getHours();
    
    // Simulate daily cycles
    const dailyMoistureVariation = Math.sin((hourOfDay / 24) * 2 * Math.PI) * 5;
    const dailyLightVariation = Math.max(0, Math.sin(((hourOfDay - 6) / 12) * Math.PI) * profile.lightBase);
    const dailyTempVariation = Math.sin(((hourOfDay - 6) / 12) * Math.PI) * 3;
    
    // Add random noise
    const moistureNoise = (Math.random() - 0.5) * 10;
    const lightNoise = Math.random() * 100;
    const tempNoise = (Math.random() - 0.5) * 2;
    const humidityNoise = (Math.random() - 0.5) * 10;

    return {
      timestamp: now.toISOString(),
      plantId: this.plantId,
      location: this.location,
      plantType: this.plantType,
      sensors: {
        soilMoisture: Math.max(0, Math.min(100, 
          profile.moistureBase + dailyMoistureVariation + moistureNoise)),
        lightLevel: Math.max(0, dailyLightVariation + lightNoise),
        temperature: profile.tempBase + dailyTempVariation + tempNoise,
        humidity: Math.max(0, Math.min(100, 
          profile.humidityBase + humidityNoise))
      }
    };
  }

  async generateAndSendSensorData() {
    const sensorData = this.generateRealisticSensorData();
    
    try {
      await this.producer.send({
        topic: 'plant-sensors',
        messages: [{
          key: this.plantId,
          value: JSON.stringify(sensorData)
        }]
      });
      
      // Update Prometheus metrics
      sensorReadingsTotal.inc({
        plant_id: this.plantId,
        plant_type: this.plantType,
        location: this.location
      });

      this.readingsCount++;

      // Update sensor value gauges
      sensorValueGauges.moisture.set(
        { plant_id: this.plantId, plant_type: this.plantType },
        sensorData.sensors.soilMoisture
      );
      sensorValueGauges.light.set(
        { plant_id: this.plantId, plant_type: this.plantType },
        sensorData.sensors.lightLevel
      );
      sensorValueGauges.temperature.set(
        { plant_id: this.plantId, plant_type: this.plantType },
        sensorData.sensors.temperature
      );
      sensorValueGauges.humidity.set(
        { plant_id: this.plantId, plant_type: this.plantType },
        sensorData.sensors.humidity
      );
      
      console.log(`Sent sensor data for ${this.plantId}:`, {
        moisture: sensorData.sensors.soilMoisture.toFixed(1),
        light: sensorData.sensors.lightLevel.toFixed(0),
        temp: sensorData.sensors.temperature.toFixed(1),
        humidity: sensorData.sensors.humidity.toFixed(1)
      });
    } catch (error) {
      console.error('Error sending sensor data:', error);
      
      // Track Kafka errors
      kafkaPublishErrors.inc({
        plant_id: this.plantId,
        error_type: error.name || 'UnknownError'
      });
    }
  }
}

// Start the sensor
const sensor = new PlantSensorSimulator();
sensor.start().catch(console.error);

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log(`Shutting down sensor ${process.env.PLANT_ID}...`);
  await sensor.producer.disconnect();
  process.exit(0);
});