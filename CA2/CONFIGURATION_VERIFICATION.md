# Configuration Verification - Static IP DNS Bypass

**Date**: October 19, 2025  
**Approach**: Use static IPs for infrastructure services to bypass Docker Swarm DNS issues

---

## ✅ Static IP Assignments

### Infrastructure Services (with static IPs)
These services have **static IPs** because other services need to connect TO them:

| Service | Static IP | Port | Why Static? |
|---------|-----------|------|-------------|
| **ZooKeeper** | `10.10.0.10` | 2181 | Kafka needs to connect to it |
| **Kafka** | `10.10.0.11` | 9092 | Sensors & Processor connect to it |
| **MongoDB** | `10.10.0.12` | 27017 | Processor connects to it |
| **Mosquitto** | `10.10.0.13` | 1883 | Processor connects to it |

### Scalable Services (with dynamic IPs)
These services get **dynamic IPs** (from range `10.10.0.128-254`) because they are clients only:

| Service | IP Assignment | Scalability | Why Dynamic? |
|---------|---------------|-------------|--------------|
| **Sensor** | Dynamic | 1-100+ replicas | Only connects OUT to Kafka |
| **Processor** | Dynamic | 1-10+ replicas | Only connects OUT to services |
| **Home Assistant** | Dynamic | 1 replica | Only needs published port 8123 |

---

## ✅ Connection String Verification

### 1. Kafka Configuration
**File**: `docker-compose.yml` (lines 44-46)

```yaml
environment:
  KAFKA_BROKER_ID: 1
  KAFKA_ZOOKEEPER_CONNECT: '10.10.0.10:2181'  # ✅ ZooKeeper static IP
  KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://10.10.0.11:9092'  # ✅ Kafka static IP
```

**Status**: ✅ NO DNS - Uses static IPs

---

### 2. Processor Service
**File**: `docker-compose.yml` (lines 200-202)

```yaml
environment:
  KAFKA_BROKER: '10.10.0.11:9092'  # ✅ Kafka static IP
  MONGODB_URL_FILE: /run/secrets/mongodb_connection_string  # ✅ Uses secret with static IP
  MQTT_BROKER: 'mqtt://10.10.0.13:1883'  # ✅ Mosquitto static IP
```

**Status**: ✅ NO DNS - Uses static IPs

---

### 3. Sensor Service
**File**: `docker-compose.yml` (line 236)

```yaml
environment:
  KAFKA_BROKERS: '10.10.0.11:9092'  # ✅ Kafka static IP
  SENSOR_INTERVAL: '30'
```

**Status**: ✅ NO DNS - Uses static IP

---

### 4. MongoDB Connection String
**File**: `ansible/deploy-stack.yml` (line 95)

```bash
echo "mongodb://plant_app:PASSWORD@10.10.0.12:27017/plant_monitoring?authSource=admin" | docker secret create mongodb_connection_string -
```

**Status**: ✅ NO DNS - Uses static IP `10.10.0.12`

---

## ✅ Network Configuration

### Overlay Network Setup
**File**: `docker-compose.yml` (lines 273-283)

```yaml
networks:
  plant-network:
    driver: overlay
    driver_opts:
      encrypted: "true"
    ipam:
      driver: default
      config:
        - subnet: 10.10.0.0/24
          ip_range: 10.10.0.128/25  # Reserve .1-.127 for static, .128-.254 for dynamic
```

**IP Allocation**:
- **Static Range**: `10.10.0.1 - 10.10.0.127` (reserved for infrastructure)
- **Dynamic Range**: `10.10.0.128 - 10.10.0.254` (for scalable services)
- **Used Static IPs**:
  - `10.10.0.10` - ZooKeeper
  - `10.10.0.11` - Kafka
  - `10.10.0.12` - MongoDB
  - `10.10.0.13` - Mosquitto
  - `10.10.0.14-127` - Available for future services

---

## ✅ Placement Constraints

### Services That Must Run on Manager
These have data persistence requirements:

```yaml
# ZooKeeper
placement:
  constraints:
    - node.role == manager  # Needs persistent storage

# MongoDB
placement:
  constraints:
    - node.role == manager  # Database persistence

# Mosquitto
placement:
  constraints:
    - node.labels.mqtt == true  # Labeled on manager
```

### Services That Can Run Anywhere
These are stateless and can scale across workers:

```yaml
# Kafka
# No placement constraint - can run on any node ✅

# Processor
# No placement constraint - can scale across workers ✅

# Sensor
# No placement constraint - can scale across workers ✅

# Home Assistant
placement:
  constraints:
    - node.labels.mqtt == true  # Co-locate with MQTT for efficiency
```

---

## ✅ No DNS Hostnames Used

