# VM-4: Home Assistant + MQTT + Sensors Setup Instructions

## Deployment Commands

```bash
# Connect to VM-4
ssh -i plant-monitoring-key.pem ubuntu@10.0.15.111

# Create application directory
sudo mkdir -p /opt/homeassistant
cd /opt/homeassistant

# Copy all files to this directory structure:
# /opt/homeassistant/
# ├── docker-compose.yml
# ├── mosquitto/
# │   └── config/
# │       └── mosquitto.conf
# └── plant-sensors/
#     ├── Dockerfile
#     ├── package.json
#     └── sensor.js

# Start all services
sudo docker compose up -d --build

# Verify all services are running
sudo docker compose ps

# Check logs
sudo docker compose logs homeassistant
sudo docker compose logs mosquitto
sudo docker compose logs plant-sensor-001
sudo docker compose logs plant-sensor-002
```

## Service Details

### Home Assistant
- **Port**: 8123 (web interface)
- **Features**: Automatic MQTT discovery enabled
- **Sensors**: All 10 plant sensors auto-discovered
- **Access**: http://VM4-PUBLIC-IP:8123

### MQTT Broker (Mosquitto)
- **Port**: 1883
- **Configuration**: Anonymous access allowed for simplicity
- **Topics**: Discovery and state messages for plant sensors

### Plant Sensors (Simulators)
- **Plant 001**: Monstera in Living Room (30s intervals)
- **Plant 002**: Snake Plant in Bedroom (45s intervals)
- **Features**: Realistic daily cycles, environmental simulation
- **Output**: Publishes to Kafka `plant-sensors` topic

## Key Features

### Realistic Sensor Simulation
- **Daily Cycles**: Light follows sun patterns (6am-6pm)
- **Environmental Variation**: Temperature, humidity fluctuations
- **Plant-Specific**: Different base values per plant type
- **Random Noise**: Adds realistic sensor variability

### Automatic Discovery
- All sensors automatically appear in Home Assistant
- Proper device classes and units configured
- Icons and friendly names assigned
- No manual configuration required

## Network Configuration

- **Kafka**: Sends data to 10.0.143.200:9092 (VM-1)
- **MQTT**: Local broker on port 1883
- **Home Assistant**: Web interface on port 8123

## Memory Optimization

- **Home Assistant**: Limited to 512MB
- **Mosquitto**: Limited to 128MB  
- **Each Sensor**: Limited to 128MB with reduced Node.js heap

## Monitoring Commands

```bash
# Monitor MQTT messages
sudo docker compose exec mosquitto mosquitto_sub -h localhost -t "homeassistant/sensor/+/config" -v
sudo docker compose exec mosquitto mosquitto_sub -h localhost -t "homeassistant/sensor/+/state" -v

# Monitor sensor output
sudo docker compose logs -f plant-sensor-001
sudo docker compose logs -f plant-sensor-002

# Access Home Assistant
# Open browser to: http://YOUR-VM4-PUBLIC-IP:8123
```
