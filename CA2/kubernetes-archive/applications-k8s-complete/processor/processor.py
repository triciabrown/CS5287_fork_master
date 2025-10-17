#!/usr/bin/env python3
"""
Plant Monitoring Data Processor
Consumes sensor data from Kafka and stores in MongoDB
"""

import os
import json
import logging
from datetime import datetime
from kafka import KafkaConsumer
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PlantDataProcessor:
    def __init__(self):
        # Kafka configuration
        self.kafka_brokers = os.getenv('KAFKA_BROKERS', 'kafka-service:9092')
        self.topic = os.getenv('KAFKA_TOPIC', 'sensor-data')
        self.consumer_group = os.getenv('CONSUMER_GROUP', 'plant-processors')
        
        # MongoDB configuration
        self.mongo_uri = os.getenv('MONGODB_URI', 'mongodb://admin:plantmon2024@mongodb-service:27017/')
        self.database_name = os.getenv('MONGO_DATABASE', 'plant_monitoring')
        self.collection_name = os.getenv('MONGO_COLLECTION', 'sensor_readings')
        
        self.processor_id = os.getenv('HOSTNAME', 'processor-unknown')
        
        # Initialize connections
        self.consumer = None
        self.mongo_client = None
        self.collection = None
        
        self.connect_kafka()
        self.connect_mongodb()
        
        logger.info(f"Processor {self.processor_id} initialized")

    def connect_kafka(self):
        """Connect to Kafka consumer"""
        try:
            self.consumer = KafkaConsumer(
                self.topic,
                bootstrap_servers=self.kafka_brokers.split(','),
                group_id=self.consumer_group,
                value_deserializer=lambda m: json.loads(m.decode('utf-8')),
                key_deserializer=lambda k: k.decode('utf-8') if k else None,
                auto_offset_reset='earliest',
                enable_auto_commit=True,
                auto_commit_interval_ms=1000,
                consumer_timeout_ms=1000
            )
            logger.info(f"Connected to Kafka topic: {self.topic}")
        except Exception as e:
            logger.error(f"Failed to connect to Kafka: {e}")
            raise

    def connect_mongodb(self):
        """Connect to MongoDB"""
        try:
            self.mongo_client = MongoClient(self.mongo_uri)
            # Test connection
            self.mongo_client.admin.command('ping')
            
            db = self.mongo_client[self.database_name]
            self.collection = db[self.collection_name]
            
            # Create indexes for better performance
            self.collection.create_index([("plant_id", 1), ("timestamp", -1)])
            self.collection.create_index([("timestamp", -1)])
            
            logger.info(f"Connected to MongoDB: {self.database_name}.{self.collection_name}")
        except ConnectionFailure as e:
            logger.error(f"Failed to connect to MongoDB: {e}")
            raise

    def process_sensor_data(self, data):
        """Process and enrich sensor data"""
        try:
            # Add processing metadata
            processed_data = data.copy()
            processed_data['processed_by'] = self.processor_id
            processed_data['processed_at'] = datetime.now().isoformat()
            
            # Calculate derived metrics
            sensors = data.get('sensors', {})
            alerts = data.get('alerts', [])
            
            # Calculate comfort index (0-100, higher is better)
            temp = sensors.get('temperature_celsius', 22)
            humidity = sensors.get('humidity_percent', 60)
            soil_moisture = sensors.get('soil_moisture_percent', 50)
            
            temp_score = max(0, 100 - abs(temp - 22) * 5)  # Optimal at 22°C
            humidity_score = max(0, 100 - abs(humidity - 60) * 2)  # Optimal at 60%
            moisture_score = soil_moisture  # Higher is better
            
            comfort_index = (temp_score + humidity_score + moisture_score) / 3
            processed_data['comfort_index'] = round(comfort_index, 2)
            
            # Risk assessment
            risk_level = 'LOW'
            if len(alerts) > 2:
                risk_level = 'HIGH'
            elif len(alerts) > 0:
                risk_level = 'MEDIUM'
            
            processed_data['risk_level'] = risk_level
            
            # Store in MongoDB
            result = self.collection.insert_one(processed_data)
            
            logger.info(
                f"Processed {data.get('plant_id')} - "
                f"Comfort: {comfort_index:.1f}, Risk: {risk_level}, "
                f"Alerts: {len(alerts)}, MongoDB ID: {result.inserted_id}"
            )
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to process data: {e}")
            return False

    def get_processing_stats(self):
        """Get processing statistics"""
        try:
            # Count total documents
            total_count = self.collection.count_documents({})
            
            # Count recent documents (last hour)
            recent_count = self.collection.count_documents({
                'processed_at': {'$gte': datetime.now().replace(minute=0, second=0, microsecond=0).isoformat()}
            })
            
            # Get unique plants
            plants = self.collection.distinct('plant_id')
            
            return {
                'total_processed': total_count,
                'recent_processed': recent_count,
                'unique_plants': len(plants),
                'plant_list': sorted(plants)
            }
        except Exception as e:
            logger.error(f"Failed to get stats: {e}")
            return None

    def run(self):
        """Main processing loop"""
        logger.info("Starting data processor...")
        message_count = 0
        
        try:
            while True:
                # Poll for messages
                message_batch = self.consumer.poll(timeout_ms=1000)
                
                if message_batch:
                    for topic_partition, messages in message_batch.items():
                        for message in messages:
                            try:
                                # Process the message
                                success = self.process_sensor_data(message.value)
                                if success:
                                    message_count += 1
                                    
                                    # Log stats every 50 messages
                                    if message_count % 50 == 0:
                                        stats = self.get_processing_stats()
                                        if stats:
                                            logger.info(f"Processing stats: {stats}")
                                            
                            except Exception as e:
                                logger.error(f"Error processing message: {e}")
                else:
                    # No messages, log heartbeat every minute
                    if message_count % 60 == 0:
                        logger.info(f"Processor active - Total processed: {message_count}")
                
        except KeyboardInterrupt:
            logger.info("Shutting down processor...")
        except Exception as e:
            logger.error(f"Processor error: {e}")
        finally:
            if self.consumer:
                self.consumer.close()
            if self.mongo_client:
                self.mongo_client.close()
            logger.info("Processor stopped")

if __name__ == '__main__':
    processor = PlantDataProcessor()
    processor.run()