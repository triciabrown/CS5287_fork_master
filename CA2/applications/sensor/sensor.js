const { Kafka } = require('kafkajs');
const fs = require('fs');
const path = require('path');

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
      
      // Send initial data immediately
      await this.generateAndSendSensorData();
      
      // Then continue at intervals
      setInterval(() => {
        this.generateAndSendSensorData();
      }, this.interval);
    } catch (error) {
      console.error('❌ Failed to start sensor:', error);
      process.exit(1);
    }
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
      
      console.log(`Sent sensor data for ${this.plantId}:`, {
        moisture: sensorData.sensors.soilMoisture.toFixed(1),
        light: sensorData.sensors.lightLevel.toFixed(0),
        temp: sensorData.sensors.temperature.toFixed(1),
        humidity: sensorData.sensors.humidity.toFixed(1)
      });
    } catch (error) {
      console.error('Error sending sensor data:', error);
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