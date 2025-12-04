````markdown
# TODO - Next Troubleshooting Session
**Date Created:** October 17, 2025  
**Last Updated:** October 18, 2025 12:25 AM
**Status:** 🔴 CRITICAL SECURITY ISSUE IDENTIFIED

---

## 🔴 CRITICAL SECURITY VULNERABILITY - FIX FIRST!

### **ISSUE: Internal Services Exposed on Public IP**
**SEVERITY: CRITICAL** ⚠️  
**Discovered:** October 18, 2025

**Problem:**
ALL services (Kafka, MongoDB, MQTT) are currently published to the public IP address, not just Home Assistant. This violates the security architecture requirement.

**Evidence:**
```
Deployment Output Shows:
  🏠 Home Assistant:  http://18.116.50.145:8123  ✅ CORRECT (should be public)
  📡 MQTT Broker:     18.116.50.145:1883         ❌ EXPOSED (should be internal only!)
  📊 Kafka:           18.116.50.145:9092         ❌ EXPOSED (should be internal only!)
  🗄️  MongoDB:         18.116.50.145:27017       ❌ EXPOSED (should be internal only!)
```

**Root Cause:**
`docker-compose.yml` has `ports:` sections with `mode: host` for ALL services, which publishes them to the manager's public IP (0.0.0.0).

**Security Risk:**
- MongoDB database accessible from internet (even with auth, this is dangerous)
- Kafka message broker exposed (potential data exfiltration)
- MQTT broker accessible (IoT attack vector)
- Violates least privilege access principle from CA1

**FIX REQUIRED (Do this FIRST tomorrow):**

1. **Edit `docker-compose.yml` - REMOVE these port sections:**
   ```yaml
   # Lines ~40-45 - DELETE:
   kafka:
     ports:  # ❌ DELETE THIS ENTIRE SECTION
       - target: 9092
         published: 9092
         protocol: tcp
         mode: host
   
   # Lines ~91-96 - DELETE:
   mongodb:
     ports:  # ❌ DELETE THIS ENTIRE SECTION
       - target: 27017
         published: 27017
         protocol: tcp
         mode: host
   
   # Lines ~139-144 - DELETE:
   mosquitto:
     ports:  # ❌ DELETE THIS ENTIRE SECTION
       - target: 1883
         published: 1883
         protocol: tcp
         mode: host
   
   # Lines ~172-174 - KEEP (only public service):
   homeassistant:
     ports:  # ✅ KEEP - This is the only service that should be public
       - target: 8123
         published: 8123
         protocol: tcp
   ```

2. **After removing ports, services communicate via overlay network:**
   - Services reference each other by name: `kafka:9092`, `mongodb:27017`, `mosquitto:1883`
   - Docker overlay network `plant-network` handles routing internally
   - NO external access except Home Assistant

3. **Redeploy:**
   ```bash
   cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC
   ./deploy.sh
   ```

4. **Verify security fix (from your laptop):**
   ```bash
   # These should TIMEOUT (not accessible):
   telnet <MANAGER_IP> 9092   # Kafka
   telnet <MANAGER_IP> 27017  # MongoDB
   telnet <MANAGER_IP> 1883   # MQTT
   
   # This should WORK (accessible):
   curl http://<MANAGER_IP>:8123  # Home Assistant
   ```

5. **For debugging internal services, use SSH tunneling:**
   ```bash
   # From your laptop:
   ssh -i ~/.ssh/docker-swarm-key -L 27017:mongodb:27017 ubuntu@<MANAGER_IP>
   # Then connect to localhost:27017 on your laptop
   ```

6. **Update deploy.sh output (around line 380):**
   - Remove Kafka, MongoDB, MQTT from "Access Information" section
   - Only show Home Assistant as publicly accessible
   - Add note about SSH tunneling for internal access

**This must be fixed BEFORE final submission!**

---

## 🎯 Current Deployment Status

### ✅ Working Components (6/7 services)
- [x] Infrastructure: VPC, subnets, NAT Gateway, security groups
- [x] Zookeeper: 1/1 replicas
- [x] Kafka: 1/1 replicas  
- [x] MongoDB: 1/1 replicas
- [x] Mosquitto MQTT: 1/1 replicas
- [x] Home Assistant: 1/1 replicas - http://3.135.203.107:8123
- [x] **Sensors: 2/2 replicas - SUCCESSFULLY SENDING DATA!**
  - Config loading working: `/app/sensor-config.json`
  - Sending to Kafka: `plant-001` (monstera) data every 30s
  - Sample output: `{ moisture: '46.5', light: '76', temp: '19.0', humidity: '52.0' }`

