# Cross-Node Communication Testing Plan

**Date**: October 19, 2025  
**Purpose**: Test if self-referencing security group rules fix Docker Swarm DNS issues

---

## Updated Deployment Strategy

### Service Placement (After Removing Manager-Only Constraints)

| Service | Constraint | Expected Placement | Reason |
|---------|-----------|-------------------|---------|
| **ZooKeeper** | None | Any node | Swarm scheduler decides |
| **Kafka** | None | Any node | Let it distribute to test DNS |
| **MongoDB** | None | Any node | Test cross-node access |
| **Processor** | None | Any node | **Key test**: Will it find Kafka/MongoDB? |
| **Mosquitto** | `node.labels.mqtt == true` | Manager | Needs to be with Home Assistant |
| **Home Assistant** | `node.labels.mqtt == true` | Manager | Needs public port 8123 |
| **Sensors** (x2) | None | Any nodes | **Will distribute across workers** |

### Why This Distribution Tests Cross-Node

**Scenario 1: Processor on Worker, Kafka on Manager**
```
Worker Node: Processor
    ↓ needs to resolve 'kafka'
Manager Node: Kafka
```
If DNS works: ✅ Processor connects to Kafka successfully  
If DNS broken: ❌ Processor gets `ENOTFOUND kafka`

**Scenario 2: Sensors on Workers, Kafka on Manager**
```
Worker1: Sensor replica 1
    ↓ needs to resolve 'kafka'
Worker2: Sensor replica 2
    ↓ needs to resolve 'kafka'
Manager: Kafka
```
If DNS works: ✅ Sensors send data to Kafka  
If DNS broken: ❌ Sensors can't find Kafka

**Scenario 3: All Services Distributed**
```
Worker1: MongoDB, Sensor
Worker2: Kafka, Sensor  
Worker3: ZooKeeper
Manager: Processor, Mosquitto, Home Assistant
```
This creates maximum cross-node communication testing.

---

## Testing Procedure

### Phase 1: Deploy with Security Group Fixes

```bash
# 1. Teardown existing deployment
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC
./teardown.sh

# 2. Apply Terraform security group changes
cd terraform/
terraform plan   # Review self-referencing rules
terraform apply  # Apply changes

# 3. Deploy stack (services will distribute)
cd ..
./deploy.sh
```

### Phase 2: Check Service Placement

```bash
# See where each service landed
docker service ps plant-monitoring_kafka
docker service ps plant-monitoring_zookeeper
docker service ps plant-monitoring_mongodb
docker service ps plant-monitoring_processor
docker service ps plant-monitoring_sensor

# Summary view
docker stack ps plant-monitoring --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}"
```

**Expected**: Services spread across multiple nodes (manager + workers)

### Phase 3: Check Service Health

```bash
# Check if all services are running
docker stack services plant-monitoring

# Look for:
# - All services showing X/X replicas (not 0/X)
# - "Running" state, not "Starting" or "Failed"
```

### Phase 4: Check Logs for DNS Errors

```bash
# Processor logs (key indicator)
docker service logs plant-monitoring_processor --tail 50

# Look for:
# ✅ SUCCESS: "Connected to Kafka", "Connected to MongoDB"
# ❌ FAILURE: "ENOTFOUND kafka", "Connection timeout"

# Sensor logs
docker service logs plant-monitoring_sensor --tail 50

# Look for:
# ✅ SUCCESS: "Sent sensor data" messages
# ❌ FAILURE: "KafkaJSConnectionError", "ENOTFOUND"

# Kafka logs
docker service logs plant-monitoring_kafka --tail 50

# Look for:
# ✅ SUCCESS: "started (kafka.server.KafkaServer)"
# ❌ FAILURE: "Connection refused", "ZooKeeper timeout"
```

### Phase 5: Test DNS Resolution Directly

```bash
# Get manager IP from Terraform
cd terraform/
MANAGER_IP=$(terraform output -raw manager_public_ip)
cd ..

# SSH to manager
ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP}

# Find a running processor or sensor container
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

# Test DNS from inside container (use processor container ID)
docker exec <processor-container-id> nslookup kafka
docker exec <processor-container-id> nslookup zookeeper
docker exec <processor-container-id> nslookup mongodb

# Expected:
# ✅ SUCCESS: Returns IP address (e.g., 10.10.0.5)
# ❌ FAILURE: "server can't find kafka"
```

### Phase 6: Test End-to-End Data Flow

```bash
# 1. Check if sensors are publishing to Kafka
docker exec $(docker ps -q -f name=kafka) kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic plant-sensors \
  --from-beginning \
  --max-messages 5

# Expected: Should see sensor data JSON

# 2. Check if processor is writing to MongoDB
docker exec $(docker ps -q -f name=mongodb) mongosh \
  --eval "use plant_monitoring; db.sensor_readings.find().limit(5).pretty()"

# Expected: Should see sensor readings

# 3. Check Home Assistant
curl http://<manager-ip>:8123
# Expected: HTTP 200 OK
```

---

## Success Criteria

### ✅ DNS Fix Worked If:

1. **All services show X/X replicas** (not stuck at 0/X)
2. **No `ENOTFOUND` errors** in any service logs
3. **Services on different nodes communicate** successfully
4. **Processor logs show**: "Connected to Kafka", "Connected to MongoDB"
5. **Sensor logs show**: "Sent sensor data to topic plant-sensors"
6. **Data appears in MongoDB** and flows to Home Assistant
7. **DNS resolution works** from containers (`nslookup kafka` succeeds)

### ❌ DNS Still Broken If:

1. Services stuck at **0/1 replicas** or constantly restarting
2. Logs full of **`ENOTFOUND kafka`**, `ENOTFOUND zookeeper`, `ENOTFOUND mongodb`
3. **`nslookup kafka`** fails from containers
4. Processor can't connect to Kafka/MongoDB
5. Sensors can't find Kafka
6. No data flowing through pipeline

---

## Diagnostic Commands

### Check Worker-to-Worker Connectivity

```bash
# Get manager IP
cd terraform/
MANAGER_IP=$(terraform output -raw manager_public_ip)
cd ..

# SSH to a worker node (via manager)
ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP}
ssh ubuntu@10.0.2.200  # Worker1

# Test UDP connectivity to other workers
nc -uzv 10.0.2.37 4789   # VXLAN overlay to worker2
nc -uzv 10.0.2.37 7946   # Gossip to worker2
nc -uzv 10.0.2.150 4789  # VXLAN overlay to worker3

# Expected:
# ✅ SUCCESS: "succeeded"
# ❌ FAILURE: "timed out"
```

### Check Overlay Network

```bash
# From manager
docker network inspect plant-monitoring_plant-network

# Check:
# - All nodes listed in "Peers"
# - Containers have IPs assigned
# - Encryption enabled: true
```

### Check Security Groups (AWS)

```bash
# From local machine
cd terraform/

# Verify self-referencing rules were applied
terraform show | grep -A5 "self = true"

# Should show 3 rules:
# - ingress port 7946 tcp self=true
# - ingress port 7946 udp self=true  
# - ingress port 4789 udp self=true
```

---

## If DNS Still Fails: Alternative Tests

### Test 1: Try Without Encryption

```yaml
# In docker-compose.yml
networks:
  plant-network:
    driver: overlay
    # Comment out encryption
    # driver_opts:
    #   encrypted: "true"
```

Redeploy and test if DNS works without encryption.

### Test 2: Use VIP Instead of DNSRR

```yaml
# Remove endpoint_mode: dnsrr from Kafka
kafka:
  deploy:
    replicas: 1
    # endpoint_mode: dnsrr  # Try default VIP mode
```

### Test 3: Force Services to Same Node (Verify It's Network, Not Services)

```yaml
# Add to ALL services temporarily
deploy:
  placement:
    constraints:
      - node.role == manager
```

If services work when all on manager but fail when distributed, confirms it's a cross-node networking issue.

### Test 4: Check MTU

```bash
# From manager and workers
ip link show eth0 | grep mtu
# Should show: mtu 9001

# Check overlay network MTU
docker network inspect plant-monitoring_plant-network | grep -i mtu
# Should account for VXLAN overhead (50 bytes)
```

---

## Expected Timeline

| Phase | Time | What Happens |
|-------|------|--------------|
| **Deploy** | 5-10 min | Terraform apply + stack deploy |
| **Initial Check** | 2 min | See where services landed |
| **Logs Review** | 5 min | Check for DNS errors |
| **DNS Test** | 3 min | nslookup from containers |
| **Data Flow** | 5 min | Verify end-to-end pipeline |
| **Total** | ~20-25 min | Complete test cycle |

---

## Documentation of Results

After testing, document in a new file: `CROSS_NODE_TEST_RESULTS.md`

Include:
1. **Service Placement**: Where each service ran (which nodes)
2. **DNS Resolution**: Did `nslookup kafka` work from workers?
3. **Logs**: Key excerpts showing success or failure
4. **Data Flow**: Did data reach MongoDB?
5. **Conclusion**: Did security group fix resolve the issue?

---

## Rollback Plan

If testing shows DNS still broken:

```bash
# Option A: Revert to manager-only placement
# Edit docker-compose.yml, add back manager constraints
# Redeploy

# Option B: Accept limitation and document
# Keep manager-only deployment
# Document as "Known Limitation: Cross-node DNS issues"
# Demonstrate scaling on single node (still shows scaling capability)

# Option C: Try alternative solutions
# Disable encryption
# Use static IPs
# Use host networking for critical services
```

---

## Summary

**What changed**:
- ❌ Removed all manager-only placement constraints
- ✅ Services will now distribute naturally across nodes
- ✅ Sensors (2 replicas) will likely split across workers
- ✅ This enables real cross-node communication testing

**Why this works for testing**:
- Forces services to communicate across overlay network
- Tests if self-referencing security group rules work
- Tests if Docker's built-in DNS works without Consul
- Provides actual cross-node scenarios to diagnose

**Next step**: 
```bash
./teardown.sh && cd terraform && terraform apply && cd .. && ./deploy.sh
```

Then follow the testing procedure above! 🚀
