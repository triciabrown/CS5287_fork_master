# MQTT Setup Guide for Home Assistant

## Quick Setup Instructions

After accessing your Home Assistant dashboard at `http://<your-vm-ip>:8123`, follow these steps to configure MQTT:

### Step 1: Access Integrations
1. Go to **Settings** → **Devices & services**
2. Click the **"+ ADD INTEGRATION"** button
3. Search for **"MQTT"** and select it

### Step 2: Configure MQTT Broker
Enter the following settings:
- **Broker**: `{{ ansible_host }}` (this VM's IP address)
- **Port**: `1883`
- **Username**: (leave blank for local connection)
- **Password**: (leave blank for local connection)

### Step 3: Enable Discovery
- **Enable discovery**: ✅ (checked)
- **Discovery prefix**: `homeassistant` (default)

### Step 4: Verify Plant Sensors
After setup, your plant sensors should appear automatically as:
- `sensor.plant_001_moisture`
- `sensor.plant_001_temperature` 
- `sensor.plant_001_humidity`
- `sensor.plant_001_light`
- `sensor.plant_002_moisture`
- `sensor.plant_002_temperature`
- `sensor.plant_002_humidity`
- `sensor.plant_002_light`

## Troubleshooting

### MQTT Not Connecting
- Verify Mosquitto broker is running: `docker ps | grep mosquitto`
- Check broker logs: `docker logs homeassistant-mosquitto-1`

### Sensors Not Appearing
- Check plant sensor logs: `docker logs homeassistant-plant-sensor-001-1`
- Verify MQTT discovery is enabled in the integration settings
- Go to **Settings** → **Devices & services** → **MQTT** → **Configure**

### Manual Sensor Discovery
If sensors don't auto-discover, you can listen for MQTT messages:
1. Go to **Settings** → **Devices & services** → **MQTT** → **Configure**  
2. In **"Listen to a topic"**, enter: `homeassistant/sensor/+/config`
3. Click **"START LISTENING"** to see discovery messages

### Connection Issues
If you can't connect to MQTT:
- ✅ Use VM IP address: `{{ ansible_host }}:1883`
- ❌ Don't use: `localhost:1883` (won't work from browser)
- Verify MQTT broker is accessible: `telnet {{ ansible_host }} 1883`

## System Info
- **MQTT Broker**: Eclipse Mosquitto 2.0 (containerized)
- **Broker URL**: `{{ ansible_host }}:1883` (accessible from outside the container)
- **Internal URL**: `localhost:1883` (for containers in same network)
- **Discovery**: Enabled with prefix `homeassistant`
- **Plant Sensors**: 2 sensors sending data every 30 seconds
- **Data Flow**: Plant Sensors → Kafka → Processor → MongoDB → MQTT → Home Assistant