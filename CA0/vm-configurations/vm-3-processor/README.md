# VM-3: Plant Care Processor Setup Instructions

## Deployment Commands

```bash
# Connect to VM-3
ssh -i plant-monitoring-key.pem ubuntu@10.0.130.79

# Create application directory
sudo mkdir -p /opt/processor
cd /opt/processor

# Copy all files to this directory structure:
# /opt/processor/
# ├── docker-compose.yml
# └── plant-care-processor/
#     ├── Dockerfile
#     ├── package.json
#     └── app.js

# Start the processor
sudo docker compose up -d --build

# Verify processor is running
sudo docker compose ps
sudo docker compose logs -f plant-processor
```

## Key Features

### Automatic MQTT Discovery
- Publishes discovery messages for all sensors on startup
- Creates 10 sensors automatically in Home Assistant (Plant 001 & 002)
- Each sensor has proper device class, units, and icons

### Data Processing Pipeline
1. **Kafka Consumer**: Consumes from `plant-sensors` topic
2. **Health Analysis**: Analyzes soil moisture, light levels
3. **MongoDB Storage**: Stores raw data and alerts
4. **MQTT Publishing**: Sends processed data to Home Assistant
5. **Alert Generation**: Creates alerts for plant care needs

### Health Analysis Logic
- **Moisture Check**: Alerts if too low/high based on plant type
- **Light Check**: Alerts if insufficient light detected  
- **Health Score**: 0-100 points based on sensor readings
- **Status**: healthy/needs_attention/critical

## Network Dependencies

- **Kafka**: 10.0.143.200:9092 (VM-1)
- **MongoDB**: 10.0.135.192:27017 (VM-2) 
- **MQTT**: 10.0.15.111:1883 (VM-4)

## Memory Optimization

- **Node.js Heap**: Limited to 256MB for t2.micro
- **Container Memory**: Limited to 512MB
- **Health Checks**: Waits for Kafka and MongoDB availability
