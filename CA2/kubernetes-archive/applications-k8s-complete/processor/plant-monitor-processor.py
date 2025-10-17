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

import json
import time
import logging
from datetime import datetime
from kafka import KafkaConsumer, KafkaProducer
from pymongo import MongoClient
import paho.mqtt.client as mqtt
import os
import threading
from flask import Flask, jsonify
import signal
import sys

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Flask app for health checks
app = Flask(__name__)

class PlantDataProcessor:
    def __init__(self):
        # Configuration from environment variables
        self.kafka_brokers = os.getenv('KAFKA_BROKERS', 'kafka-service:9092').split(',')
        self.mongo_url = os.getenv('MONGODB_URL', 'mongodb://plantuser:PlantUserPass123!@mongodb-service:27017/plant_monitoring')
        self.consumer_group = os.getenv('KAFKA_CONSUMER_GROUP', 'plant-processor-group')
        self.mqtt_broker = os.getenv('MQTT_BROKER', 'homeassistant-service:1883').split(':')
        self.mqtt_host = self.mqtt_broker[0]
        self.mqtt_port = int(self.mqtt_broker[1]) if len(self.mqtt_broker) > 1 else 1883
        
        # Plant care profiles for health analysis
        self.plant_profiles = {
            'monstera': {
                'moisture_min': 40,
                'moisture_max': 60,
                'light_min': 800,
                'temp_min': 18,
                'temp_max': 26
            },
            'sansevieria': {
                'moisture_min': 20,
                'moisture_max': 40,
                'light_min': 200,
                'temp_min': 15,
                'temp_max': 25
            }
        }
        
        # Initialize Kafka consumer
        self.consumer = KafkaConsumer(
            os.getenv('KAFKA_SENSOR_TOPIC', 'plant-sensors'),
            'sensor-data',  # Backward compatibility
            bootstrap_servers=self.kafka_brokers,
            group_id=self.consumer_group,
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            auto_offset_reset='latest',
            enable_auto_commit=True
        )
        
        # Initialize Kafka producer for alerts
        self.producer = KafkaProducer(
            bootstrap_servers=self.kafka_brokers,
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )
        
        # Initialize MongoDB client
        self.mongo_client = MongoClient(self.mongo_url)
        self.db = self.mongo_client.plant_monitoring
        
        # Initialize MQTT client for Home Assistant
        self.mqtt_client = mqtt.Client(client_id="plant-processor")
        self.mqtt_client.on_connect = self.on_mqtt_connect
        self.mqtt_client.on_disconnect = self.on_mqtt_disconnect
        self.mqtt_client.on_publish = self.on_mqtt_publish
        
        # Connect to MQTT broker
        try:
            self.mqtt_client.connect(self.mqtt_host, self.mqtt_port, 60)
            self.mqtt_client.loop_start()
        except Exception as e:
            logger.error(f"Failed to connect to MQTT broker: {e}")
        
        # Initialize database
        self.initialize_database()
        
        logger.info(f"🌱 Plant Processor initialized")
        logger.info(f"📡 Kafka brokers: {self.kafka_brokers}")
        logger.info(f"🗄️ MongoDB URL: {self.mongo_url}")
        logger.info(f"📨 MQTT Broker: {self.mqtt_host}:{self.mqtt_port}")

    def initialize_database(self):
        """Initialize MongoDB with plant configurations"""
        try:
            plants = [
                {
                    'plant_id': 'plant-001',
                    'name': 'Monstera Deliciosa',
                    'type': 'monstera',
                    'location': 'Living Room',
                    'care_instructions': self.plant_profiles['monstera'],
                    'added_at': datetime.utcnow()
                },
                {
                    'plant_id': 'plant-002',
                    'name': 'Snake Plant', 
                    'type': 'sansevieria',
                    'location': 'Bedroom',
                    'care_instructions': self.plant_profiles['sansevieria'],
                    'added_at': datetime.utcnow()
                }
            ]
            
            for plant in plants:
                self.db.plants.replace_one(
                    {'plant_id': plant['plant_id']},
                    plant,
                    upsert=True
                )
            
            logger.info("✅ Database initialized with plant configurations")
        except Exception as e:
            logger.error(f"❌ Error initializing database: {e}")

    def on_mqtt_connect(self, client, userdata, flags, rc):
        if rc == 0:
            logger.info("✅ Connected to MQTT broker for Home Assistant integration")
            self.publish_discovery_messages()
        else:
            logger.error(f"❌ Failed to connect to MQTT broker: {rc}")

    def on_mqtt_disconnect(self, client, userdata, rc):
        logger.info("📡 Disconnected from MQTT broker")

    def on_mqtt_publish(self, client, userdata, mid):
        logger.debug(f"📤 MQTT message published: {mid}")

    def publish_discovery_messages(self):
        """Publish MQTT discovery messages for Home Assistant"""
        logger.info("🔍 Publishing MQTT discovery messages...")
        
        plants = ['plant-001', 'plant-002']
        sensors = [
            {'name': 'Moisture', 'key': 'moisture', 'unit': '%', 'device_class': 'humidity', 'icon': 'mdi:water-percent'},
            {'name': 'Health Score', 'key': 'health', 'unit': 'pts', 'device_class': None, 'icon': 'mdi:leaf'},
            {'name': 'Light Level', 'key': 'light', 'unit': 'lux', 'device_class': 'illuminance', 'icon': 'mdi:lightbulb'},
            {'name': 'Temperature', 'key': 'temperature', 'unit': '°C', 'device_class': 'temperature', 'icon': 'mdi:thermometer'},
            {'name': 'Humidity', 'key': 'humidity', 'unit': '%', 'device_class': 'humidity', 'icon': 'mdi:water-percent'},
            {'name': 'Status', 'key': 'status', 'unit': None, 'device_class': None, 'icon': 'mdi:sprout'},
            {'name': 'Battery', 'key': 'battery', 'unit': '%', 'device_class': 'battery', 'icon': 'mdi:battery'}
        ]

        for plant in plants:
            for sensor in sensors:
                self.publish_discovery(plant, sensor)
        
        logger.info("✅ MQTT discovery messages published")

    def publish_discovery(self, plant_id, sensor):
        """Publish individual sensor discovery message"""
        entity_id = f"{plant_id.replace('-', '_')}_{sensor['key']}"
        discovery_topic = f"homeassistant/sensor/{entity_id}/config"
        
        config = {
            'name': f"{plant_id.replace('plant-', 'Plant ')} {sensor['name']}",
            'state_topic': f"homeassistant/sensor/{plant_id.replace('-', '_')}/state",
            'value_template': f"{{{{ value_json.{sensor['key']} }}}}",
            'unique_id': entity_id,
            'device': {
                'identifiers': [plant_id.replace('-', '_')],
                'name': plant_id.replace('plant-', 'Plant '),
                'manufacturer': 'CS5287 IoT Systems',
                'model': 'Smart Plant Monitor v2.0',
                'sw_version': '1.0.0'
            }
        }

        if sensor['unit']:
            config['unit_of_measurement'] = sensor['unit']
        if sensor['device_class']:
            config['device_class'] = sensor['device_class']
        if sensor['icon']:
            config['icon'] = sensor['icon']

        self.mqtt_client.publish(discovery_topic, json.dumps(config), retain=True)

    def process_sensor_data(self, data):
        """Process individual sensor data record"""
        try:
            logger.info(f"📊 Processing data for {data.get('plantId')}: {data.get('sensors', {})}")
            
            # Add processing metadata
            processed_data = {
                **data,
                'processed_at': datetime.utcnow(),
                'processor_version': '2.0.0'
            }
            
            # Store raw sensor data
            result = self.db.sensor_readings.insert_one(processed_data)
            logger.info(f"💾 Stored sensor data: {result.inserted_id}")
            
            # Get plant configuration
            plant = self.db.plants.find_one({'plant_id': data.get('plantId')})
            
            if plant:
                # Analyze plant health
                health_analysis = self.analyze_health(data, plant['care_instructions'])
                
                # Store health analysis
                self.db.health_analysis.insert_one({
                    'plant_id': data.get('plantId'),
                    'timestamp': datetime.utcnow(),
                    **health_analysis
                })
                
                logger.info(f"🌡️ Health analysis for {data.get('plantId')}: Score={health_analysis['health_score']}, Status={health_analysis['status']}")
                
                # Send alerts if necessary
                if health_analysis['issues']:
                    self.send_alerts(data.get('plantId'), health_analysis)
                
                # Update Home Assistant
                self.update_home_assistant(data.get('plantId'), {
                    'moisture': data.get('sensors', {}).get('soilMoisture', 0),
                    'health': health_analysis['health_score'],
                    'light': data.get('sensors', {}).get('lightLevel', 0),
                    'temperature': data.get('sensors', {}).get('temperature', 0),
                    'humidity': data.get('sensors', {}).get('humidity', 0),
                    'status': health_analysis['status'],
                    'battery': data.get('metadata', {}).get('batteryLevel', 100)
                })
            else:
                logger.warning(f"⚠️ No plant configuration found for {data.get('plantId')}")
                
        except Exception as e:
            logger.error(f"❌ Error processing sensor data: {e}")

    def analyze_health(self, data, care_instructions):
        """Analyze plant health based on sensor data and care instructions"""
        sensors = data.get('sensors', {})
        health_score = 100
        issues = []
        
        # Moisture analysis
        moisture = sensors.get('soilMoisture', 50)
        if moisture < care_instructions['moisture_min']:
            issues.append({
                'type': 'WATER_NEEDED',
                'severity': 'HIGH',
                'message': f'Soil moisture too low: {moisture}% (needs {care_instructions["moisture_min"]}%+)'
            })
            health_score -= 30
        elif moisture > care_instructions['moisture_max']:
            issues.append({
                'type': 'OVERWATERED',
                'severity': 'MEDIUM',
                'message': f'Soil moisture too high: {moisture}% (max {care_instructions["moisture_max"]}%)'
            })
            health_score -= 20
        
        # Light analysis
        light = sensors.get('lightLevel', 0)
        if light < care_instructions['light_min']:
            issues.append({
                'type': 'INSUFFICIENT_LIGHT',
                'severity': 'MEDIUM',
                'message': f'Light level too low: {light} lux (needs {care_instructions["light_min"]}+ lux)'
            })
            health_score -= 15
            
        # Temperature analysis
        temp = sensors.get('temperature', 20)
        if temp < care_instructions['temp_min'] or temp > care_instructions['temp_max']:
            issues.append({
                'type': 'TEMPERATURE_STRESS',
                'severity': 'LOW',
                'message': f'Temperature {temp}°C outside optimal range ({care_instructions["temp_min"]}-{care_instructions["temp_max"]}°C)'
            })
            health_score -= 10
        
        # Battery warning
        battery = data.get('metadata', {}).get('batteryLevel', 100)
        if battery < 20:
            issues.append({
                'type': 'LOW_BATTERY',
                'severity': 'LOW',
                'message': f'Sensor battery low: {battery}%'
            })
            health_score -= 5
        
        status = 'healthy' if health_score > 80 else 'needs_attention' if health_score > 60 else 'critical'
        
        return {
            'health_score': max(0, health_score),
            'status': status,
            'issues': issues,
            'analyzed_at': datetime.utcnow()
        }

    def send_alerts(self, plant_id, health_analysis):
        """Send alerts for plant health issues"""
        try:
            for issue in health_analysis['issues']:
                # Store alert in MongoDB
                self.db.alerts.insert_one({
                    'plant_id': plant_id,
                    'timestamp': datetime.utcnow(),
                    **issue
                })
                
                # Send to Kafka alerts topic
                alert = {
                    'plant_id': plant_id,
                    'timestamp': datetime.utcnow().isoformat(),
                    **issue
                }
                
                self.producer.send(os.getenv('KAFKA_ALERT_TOPIC', 'plant-alerts'), alert)
                logger.info(f"🚨 Alert sent for {plant_id}: {issue['message']}")
        except Exception as e:
            logger.error(f"❌ Error sending alerts: {e}")

    def update_home_assistant(self, plant_id, data):
        """Update Home Assistant via MQTT"""
        try:
            topic = f"homeassistant/sensor/{plant_id.replace('-', '_')}/state"
            payload = {
                **data,
                'last_updated': datetime.utcnow().isoformat()
            }
            
            self.mqtt_client.publish(topic, json.dumps(payload))
            logger.info(f"📡 Updated Home Assistant for {plant_id}")
        except Exception as e:
            logger.error(f"❌ Error updating Home Assistant: {e}")

    def run(self):
        """Main processing loop"""
        logger.info("🚀 Starting plant data processor...")
        
        try:
            for message in self.consumer:
                self.process_sensor_data(message.value)
                
        except KeyboardInterrupt:
            logger.info("🛑 Received interrupt signal")
        except Exception as e:
            logger.error(f"❌ Error in main loop: {e}")
        finally:
            self.cleanup()

    def cleanup(self):
        """Clean up resources"""
        logger.info("🧹 Cleaning up resources...")
        try:
            self.consumer.close()
            self.producer.close()
            self.mqtt_client.loop_stop()
            self.mqtt_client.disconnect()
            self.mongo_client.close()
            logger.info("✅ Plant data processor stopped")
        except Exception as e:
            logger.error(f"❌ Error during cleanup: {e}")

# Flask health check endpoints
@app.route('/health')
@app.route('/')
def health_check():
    return jsonify({
        'status': 'healthy',
        'service': 'plant-data-processor',
        'version': '2.0.0',
        'timestamp': datetime.utcnow().isoformat()
    })

@app.route('/metrics')
def metrics():
    return jsonify({
        'uptime': time.time(),
        'service': 'plant-data-processor',
        'version': '2.0.0'
    })

def signal_handler(signum, frame):
    logger.info("🛑 Received shutdown signal")
    processor.cleanup()
    sys.exit(0)

if __name__ == "__main__":
    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    processor = PlantDataProcessor()
    
    # Start Flask health check server in background thread
    def start_health_server():
        app.run(host='0.0.0.0', port=8080, debug=False)
    
    health_thread = threading.Thread(target=start_health_server)
    health_thread.daemon = True
    health_thread.start()
    
    logger.info("📋 Health check server started on port 8080")
    
    # Start main processing loop
    processor.run()