### ⚠️ Issue: Processor Service (0/1 replicas)
**Primary Problem:** MongoDB Authentication Failure

**Error Message:**
```
MongoServerError: Authentication failed.
code: 18
codeName: 'AuthenticationFailed'
```

---

## 📋 Priority 1: Fix MongoDB Authentication

### Issue Analysis
The processor service is failing to connect to MongoDB with authentication error. This prevents the data pipeline from completing:
```
Sensors → Kafka → ❌ Processor → MongoDB + MQTT → Home Assistant
```

### Troubleshooting Steps

#### Step 1: Verify MongoDB Secret Content
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.135.203.107

# Check what secrets exist
docker secret ls

# Inspect the MongoDB connection string secret
docker secret inspect mongodb_connection_string

# Try to see what's in the secret (from a running container)
docker service ps plant-monitoring_mongodb
docker exec -it <mongodb-container-id> cat /run/secrets/mongodb_connection_string
```

**Expected Format:**
```
mongodb://plantuser:PlantUserPass123!@mongodb:27017/plant_monitoring?authSource=admin
```

**Check For:**
- [ ] Correct username: `plantuser`
- [ ] Correct password: `PlantUserPass123!`
- [ ] Correct host: `mongodb` (not an IP address)
- [ ] Correct port: `27017`
- [ ] Correct database: `plant_monitoring`
- [ ] Auth source parameter: `?authSource=admin`
- [ ] No extra whitespace or newlines

#### Step 2: Verify MongoDB User Creation
```bash
# Connect to MongoDB container
docker exec -it $(docker ps -q -f name=plant-monitoring_mongodb) mongosh

# Check if user exists
use admin
db.getUsers()

# Verify authentication works
use admin
db.auth("plantuser", "PlantUserPass123!")

# Check if database exists
show dbs
use plant_monitoring
show collections
```

**Expected:**
- [ ] User `plantuser` exists in `admin` database
- [ ] User has readWrite role on `plant_monitoring` database
- [ ] Authentication succeeds
- [ ] Database `plant_monitoring` is accessible

#### Step 3: Check Ansible Secret Creation
Location: `ansible/deploy-stack.yml` lines ~77-95

```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC

# Review how secrets are created
cat ansible/deploy-stack.yml | grep -A 20 "Create Docker secrets"
```

**Verify:**
- [ ] Secret creation uses correct format
- [ ] Password matches what MongoDB init script expects
- [ ] Connection string includes all required parameters
- [ ] No shell escaping issues with special characters (`!` in password)

#### Step 4: Check MongoDB Initialization
MongoDB should be initialized with the user. Check the initialization:

```bash
# Check MongoDB logs
docker service logs plant-monitoring_mongodb --tail 100

# Look for user creation messages
docker service logs plant-monitoring_mongodb | grep -i "user\|auth\|created"
```

**Look For:**
- [ ] "Successfully added user" message
- [ ] No authentication errors in MongoDB logs
- [ ] MongoDB is accepting connections

#### Step 5: Fix Connection String Format
If the connection string is wrong, update it in Ansible:

File: `ansible/deploy-stack.yml` around line 85

**Current:**
```yaml
echo "mongodb://\${MONGO_USER}:\${MONGO_PASS}@mongodb:27017/plant_monitoring" | \
  docker secret create mongodb_connection_string -
```

**Should Be:**
```yaml
echo "mongodb://\${MONGO_USER}:\${MONGO_PASS}@mongodb:27017/plant_monitoring?authSource=admin" | \
  docker secret create mongodb_connection_string -
```

#### Step 6: Rebuild and Redeploy
If changes are needed:

```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC

# Teardown existing deployment
./teardown.sh

# Redeploy with fixed configuration
./deploy.sh
```

---

## 📋 Priority 2: Verify Data Flow End-to-End

Once processor is working, verify complete pipeline:

### Step 1: Check Kafka Topics
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.135.203.107

# Enter Kafka container
docker exec -it $(docker ps -q -f name=plant-monitoring_kafka) bash

# List topics
kafka-topics --list --bootstrap-server localhost:9092

# Consume messages from sensor topic
kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic plant-sensors --from-beginning --max-messages 5
```

