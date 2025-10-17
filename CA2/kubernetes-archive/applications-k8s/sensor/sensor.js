const kafka = require('kafkajs');

class PlantSensorSimulator {
  constructor() {
    this.plantId = process.env.PLANT_ID;
    this.plantType = process.env.PLANT_TYPE;
    this.location = process.env.LOCATION;
    this.interval = parseInt(process.env.SENSOR_INTERVAL) * 1000;

    this.kafka = kafka({
      clientId: `plant-sensor-${this.plantId}`,
      brokers: [process.env.KAFKA_BROKERS]
    });
    this.producer = this.kafka.producer();

    // Plant-specific characteristics matching CA0 proven architecture
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
    console.log(`⏱️ Sensor interval: ${process.env.SENSOR_INTERVAL} seconds`);
  }

  async start() {
    try {
      await this.producer.connect();
      console.log(`🚀 Starting sensor simulation for ${this.plantId}`);
      
      // Send initial data immediately
      await this.generateAndSendSensorData();
      
      // Then continue with interval
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
    
    // Simulate daily cycles matching CA0 proven patterns
    const dailyMoistureVariation = Math.sin((hourOfDay / 24) * 2 * Math.PI) * 5;
    const dailyLightVariation = Math.max(0, Math.sin(((hourOfDay - 6) / 12) * Math.PI) * profile.lightBase);
    const dailyTempVariation = Math.sin(((hourOfDay - 6) / 12) * Math.PI) * 3;
    
    // Add realistic random noise
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
        temperature: Number((profile.tempBase + dailyTempVariation + tempNoise).toFixed(1)),
        humidity: Math.max(0, Math.min(100, 
          profile.humidityBase + humidityNoise))
      }
    };
  }

  async generateAndSendSensorData() {
    const sensorData = this.generateRealisticSensorData();
    
    try {
      await this.producer.send({
        topic: process.env.KAFKA_TOPIC || 'plant-sensors',
        messages: [{
          key: this.plantId,
          value: JSON.stringify(sensorData)
        }]
      });
      
      console.log(`📊 Sent sensor data for ${this.plantId}:`, {
        moisture: `${sensorData.sensors.soilMoisture.toFixed(1)}%`,
        light: `${sensorData.sensors.lightLevel.toFixed(0)} lux`,
        temp: `${sensorData.sensors.temperature}°C`, 
        humidity: `${sensorData.sensors.humidity.toFixed(1)}%`
      });
    } catch (error) {
      console.error('❌ Error sending sensor data:', error);
    }
  }

  async healthCheck() {
    try {
      // Simple health check endpoint 
      const status = {
        status: 'healthy',
        plantId: this.plantId,
        plantType: this.plantType,
        location: this.location,
        uptime: process.uptime(),
        memoryUsage: process.memoryUsage(),
        kafkaConnected: this.producer ? true : false
      };
      return status;
    } catch (error) {
      return {
        status: 'unhealthy',
        error: error.message
      };
    }
  }
}

// Health check endpoint for Kubernetes probes
const http = require('http');
const sensor = new PlantSensorSimulator();

// Simple HTTP server for health checks
const server = http.createServer(async (req, res) => {
  if (req.url === '/health' || req.url === '/') {
    const health = await sensor.healthCheck();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(health, null, 2));
  } else {
    res.writeHead(404);
    res.end('Not Found');
  }
});

server.listen(8080, () => {
  console.log('📋 Health check server running on port 8080');
});

// Start the sensor
sensor.start().catch(console.error);

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log(`🛑 Shutting down sensor ${process.env.PLANT_ID}...`);
  try {
    await sensor.producer.disconnect();
    server.close();
    console.log('✅ Sensor shutdown complete');
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
  }
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log(`🛑 Received SIGTERM, shutting down sensor ${process.env.PLANT_ID}...`);
  try {
    await sensor.producer.disconnect();
    server.close();
    console.log('✅ Sensor shutdown complete');
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
  }
  process.exit(0);
});