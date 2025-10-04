#!/usr/bin/env python3
"""
Plant Monitoring Data Producer
Generates realistic sensor data for plant monitoring system
"""

import os
import time
import json
import random
import logging
from datetime import datetime
from kafka import KafkaProducer
from kafka.errors import KafkaError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PlantSensorProducer:
    def __init__(self):
        self.kafka_brokers = os.getenv('KAFKA_BROKERS', 'kafka-service:9092')
        self.topic = os.getenv('KAFKA_TOPIC', 'sensor-data')
        self.producer_id = os.getenv('HOSTNAME', f'producer-{random.randint(1000, 9999)}')
        self.plant_count = int(os.getenv('PLANT_COUNT', '10'))
        self.interval = int(os.getenv('PRODUCE_INTERVAL', '30'))
        
        # Kafka producer configuration
        self.producer = None
        self.connect_kafka()
        
        logger.info(f"Producer {self.producer_id} initialized")
        logger.info(f"Kafka brokers: {self.kafka_brokers}")
        logger.info(f"Topic: {self.topic}")
        logger.info(f"Plants to monitor: {self.plant_count}")
        logger.info(f"Produce interval: {self.interval}s")

    def connect_kafka(self):
        """Connect to Kafka with retry logic"""
        max_retries = 10
        retry_count = 0
        
        while retry_count < max_retries:
            try:
                self.producer = KafkaProducer(
                    bootstrap_servers=self.kafka_brokers.split(','),
                    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                    key_serializer=lambda k: k.encode('utf-8') if k else None,
                    acks='all',
                    retries=3,
                    batch_size=16384,
                    linger_ms=10,
                    buffer_memory=33554432
                )
                logger.info("Successfully connected to Kafka")
                return
            except Exception as e:
                retry_count += 1
                logger.warning(f"Failed to connect to Kafka (attempt {retry_count}/{max_retries}): {e}")
                time.sleep(5)
        
        raise Exception("Failed to connect to Kafka after maximum retries")

    def generate_sensor_data(self, plant_id):
        """Generate realistic sensor data for a plant"""
        base_temp = 22.0  # Base temperature in Celsius
        base_humidity = 60.0  # Base humidity percentage
        base_soil_moisture = 50.0  # Base soil moisture percentage
        base_light = 500.0  # Base light level in lux
        
        # Add realistic variations
        temperature = base_temp + random.uniform(-5.0, 8.0)
        humidity = max(0, min(100, base_humidity + random.uniform(-20.0, 20.0)))
        soil_moisture = max(0, min(100, base_soil_moisture + random.uniform(-30.0, 30.0)))
        light_level = max(0, base_light + random.uniform(-200, 800))
        
        # Generate alerts for extreme conditions
        alerts = []
        if soil_moisture < 20:
            alerts.append("LOW_SOIL_MOISTURE")
        if temperature > 28:
            alerts.append("HIGH_TEMPERATURE")
        if humidity > 80:
            alerts.append("HIGH_HUMIDITY")
        if light_level < 100:
            alerts.append("LOW_LIGHT")
            
        return {
            'timestamp': datetime.now().isoformat(),
            'producer_id': self.producer_id,
            'plant_id': plant_id,
            'location': f'greenhouse-sector-{(hash(plant_id) % 5) + 1}',
            'sensors': {
                'temperature_celsius': round(temperature, 2),
                'humidity_percent': round(humidity, 2),
                'soil_moisture_percent': round(soil_moisture, 2),
                'light_level_lux': round(light_level, 2),
                'ph_level': round(random.uniform(6.0, 7.5), 2),
                'conductivity_ms': round(random.uniform(1.0, 3.0), 2)
            },
            'alerts': alerts,
            'battery_level': random.randint(15, 100),
            'signal_strength': random.randint(-80, -40)
        }

    def produce_data(self):
        """Main producer loop"""
        message_count = 0
        
        try:
            while True:
                for plant_id in [f'plant-{i:03d}' for i in range(1, self.plant_count + 1)]:
                    try:
                        # Generate sensor data
                        sensor_data = self.generate_sensor_data(plant_id)
                        
                        # Send to Kafka
                        future = self.producer.send(
                            self.topic,
                            value=sensor_data,
                            key=plant_id
                        )
                        
                        # Wait for confirmation (optional, for reliability)
                        record_metadata = future.get(timeout=10)
                        message_count += 1
                        
                        logger.info(
                            f"Sent message {message_count}: {plant_id} -> "
                            f"partition {record_metadata.partition}, "
                            f"offset {record_metadata.offset}"
                        )
                        
                    except KafkaError as e:
                        logger.error(f"Failed to send message for {plant_id}: {e}")
                    except Exception as e:
                        logger.error(f"Unexpected error for {plant_id}: {e}")
                
                # Wait before next round
                logger.info(f"Completed round {message_count // self.plant_count}. Waiting {self.interval}s...")
                time.sleep(self.interval)
                
        except KeyboardInterrupt:
            logger.info("Shutting down producer...")
        except Exception as e:
            logger.error(f"Producer error: {e}")
        finally:
            if self.producer:
                self.producer.close()
                logger.info("Producer closed")

if __name__ == '__main__':
    producer = PlantSensorProducer()
    producer.produce_data()