**Expected:**
- [ ] Topic `plant-sensors` exists
- [ ] Messages from `plant-001` (and potentially `plant-002`) visible
- [ ] JSON data includes: plantId, location, plantType, sensors (moisture, light, temp, humidity)

### Step 2: Check MongoDB Data Storage
```bash
# Connect to MongoDB
docker exec -it $(docker ps -q -f name=plant-monitoring_mongodb) mongosh

use plant_monitoring
db.sensor_readings.find().limit(5).pretty()
db.sensor_readings.countDocuments()
```

**Expected:**
- [ ] Collection `sensor_readings` exists
- [ ] Documents contain sensor data
- [ ] Timestamps are recent
- [ ] Data matches what sensors are sending

### Step 3: Check MQTT Publishing
```bash
# Subscribe to MQTT topics
docker exec -it $(docker ps -q -f name=plant-monitoring_mosquitto) \
  mosquitto_sub -h localhost -t "homeassistant/#" -v
```

**Expected:**
- [ ] MQTT discovery messages for sensors
- [ ] Sensor state updates being published
- [ ] Topics following Home Assistant format: `homeassistant/sensor/plant_001_*/state`

### Step 4: Verify Home Assistant Integration
```bash
# Access Home Assistant
# URL: http://3.135.203.107:8123
```

**In Home Assistant UI:**
- [ ] Navigate to Developer Tools → States
- [ ] Search for `sensor.plant_001`
- [ ] Verify sensors appear:
  - `sensor.plant_001_moisture`
  - `sensor.plant_001_health`
  - `sensor.plant_001_light`
  - `sensor.plant_001_temperature`
  - `sensor.plant_001_status`
- [ ] Values are updating (check timestamps)
- [ ] Create a simple dashboard to visualize plant data

---

## 📋 Priority 3: Network Security Verification

Verify the secure architecture is working as designed:

### Current Architecture
```
Public Subnet (10.0.1.0/24):
  - Manager Node (has public IP: 3.135.203.107)
    - Runs: Home Assistant (port 8123 publicly accessible)
    
Private Subnet (10.0.2.0/24):
  - Worker Nodes (NO public IPs)
  - NAT Gateway for outbound internet (Docker Hub, updates)
```

### Verification Steps

```bash
# 1. Check infrastructure
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC
terraform output

# 2. SSH to manager
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.135.203.107

# 3. List nodes and their IPs
docker node ls
docker node inspect <node-id> | grep Addr

# 4. Verify placement
docker service ps plant-monitoring_homeassistant --no-trunc
docker service ps plant-monitoring_sensor --no-trunc
```

**Verify:**
- [ ] Manager node is in public subnet (10.0.1.x)
- [ ] Worker nodes are in private subnet (10.0.2.x) - if using worker constraints
- [ ] Home Assistant accessible from internet: http://3.135.203.107:8123
- [ ] MongoDB port 27017 NOT accessible from internet
- [ ] Kafka port 9092 NOT accessible from internet
- [ ] Only SSH (22) and HA (8123) exposed to 0.0.0.0/0

---

## 📋 Priority 4: Performance and Scaling Tests

Once everything is working:

### Test Service Scaling
```bash
# Scale sensors up
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.135.203.107 \
  'docker service scale plant-monitoring_sensor=5'

# Watch scaling
watch -n 2 'docker service ps plant-monitoring_sensor'

# Check if all replicas are distributing load
docker service logs plant-monitoring_sensor --tail 50 | grep "plant-"

# Scale back down
docker service scale plant-monitoring_sensor=2
```

**Verify:**
- [ ] New replicas start successfully
- [ ] Each replica gets different plant config (via TASK_SLOT)
- [ ] Load is distributed across nodes (if multi-node)
- [ ] No data loss during scaling

### Monitor Resource Usage
```bash
# Check service resource consumption
docker stats

# Check specific service
docker service ps plant-monitoring_kafka --format "{{.Node}} {{.CurrentState}}"
```

**Check:**
- [ ] Memory usage within limits (sensor: 128M, processor: 512M)
- [ ] CPU usage reasonable
- [ ] No services being killed/restarted due to OOM

---

## 📋 Priority 5: Documentation Updates

### Update README.md
Add sections for:
- [ ] Quick start guide
- [ ] Architecture diagram (network topology)
- [ ] Troubleshooting common issues
- [ ] Access information for deployed services

### Create Deployment Verification Checklist
Create: `DEPLOYMENT_VERIFICATION.md`

Include:
- [ ] Pre-deployment checks
- [ ] Post-deployment validation steps
- [ ] Smoke tests for each service
- [ ] Data flow verification commands

