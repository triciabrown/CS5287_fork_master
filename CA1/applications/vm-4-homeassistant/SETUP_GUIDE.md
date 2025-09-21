# 🏠 Plant Monitoring System - Home Assistant Setup Guide

## 🚀 Quick Start

Your Plant Monitoring System is **automatically configured** with MQTT integration! No manual setup required.

### 📊 **Accessing Your Dashboard**

1. **Open your web browser** and navigate to: `http://YOUR_PUBLIC_IP:8123`
2. **First-time setup**: Create your Home Assistant user account
3. **MQTT is pre-configured** - sensors will appear automatically!

### 🌱 **What You'll See**

Your dashboard will automatically display:
- **Plant 001** (Monstera - Living Room)
  - Soil Moisture Level
  - Light Level  
  - Temperature
  - Humidity
  - Health Status

- **Plant 002** (Sansevieria - Bedroom)
  - Soil Moisture Level
  - Light Level
  - Temperature  
  - Humidity
  - Health Status

### 🔧 **MQTT Configuration (Pre-configured)**

The system automatically configures:
- **MQTT Broker**: `localhost:1883` (internal)
- **Discovery**: Enabled (sensors appear automatically)
- **Topics**: `homeassistant/sensor/plant_*`

### 📈 **System Components**

1. **Sensors**: Simulate real plant sensors (moisture, light, temperature)
2. **Kafka**: Message streaming for sensor data
3. **Processor**: Analyzes data and publishes to Home Assistant  
4. **MQTT**: Communication bridge to Home Assistant
5. **Home Assistant**: Your monitoring dashboard

### 🛠️ **Advanced Configuration**

All configuration files are located in `/opt/homeassistant/config/`:
- `configuration.yaml` - Main configuration
- `sensors.yaml` - MQTT sensor definitions
- `automations.yaml` - Plant care automations
- `customize.yaml` - Entity customizations

### 🔍 **Troubleshooting**

If sensors don't appear:
1. Check MQTT integration: **Settings → Integrations → MQTT**
2. Verify broker connection: `mosquitto_pub -h localhost -t test -m "hello"`
3. Check processor logs: `docker logs processor-plant-processor-1`

### 📱 **Mobile Access**

Home Assistant is accessible from any device on your network:
- Desktop: `http://YOUR_IP:8123`
- Mobile: Download "Home Assistant" app and connect to your server

### 🎯 **Next Steps**

1. **Explore** your plant dashboard
2. **Set up notifications** for low moisture levels
3. **Create automations** for plant care reminders  
4. **Add more plants** by modifying sensor configurations

---
**🌿 Happy Plant Monitoring!**