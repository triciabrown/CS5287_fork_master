const { Kafka } = require('kafkajs');
const fs = require('fs');
const path = require('path');

class PlantSensorSimulator {
  constructor() {
    // Load configuration from file or environment variables
    this.loadConfig();
    
    this.interval = (this.sensorInterval || parseInt(process.env.SCAN_INTERVAL) || 10) * 1000;

    // Parse Kafka broker(s) - can be comma-separated list
    const brokerString = process.env.KAFKA_BROKER || process.env.KAFKA_BROKERS || 'localhost:9092';
    this.brokers = brokerString.split(',').map(b => b.trim());
    
    console.log(`🔧 DEBUG: brokerString = "${brokerString}"`);
    console.log(`🔧 DEBUG: brokers array = [${this.brokers.join(', ')}]`);

    this.kafka = new Kafka({
      clientId: `plant-sensor-${this.plantId}`,
      brokers: this.brokers
    });
    this.producer = this.kafka.producer();

    // Plant-specific characteristics with configurable ranges
    this.plantProfiles = {
      'tomato': {
        tempMin: parseFloat(process.env.TEMP_MIN) || 18,
        tempMax: parseFloat(process.env.TEMP_MAX) || 28,
        humidityMin: parseFloat(process.env.HUMIDITY_MIN) || 60,
        humidityMax: parseFloat(process.env.HUMIDITY_MAX) || 85,
        moistureMin: parseFloat(process.env.SOIL_MOISTURE_MIN) || 40,
        moistureMax: parseFloat(process.env.SOIL_MOISTURE_MAX) || 70,
        lightMin: parseFloat(process.env.LIGHT_MIN) || 400,
        lightMax: parseFloat(process.env.LIGHT_MAX) || 800
      },
      'basil': {
        tempMin: parseFloat(process.env.TEMP_MIN) || 20,
        tempMax: parseFloat(process.env.TEMP_MAX) || 30,
        humidityMin: parseFloat(process.env.HUMIDITY_MIN) || 50,
        humidityMax: parseFloat(process.env.HUMIDITY_MAX) || 70,
        moistureMin: parseFloat(process.env.SOIL_MOISTURE_MIN) || 35,
        moistureMax: parseFloat(process.env.SOIL_MOISTURE_MAX) || 65,
        lightMin: parseFloat(process.env.LIGHT_MIN) || 600,
        lightMax: parseFloat(process.env.LIGHT_MAX) || 1000
      },
      'lettuce': {
        tempMin: parseFloat(process.env.TEMP_MIN) || 15,
        tempMax: parseFloat(process.env.TEMP_MAX) || 22,
        humidityMin: parseFloat(process.env.HUMIDITY_MIN) || 60,
        humidityMax: parseFloat(process.env.HUMIDITY_MAX) || 80,
        moistureMin: parseFloat(process.env.SOIL_MOISTURE_MIN) || 45,
        moistureMax: parseFloat(process.env.SOIL_MOISTURE_MAX) || 75,
        lightMin: parseFloat(process.env.LIGHT_MIN) || 300,
        lightMax: parseFloat(process.env.LIGHT_MAX) || 600
      },
      'monstera': {
        tempMin: 18,
        tempMax: 26,
        humidityMin: 40,
        humidityMax: 60,
        moistureMin: 40,
        moistureMax: 60,
        lightMin: 500,
        lightMax: 700
      },
      'sansevieria': {
        tempMin: 16,
        tempMax: 24,
        humidityMin: 30,
        humidityMax: 50,
        moistureMin: 20,
        moistureMax: 40,
        lightMin: 200,
        lightMax: 400
      }
    };
    
    console.log(`🌱 Initializing sensor for ${this.plantId} (${this.plantType}) at ${this.location}`);
    console.log(`📡 Kafka brokers: ${this.brokers.join(', ')}`);
    console.log(`⏱️  Sensor interval: ${this.interval / 1000} seconds`);
    
    // Log plant profile ranges
    const profile = this.plantProfiles[this.plantType];
    if (profile) {
      console.log(`🌡️  Temp range: ${profile.tempMin}°C - ${profile.tempMax}°C`);
      console.log(`💧 Moisture range: ${profile.moistureMin}% - ${profile.moistureMax}%`);
      console.log(`💡 Light range: ${profile.lightMin} - ${profile.lightMax} lux`);
      console.log(`💨 Humidity range: ${profile.humidityMin}% - ${profile.humidityMax}%`);
    }
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
      this.plantId = process.env.SENSOR_ID || process.env.PLANT_ID || 'plant-default';
      this.plantType = process.env.SENSOR_TYPE || process.env.PLANT_TYPE || 'tomato';
      this.location = process.env.SENSOR_LOCATION || process.env.LOCATION || 'Unknown';
      this.sensorInterval = parseInt(process.env.SCAN_INTERVAL || process.env.SENSOR_INTERVAL) || 10;
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
    const profile = this.plantProfiles[this.plantType] || this.plantProfiles['tomato'];
    const now = new Date();
    const hourOfDay = now.getHours();
    const minuteOfHour = now.getMinutes();
    
    // Calculate midpoints and ranges
    const tempMid = (profile.tempMin + profile.tempMax) / 2;
    const tempRange = (profile.tempMax - profile.tempMin) / 2;
    const humidityMid = (profile.humidityMin + profile.humidityMax) / 2;
    const humidityRange = (profile.humidityMax - profile.humidityMin) / 2;
    const moistureMid = (profile.moistureMin + profile.moistureMax) / 2;
    const moistureRange = (profile.moistureMax - profile.moistureMin) / 2;
    const lightMid = (profile.lightMin + profile.lightMax) / 2;
    const lightRange = (profile.lightMax - profile.lightMin) / 2;
    
    // Simulate daily cycles (more pronounced variations)
    const timeOfDay = (hourOfDay + minuteOfHour / 60) / 24; // 0-1 through the day
    const dailyTempVariation = Math.sin(((hourOfDay - 6) / 12) * Math.PI) * tempRange * 0.8;
    const dailyHumidityVariation = Math.sin(((hourOfDay - 12) / 12) * Math.PI) * humidityRange * 0.6;
    
    // Light follows day/night cycle (6am-8pm bright, 8pm-6am dark)
    const dailyLightVariation = Math.max(0, Math.sin(((hourOfDay - 6) / 12) * Math.PI)) * lightRange * 1.8;
    
    // Moisture slowly decreases during day, increases during watering (simulated)
    const wateringCycle = (hourOfDay === 7 || hourOfDay === 19) ? moistureRange * 0.3 : 0;
    const dailyMoistureVariation = Math.sin((hourOfDay / 24) * 2 * Math.PI) * moistureRange * 0.4;
    
    // Add more random noise for frequent changes
    const tempNoise = (Math.random() - 0.5) * tempRange * 0.4;
    const humidityNoise = (Math.random() - 0.5) * humidityRange * 0.5;
    const moistureNoise = (Math.random() - 0.5) * moistureRange * 0.3;
    const lightNoise = Math.random() * lightRange * 0.3;

    return {
      timestamp: now.toISOString(),
      plantId: this.plantId,
      location: this.location,
      plantType: this.plantType,
      sensors: {
        soilMoisture: Math.max(profile.moistureMin, Math.min(profile.moistureMax, 
          moistureMid + dailyMoistureVariation + wateringCycle + moistureNoise)),
        lightLevel: Math.max(profile.lightMin * 0.1, Math.min(profile.lightMax * 1.2, 
          lightMid + dailyLightVariation + lightNoise)),
        temperature: Math.max(profile.tempMin - 2, Math.min(profile.tempMax + 2, 
          tempMid + dailyTempVariation + tempNoise)),
        humidity: Math.max(profile.humidityMin - 5, Math.min(profile.humidityMax + 5, 
          humidityMid + dailyHumidityVariation + humidityNoise))
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
  console.log(`Shutting down sensor ${process.env.SENSOR_ID || process.env.PLANT_ID}...`);
  await sensor.producer.disconnect();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log(`Shutting down sensor ${process.env.SENSOR_ID || process.env.PLANT_ID}...`);
  await sensor.producer.disconnect();
  process.exit(0);
});