### Document Security Architecture
Create: `SECURITY_ARCHITECTURE.md`

Include:
- [ ] Network topology diagram
- [ ] Firewall rules (security groups)
- [ ] Secrets management approach
- [ ] Access control matrix
- [ ] Compliance with least privilege principle

---

## 🔍 Quick Reference Commands

### Deployment
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC

# Deploy
./deploy.sh

# Teardown
./teardown.sh

# Check status
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.135.203.107 'docker stack services plant-monitoring'
```

### Debugging
```bash
# View all service logs
docker service logs plant-monitoring_<service-name> --tail 100 --follow

# Check service status
docker service ps plant-monitoring_<service-name> --no-trunc

# Inspect service configuration
docker service inspect plant-monitoring_<service-name> --pretty

# Force service update (pull new image)
docker service update --image docker.io/triciab221/plant-processor:v1.0.0 --force plant-monitoring_processor
```

### Image Management
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/applications

# Rebuild and push images
PUSH_IMAGES=true ./build-images.sh

# Check local images
docker images | grep triciab221
```

---

## 📝 Known Working Configuration

### Images (Verified on Docker Hub)
- ✅ `triciab221/plant-sensor:v1.0.0` - Config loading working
- ✅ `triciab221/plant-processor:v1.0.0` - Secret file reading working

### Secrets (Defined in Ansible)
- `mongo_root_password` - MongoDB root password
- `mongo_user_password` - MongoDB plantuser password
- `mongodb_connection_string` - Full connection URL ⚠️ **NEEDS VERIFICATION**

### Configs (Docker Configs)
- ✅ `mosquitto_config` - Mosquitto configuration
- ✅ `sensor_config` - Sensor plant profiles (2 plants: monstera, sansevieria)

### Services Status
```
✅ Zookeeper: 1/1
✅ Kafka: 1/1
✅ MongoDB: 1/1
✅ Mosquitto: 1/1
✅ Home Assistant: 1/1 - http://3.135.203.107:8123
✅ Sensor: 2/2 - Sending data successfully
⚠️ Processor: 0/1 - MongoDB auth failure
```

---

## 🎯 Session Goals

**Primary Goal:**
- [ ] Fix MongoDB authentication and get processor service running

**Secondary Goals:**
- [ ] Verify complete data pipeline (sensor → Kafka → processor → MongoDB → MQTT → Home Assistant)
- [ ] Confirm Home Assistant shows plant sensor data
- [ ] Document working configuration

**Stretch Goals:**
- [ ] Test service scaling
- [ ] Performance monitoring
- [ ] Create architecture diagrams
- [ ] Update all documentation

---

## 🚀 Quick Start for Tomorrow

```bash
# 1. Check current deployment status
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.135.203.107 'docker stack services plant-monitoring'

# 2. Start with MongoDB secret verification
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.135.203.107
docker secret ls
docker secret inspect mongodb_connection_string

# 3. Check MongoDB logs
docker service logs plant-monitoring_mongodb --tail 100

# 4. Check processor logs
docker service logs plant-monitoring_processor --tail 50

# 5. Verify MongoDB user
docker exec -it $(docker ps -q -f name=plant-monitoring_mongodb) mongosh
use admin
db.getUsers()
```

---

## 📚 Reference Files

- **Deployment Script:** `plant-monitor-swarm-IaC/deploy.sh`
- **Teardown Script:** `plant-monitor-swarm-IaC/teardown.sh`
- **Ansible Playbooks:**
  - `ansible/setup-swarm.yml` - Cluster initialization
  - `ansible/deploy-stack.yml` - Application deployment (CHECK SECRET CREATION HERE)
- **Docker Compose:** `docker-compose.yml`
- **Terraform Config:** `terraform/main.tf`
- **Processor App:** `applications/processor/app.js`
- **Sensor App:** `applications/sensor/sensor.js`

---

## ✅ Completed Today

- [x] Implemented secure AWS architecture (public/private subnets, NAT Gateway)
- [x] Fixed sensor config file loading
- [x] Updated processor to read MongoDB URL from secrets
- [x] Successfully deployed 6/7 services
- [x] Verified sensors are sending data to Kafka
- [x] Built and pushed versioned images (v1.0.0)
- [x] Created idempotent deployment/teardown scripts
- [x] Fixed Ansible playbook idempotency issues

**Great progress! Just need to fix that MongoDB auth issue tomorrow! 🎉**
