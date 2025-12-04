# CA4 Network Architecture - Multi-Tier Segmentation

## Overview
The CA4 plant monitoring system uses **network segmentation** across three tiers to isolate services by function and improve security. This is a key improvement over CA2.

## Network Tiers

### 1. Frontend Tier (10.10.1.0/24)
**Purpose:** Public-facing user interfaces

**Services:**
- **Home Assistant** (port 8123)
  - Only service exposed externally
  - Cannot access Kafka or MongoDB directly
  - Communicates via MQTT only

### 2. Messaging Tier (10.10.2.0/24)
**Purpose:** Message queue infrastructure

**Services:**
- **Zookeeper** (port 2181)
  - Kafka cluster coordination
  - Metadata management
  - Only accessible within messaging-net

- **Kafka** (ports 9092, 9093)
  - INTERNAL listener: `kafka:9092` (cloud services only)
  - EXTERNAL listener: `10.20.0.1:9093` (VPN - edge sensors)
  - Topic: `plant-sensors`
  - Consumer Group: `plant-processor-group`

- **Mosquitto MQTT** (port 1883)
  - **MULTI-NETWORK**: Connected to frontend-net, messaging-net, AND data-net
  - Reason: Needs to receive from processor (data-net) AND send to Home Assistant (frontend-net)

### 3. Data Tier (10.10.3.0/24)
**Purpose:** Data persistence and storage

**Services:**
- **MongoDB** (port 27017)
  - Database: `plant_monitoring`
  - Collections: `sensor_readings`, `plant_configurations`
  - Only accessible within data-net
  - No external access

## Multi-Network Components

### Plant Processor
**Networks:** messaging-net (10.10.2.0/24) + data-net (10.10.3.0/24)

**Why both networks?**
- **messaging-net**: To consume messages from Kafka (via `kafka:9092`)
- **data-net**: To write to MongoDB AND publish to MQTT

**Configuration:**
```yaml
processor:
  networks:
    - messaging-net  # Access to Kafka
    - data-net       # Access to MongoDB + Mosquitto
```

**Scalable:** Can scale from 1→3 replicas for load testing

### Mosquitto MQTT
**Networks:** frontend-net + data-net

**Why both networks?**
- **data-net**: To receive published events from processor
- **frontend-net**: To serve subscriptions to Home Assistant

**Configuration:**
```yaml
mosquitto:
  networks:
    - frontend-net  # Access from Home Assistant
    - data-net      # Access from Processor
```

## Security Benefits

### Network Isolation
1. **Home Assistant** cannot directly query MongoDB
   - Must use MQTT messages published by processor
   - Prevents unauthorized database access

2. **Frontend tier** cannot access Kafka
   - No direct access to message queue
   - Prevents message injection

3. **Kafka** is isolated in messaging tier
   - Only processor and edge sensors (via VPN) can access
   - Internal listener (`kafka:9092`) only for cloud services

### Defense in Depth
- Even if Home Assistant is compromised, attacker cannot:
  - Read raw sensor data from MongoDB
  - Inject messages into Kafka
  - Access backend infrastructure

## VPN Integration

### WireGuard Tunnel
- **Subnet:** 10.20.0.0/24
- **Cloud Gateway:** 10.20.0.1 (on manager node)
- **Edge Client:** 10.20.0.2

### Kafka VPN Access
Kafka's EXTERNAL listener is published on the manager node using `mode: host`:

```yaml
kafka:
  ports:
    - target: 9093
      published: 9093
      protocol: tcp
      mode: host  # Binds to manager's network interface
  deploy:
    placement:
      constraints:
        - node.role == manager  # Must run on manager where VPN terminates
```

**Why mode: host?**
- VPN traffic arrives at manager node (10.20.0.1)
- `mode: host` binds port 9093 to manager's actual interface
- Edge sensors connect to `10.20.0.1:9093` (manager's VPN IP)
- Traffic routes directly to Kafka container on manager

**Alternative (ingress mode) would NOT work:**
- Docker's ingress load balancer uses IPVS/iptables
- VPN tunnel wouldn't route properly through ingress mesh
- Connection would fail or go to wrong node

## Data Flow Across Networks

```
Edge Sensors (via VPN 10.20.0.0/24)
    ↓
Kafka EXTERNAL listener (10.20.0.1:9093 on messaging-net)
    ↓
Processor consumes (messaging-net → Kafka)
    ↓
Processor writes (data-net → MongoDB)
    ↓
Processor publishes (data-net → MQTT)
    ↓
Home Assistant subscribes (frontend-net → MQTT)
    ↓
User views dashboard (external → port 8123)
```

## Network Diagram Legend

- **messaging-net only:** Zookeeper, Kafka
- **data-net only:** MongoDB
- **frontend-net only:** Home Assistant
- **messaging-net + data-net:** Processor (needs both to consume from Kafka and write to MongoDB)
- **frontend-net + data-net:** MQTT (needs both to receive from processor and serve Home Assistant)

## AWS VPC Context
All overlay networks (frontend-net, messaging-net, data-net) operate within the AWS VPC (10.0.0.0/16). The VPC provides:
- Network isolation from internet
- Security groups for EC2 instance access control
- VPN endpoint for edge connectivity

The VPN tunnel (10.20.0.0/24) is a separate subnet that bridges the edge site to the cloud VPC.
