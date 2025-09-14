const kafka = require('kafkajs');
const { MongoClient } = require('mongodb');
const mqtt = require('mqtt');

class PlantCareProcessor {
  constructor() {
    // Kafka configuration
    this.kafka = kafka({
      clientId: 'plant-care-processor',
      brokers: ['10.0.143.200:9092']
    });
    this.consumer = this.kafka.consumer({ groupId: 'plant-processor-group' });
    this.producer = this.kafka.producer();

    // MongoDB configuration
    this.mongoUrl = 'mongodb://plantuser:PlantUserPass123!@10.0.135.192:27017/plant_monitoring';
    this.mongoClient = new MongoClient(this.mongoUrl);

    // MQTT configuration
    this.mqttClient = mqtt.connect('mqtt://10.0.15.111:1883');

    this.plantProfiles = {
      'monstera': { moistureMin: 40, moistureMax: 60, lightMin: 800 },
      'sansevieria': { moistureMin: 20, moistureMax: 40, lightMin: 200 }
    };
  }

  async start() {
    try {
      await this.consumer.connect();
      await this.producer.connect();
      await this.mongoClient.connect();
      
      console.log('Starting Plant Care Processor...');
      console.log('Connected to Kafka and MongoDB');
      
      // Publish MQTT discovery messages for automatic sensor setup
      await this.publishDiscoveryMessages();
      
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

  async processPlantData(sensorData) {
    console.log(`Processing data for ${sensorData.plantId}:`, {
      plantId: sensorData.plantId,
      timestamp: sensorData.timestamp,
      location: sensorData.location,
      plantType: sensorData.plantType,
      sensors: sensorData.sensors
    });
    
    // Store raw sensor data
    await this.mongoClient.db('plant_monitoring')
      .collection('sensor_readings')
      .insertOne({
        ...sensorData,
        processedAt: new Date()
      });

    // Analyze plant health
    const plant = await this.mongoClient.db('plant_monitoring')
      .collection('plants')
      .findOne({ plantId: sensorData.plantId });

    if (plant) {
      const healthAnalysis = this.analyzePlantHealth(sensorData, plant.careInstructions);
      
      console.log(`Health analysis for ${sensorData.plantId}:`, healthAnalysis);
      
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