### DNS Removed From:
- ✅ `KAFKA_ZOOKEEPER_CONNECT`: Was `zookeeper:2181` → Now `10.10.0.10:2181`
- ✅ `KAFKA_ADVERTISED_LISTENERS`: Was `kafka:9092` → Now `10.10.0.11:9092`
- ✅ `KAFKA_BROKER` (processor): Was `kafka:9092` → Now `10.10.0.11:9092`
- ✅ `KAFKA_BROKERS` (sensor): Was `kafka:9092` → Now `10.10.0.11:9092`
- ✅ `MQTT_BROKER` (processor): Was `mosquitto:1883` → Now `10.10.0.13:1883`
- ✅ `mongodb_connection_string`: Was `mongodb:27017` → Now `10.10.0.12:27017`

### DNS No Longer Required For:
- ❌ Service-to-service communication (using static IPs instead)
- ✅ Container name resolution (not needed)
- ✅ Overlay network routing (works with IPs)

---

## ✅ Scalability Verification

### How Scaling Works:

#### Scaling Sensors (1 → 100 replicas)
```bash
docker service scale plant-monitoring_sensor=100
```

**What Happens**:
1. Docker creates 100 sensor containers
2. Each gets a **dynamic IP** from `10.10.0.128-254` range
3. All 100 sensors connect to **Kafka at 10.10.0.11**
4. Kafka accepts connections from any IP on port 9092
5. Load balancing happens at Kafka level (consumer groups)

**No DNS needed** ✅

#### Scaling Processors (1 → 10 replicas)
```bash
docker service scale plant-monitoring_processor=10
```

**What Happens**:
1. Docker creates 10 processor containers
2. Each gets a **dynamic IP** from `10.10.0.128-254` range
3. All 10 processors connect to:
   - **Kafka at 10.10.0.11**
   - **MongoDB at 10.10.0.12**
   - **Mosquitto at 10.10.0.13**
4. Load balancing via Kafka consumer groups

**No DNS needed** ✅

---

## ✅ Benefits of This Approach

### 1. **DNS Independence**
- ❌ No reliance on Docker Swarm's broken embedded DNS
- ✅ Services connect using predictable static IPs
- ✅ Works across all nodes (manager + workers)

### 2. **Scalability Maintained**
- ✅ Infrastructure services have fixed IPs (can be found)
- ✅ Client services have dynamic IPs (can scale freely)
- ✅ No IP conflicts (separate ranges)

### 3. **Cross-Node Communication**
- ✅ Services on worker nodes can reach Kafka on any node
- ✅ Overlay network routes by IP (doesn't need DNS)
- ✅ No "ENOTFOUND" errors

### 4. **Production Ready**
- ✅ Static IPs for infrastructure = predictable
- ✅ Dynamic IPs for clients = flexible
- ✅ Standard approach used in Kubernetes, Docker Swarm production

---

## ✅ Potential Issues (And Mitigations)

### Issue 1: What if Kafka container restarts?
**Answer**: Static IP is assigned at the **service level**, not container level. When Kafka restarts, Docker Swarm ensures it gets the same IP (`10.10.0.11`).

### Issue 2: What if we need to change Kafka's IP?
**Answer**: 
1. Update `docker-compose.yml` with new IP
2. Redeploy stack: `./deploy.sh`
3. All services get the new IP automatically
4. Takes ~5 minutes total

### Issue 3: What if we run out of dynamic IPs?
**Answer**: 
- Dynamic range: `10.10.0.128-254` = **126 IPs**
- Max sensors + processors: ~100 total
- If needed, can expand subnet to `/16` for 65,534 IPs

### Issue 4: What about Home Assistant config?
**Answer**:
- Home Assistant doesn't connect to Kafka directly
- Processor pushes data to MQTT (10.10.0.13)
- Home Assistant subscribes to MQTT topics
- No DNS needed ✅

---

## ✅ Testing Checklist

### Pre-Deployment
- [x] docker-compose.yml: All IPs are static (no hostnames)
- [x] deploy-stack.yml: MongoDB connection string uses IP
- [x] Network config: Static range reserved (10.10.0.1-127)
- [x] Services: Placement constraints appropriate

### Post-Deployment
- [ ] Check services are running: `docker service ls`
- [ ] Verify static IPs assigned: `docker network inspect plant-monitoring_plant-network`
- [ ] Check processor logs: No "ENOTFOUND" errors
- [ ] Check sensor logs: No "Connection timeout" errors
- [ ] Test scaling: `./scaling-test.sh`
- [ ] Verify message flow: Check MongoDB for sensor data

---

## ✅ Deployment Ready

All DNS hostname references have been replaced with static IPs. The configuration is ready for deployment.

**Next Step**: Run `./deploy.sh`
