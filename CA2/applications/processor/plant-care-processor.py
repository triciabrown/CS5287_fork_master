#!/usr/bin/env python3
"""
Plant Care Processor - Kubernetes Version
Based on proven CA0 architecture: Kafka → MongoDB + MQTT (Home Assistant)
Consolidates the working Node.js pattern into Python for Kubernetes deployment
"""

import os
import json
import time
import logging
from datetime import datetime
from kafka import KafkaConsumer, KafkaProducer
from kafka.errors import KafkaError
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure
import paho.mqtt.client as mqtt

# Configure logging  
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PlantCareProcessor:
    """
    Plant Care Processor matching CA0 proven architecture
    Processes sensor data and integrates with Home Assistant via MQTT
    """
    
    def __init__(self):
        # Kafka configuration
        self.kafka_brokers = os.getenv('KAFKA_BROKERS', 'kafka-service:9092')
        self.consumer_topic = os.getenv('KAFKA_TOPIC', 'plant-sensors')
        self.alert_topic = os.getenv('ALERT_TOPIC', 'plant-alerts')
        self.consumer_group = os.getenv('CONSUMER_GROUP', 'plant-processor-group')
        
        # MongoDB configuration (matching CA0 structure)
        self.mongo_uri = os.getenv('MONGODB_URI', 'mongodb://plantuser:PlantUserPass123!@mongodb-service:27017/plant_monitoring')
        
        # MQTT configuration for Home Assistant
        self.mqtt_broker = os.getenv('MQTT_BROKER', 'homeassistant-service')
        self.mqtt_port = int(os.getenv('MQTT_PORT', '1883'))
        
        self.processor_id = os.getenv('HOSTNAME', 'k8s-processor')
        
        # Plant care profiles (matching CA0 logic)
        self.plant_profiles = {
            'monstera': {'moistureMin': 40, 'moistureMax': 60, 'lightMin': 800},
            'sansevieria': {'moistureMin': 20, 'moistureMax': 40, 'lightMin': 200}
        }
        
        # Initialize connections
        self.consumer = None
        self.producer = None
        self.mongo_client = None
        self.collection = None
        self.mqtt_client = None
        
        logger.info(f"Plant Care Processor {self.processor_id} initializing...")

    def connect_kafka(self):
        """Connect to Kafka consumer and producer"""
        try:
            # Consumer for plant sensor data
            self.consumer = KafkaConsumer(
                self.consumer_topic,
                bootstrap_servers=self.kafka_brokers.split(','),
                group_id=self.consumer_group,
                value_deserializer=lambda m: json.loads(m.decode('utf-8')),
                key_deserializer=lambda k: k.decode('utf-8') if k else None,
                auto_offset_reset='earliest',
                enable_auto_commit=True
            )
            
            # Producer for alerts
            self.producer = KafkaProducer(
                bootstrap_servers=self.kafka_brokers.split(','),
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                key_serializer=lambda k: k.encode('utf-8') if k else None,
                acks='all'
            )
            
            logger.info(f"Connected to Kafka - Consumer: {self.consumer_topic}, Producer: {self.alert_topic}")
        except Exception as e:
            logger.error(f"Failed to connect to Kafka: {e}")
            raise

    def connect_mongodb(self):
        """Connect to MongoDB (matching CA0 structure)"""
        try:
            self.mongo_client = MongoClient(self.mongo_uri)
            # Test connection
            self.mongo_client.admin.command('ping')
            
            db = self.mongo_client.plant_monitoring
            self.collection = db.sensor_readings
            self.alerts_collection = db.alerts
            self.plants_collection = db.plants
            
            # Create indexes matching CA0
            self.collection.create_index([("plantId", 1), ("timestamp", -1)])
            self.alerts_collection.create_index([("plantId", 1), ("timestamp", -1)])
            
            logger.info("Connected to MongoDB with CA0-compatible schema")
        except ConnectionFailure as e:
            logger.error(f"Failed to connect to MongoDB: {e}")
            raise

    def connect_mqtt(self):
        """Connect to MQTT for Home Assistant integration"""
        try:
            self.mqtt_client = mqtt.Client()
            self.mqtt_client.on_connect = self.on_mqtt_connect
            self.mqtt_client.on_disconnect = self.on_mqtt_disconnect
            
            self.mqtt_client.connect(self.mqtt_broker, self.mqtt_port, 60)
            self.mqtt_client.loop_start()
            
            logger.info(f"Connected to MQTT broker: {self.mqtt_broker}:{self.mqtt_port}")
        except Exception as e:
            logger.error(f"Failed to connect to MQTT: {e}")
            raise

    def on_mqtt_connect(self, client, userdata, flags, rc):
        if rc == 0:
            logger.info("MQTT connected successfully")
            # Publish discovery messages on connect
            self.publish_discovery_messages()
        else:
            logger.error(f"MQTT connection failed with code {rc}")

    def on_mqtt_disconnect(self, client, userdata, rc):
        logger.warning("MQTT disconnected")

    def publish_discovery_messages(self):
        """Publish MQTT discovery messages for Home Assistant (matching CA0 logic)"""
        logger.info("Publishing MQTT discovery messages...") 
        plants = ['001', '002']
        sensors = [
            {'name': 'Moisture', 'key': 'moisture', 'unit': '%', 'device_class': 'humidity', 'icon': 'mdi:water-percent'},
            {'name': 'Health', 'key': 'health', 'unit': 'pts', 'device_class': None, 'icon': 'mdi:leaf'},
            {'name': 'Light', 'key': 'light', 'unit': 'lux', 'device_class': 'illuminance', 'icon': 'mdi:lightbulb'},
            {'name': 'Temperature', 'key': 'temperature', 'unit': '°C', 'device_class': 'temperature', 'icon': 'mdi:thermometer'},
            {'name': 'Status', 'key': 'status', 'unit': None, 'device_class': None, 'icon': 'mdi:sprout'}
        ]

        for plant in plants:
            for sensor in sensors:
                self.publish_discovery(plant, sensor)
                logger.info(f"Published discovery for Plant {plant} {sensor['name']}")
        
        logger.info("MQTT discovery messages published successfully")

    def publish_discovery(self, plant_id, sensor):
        """Publish individual MQTT discovery message"""
        discovery_topic = f"homeassistant/sensor/plant_{plant_id}_{sensor['key']}/config"
        config = {
            'name': f"Plant {plant_id} {sensor['name']}",
            'state_topic': f"homeassistant/sensor/plant_plant_{plant_id}/state",
            'value_template': f"{{{{ value_json.{sensor['key']} }}}}",
            'unique_id': f"plant_{plant_id}_{sensor['key']}",
            'device': {
                'identifiers': [f"plant_{plant_id}"],
                'name': f"Plant {plant_id}",
                'manufacturer': 'CS5287 IoT',
                'model': 'Smart Plant Monitor'
            }
        }

        if sensor['unit']:
            config['unit_of_measurement'] = sensor['unit']
        if sensor['device_class']:
            config['device_class'] = sensor['device_class']
        if sensor['icon']:
            config['icon'] = sensor['icon']

        self.mqtt_client.publish(discovery_topic, json.dumps(config), retain=True)

    def analyze_plant_health(self, sensor_data, care_instructions):
        """Analyze plant health (matching CA0 logic)"""
        alerts = []
        health_score = 100

        # Check moisture levels
        if sensor_data['sensors']['soilMoisture'] < care_instructions['moistureMin']:
            alerts.append({
                'type': 'WATER_NEEDED',
                'severity': 'HIGH', 
                'message': 'Soil moisture too low'
            })
            health_score -= 30

        if sensor_data['sensors']['soilMoisture'] > care_instructions['moistureMax']:
            alerts.append({
                'type': 'OVERWATERED',
                'severity': 'MEDIUM',
                'message': 'Soil moisture too high'
            })
            health_score -= 20

        # Check light levels
        if sensor_data['sensors']['lightLevel'] < 200:
            alerts.append({
                'type': 'INSUFFICIENT_LIGHT',
                'severity': 'MEDIUM',
                'message': 'Light level too low'
            })
            health_score -= 15

        status = 'healthy' if health_score > 80 else 'needs_attention' if health_score > 60 else 'critical'

        return {'healthScore': health_score, 'status': status, 'alerts': alerts}

    def send_alerts(self, plant_id, alerts):
        """Send alerts to Kafka and MongoDB (matching CA0 pattern)"""
        for alert in alerts:
            alert_doc = {
                'plantId': plant_id,
                'timestamp': datetime.now(),
                **alert
            }
            
            # Store in MongoDB
            self.alerts_collection.insert_one(alert_doc)
            
            # Send to Kafka
            try:
                self.producer.send(
                    self.alert_topic,
                    value=alert_doc,
                    key=plant_id
                )
                logger.info(f"Alert sent for {plant_id}: {alert['type']}")
            except KafkaError as e:
                logger.error(f"Failed to send alert to Kafka: {e}")

    def update_home_assistant(self, plant_id, data):
        """Update Home Assistant via MQTT (matching CA0 pattern)"""
        topic = f"homeassistant/sensor/plant_{plant_id.replace('-', '_')}/state"
        self.mqtt_client.publish(topic, json.dumps(data))

    def process_sensor_data(self, sensor_data):
        """Process sensor data (matching CA0 workflow)"""
        plant_id = sensor_data['plantId']
        logger.info(f"Processing data for {plant_id}")
        
        # Store raw sensor data
        document = {
            **sensor_data,
            'processedAt': datetime.now(),
            'processedBy': self.processor_id
        }
        self.collection.insert_one(document)
        
        # Get plant profile
        plant = self.plants_collection.find_one({'plantId': plant_id})
        if plant:
            care_instructions = plant['careInstructions']
            health_analysis = self.analyze_plant_health(sensor_data, care_instructions)
            
            logger.info(f"Health analysis for {plant_id}: Score={health_analysis['healthScore']}, Status={health_analysis['status']}")
            
            # Send alerts if needed
            if health_analysis['alerts']:
                self.send_alerts(plant_id, health_analysis['alerts'])
            
            # Update Home Assistant
            ha_data = {
                'moisture': sensor_data['sensors']['soilMoisture'],
                'health': health_analysis['healthScore'],
                'light': sensor_data['sensors']['lightLevel'],
                'temperature': sensor_data['sensors']['temperature'],
                'status': health_analysis['status']
            }
            self.update_home_assistant(plant_id, ha_data)

    def run(self):
        """Main processing loop"""
        try:
            # Connect to all services
            self.connect_kafka()
            self.connect_mongodb()
            self.connect_mqtt()
            
            logger.info("Plant Care Processor started - monitoring sensor data...")
            
            # Process messages
            for message in self.consumer:
                try:
                    sensor_data = message.value
                    self.process_sensor_data(sensor_data)
                except Exception as e:
                    logger.error(f"Error processing message: {e}")
                    
        except KeyboardInterrupt:
            logger.info("Shutting down processor...")
        except Exception as e:
            logger.error(f"Processor error: {e}")
        finally:
            # Cleanup connections
            if self.consumer:
                self.consumer.close()
            if self.producer:
                self.producer.close()
            if self.mongo_client:
                self.mongo_client.close()
            if self.mqtt_client:
                self.mqtt_client.loop_stop()
                self.mqtt_client.disconnect()
            logger.info("Plant Care Processor stopped")

if __name__ == '__main__':
    processor = PlantCareProcessor()
    processor.run()