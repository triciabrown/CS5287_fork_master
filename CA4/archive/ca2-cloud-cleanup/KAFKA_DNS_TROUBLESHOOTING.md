# Kafka DNS Resolution Issue - Complete Troubleshooting Guide

**Date**: October 18, 2025  
**Issue**: Services cannot connect to Kafka due to DNS resolution failure  
**Severity**: CRITICAL - Blocks entire pipeline (sensor → processor communication)

**⚠️ UPDATE**: This was a secondary issue. The PRIMARY issue was **overlay network IP conflict**. See `OVERLAY_NETWORK_IP_CONFLICT.md` for the root cause.

---

## Problem Summary

### Symptoms

All services trying to connect to Kafka fail with these errors:

**Processor logs**:
```
Connection error: getaddrinfo ENOTFOUND kafka
KafkaJSConnectionError: Connection error: getaddrinfo ENOTFOUND kafka
Failed to connect to seed broker, trying another broker from the list
```

**Sensor logs**:
```
KafkaJSConnectionError: Connection timeout
broker: 'kafka:9092'
```

**Service status**:
```bash
$ docker service ls
NAME                          REPLICAS
plant-monitoring_processor    0/1      # Crashing
plant-monitoring_sensor       2/2      # Running but can't send data
plant-monitoring_kafka        1/1      # Running fine
```

### Root Cause

**Docker Swarm VIP (Virtual IP) endpoint mode causes DNS resolution failures** on overlay networks.

When Kafka is deployed with the default VIP endpoint mode:
- Docker creates a virtual IP for the service
- DNS should resolve `kafka` → VIP → actual container IP
- **BUT**: DNS resolution fails, especially in multi-node clusters
- The alternative `tasks.kafka` DOES resolve correctly

This is a **known Docker Swarm limitation** with stateful services on overlay networks.

---

## Diagnosis Steps

### 1. Verify the Problem

Test DNS resolution from a running container:

```bash
# This FAILS with VIP mode
docker exec $(docker ps -q -f name=sensor) nslookup kafka
```

**Output showing the problem**:
```
Server:         127.0.0.11
Address:        127.0.0.11:53

** server can't find kafka.us-east-2.compute.internal: NXDOMAIN
** server can't find kafka.us-east-2.compute.internal: NXDOMAIN
```

**BUT this works**:
```bash
docker exec $(docker ps -q -f name=sensor) nslookup tasks.kafka
```

**Output showing it resolves**:
```
Server:         127.0.0.11
Address:        127.0.0.11:53

Non-authoritative answer:
Name:   tasks.kafka
Address: 10.0.1.3
```

### 2. Check Kafka Endpoint Mode

```bash
docker service inspect plant-monitoring_kafka --format '{{.Endpoint.Spec.Mode}}'
```

**If output is `vip`** → That's the problem!  
**Should be `dnsrr`** → DNS Round Robin mode

### 3. Confirm Kafka is Running

```bash
# Kafka should be running fine
docker service ps plant-monitoring_kafka
```

**Expected**: `Running X minutes ago`

The issue isn't Kafka itself - it's how other services discover it.

### 4. Check Service Logs

```bash
# Processor logs show DNS failures
docker service logs plant-monitoring_processor --tail 50 | grep -i error

# Sensor logs show connection timeouts
docker service logs plant-monitoring_sensor --tail 50 | grep -i kafka
```

---

## Solution: Use DNS Round Robin Endpoint Mode

### Step 1: Update docker-compose.yml

Edit `docker-compose.yml` and add `endpoint_mode: dnsrr` to the Kafka service:

```yaml
  kafka:
    image: confluentinc/cp-kafka:7.4.0
    hostname: kafka
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://kafka:9092'
      # ... other config
    networks:
      - plant-network
    depends_on:
      - zookeeper
    deploy:
      replicas: 1
      endpoint_mode: dnsrr  # ← ADD THIS LINE
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 400M
```

### Step 2: Redeploy the Stack

```bash
# If local deployment
docker stack deploy -c docker-compose.yml plant-monitoring

# If AWS deployment
cd plant-monitor-swarm-IaC/
./deploy.sh  # Will automatically use updated compose file
```

### Step 3: Verify the Fix

**Check endpoint mode changed**:
```bash
docker service inspect plant-monitoring_kafka --format '{{.Endpoint.Spec.Mode}}'
# Expected: dnsrr
```

**Test DNS resolution now works**:
```bash
docker exec $(docker ps -q -f name=sensor) nslookup kafka
# Expected: Returns IP address (no NXDOMAIN error)
```

**Check processor logs show connection**:
```bash
docker service logs plant-monitoring_processor --tail 20
# Expected: No "ENOTFOUND" errors
# Should see: "Connected to Kafka" or similar
```

**Check sensor logs show data sending**:
```bash
docker service logs plant-monitoring_sensor --tail 20
# Expected: "Sent sensor data for plant-001: { moisture: '42.1', ... }"
```

**Verify service is running**:
```bash
docker service ls | grep processor
# Expected: plant-monitoring_processor  1/1
```

---

## Alternative Solutions

### Option 2: Use tasks.kafka in Application Code

If you can't change the endpoint mode, modify application code to use `tasks.kafka`:

**In `applications/processor/app.js`**:
```javascript
const kafka = new Kafka({
  clientId: 'plant-care-processor',
  brokers: ['tasks.kafka:9092'],  // Changed from 'kafka:9092'
})
```

**In `applications/sensor/sensor.js`**:
```javascript
const kafka = new Kafka({
  clientId: `plant-sensor-${SENSOR_ID}`,
  brokers: ['tasks.kafka:9092'],  // Changed from 'kafka:9092'
})
```

Then rebuild images and redeploy.

### Option 3: Force Service Update (Temporary)

Sometimes DNS caching causes issues. Force update to clear:

```bash
# Update Kafka
docker service update --force plant-monitoring_kafka

# Wait for DNS propagation
sleep 30

# Update dependent services
docker service update --force plant-monitoring_processor
docker service update --force plant-monitoring_sensor
```

This is a **temporary fix** - the issue may return after redeployment.

---

## Why This Happens

### VIP (Virtual IP) Mode - Default Behavior

```
Client Container
    ↓
    nslookup kafka
    ↓
Docker DNS (127.0.0.11)
    ↓ [SHOULD return VIP]
    ↓ [BUT SOMETIMES FAILS]
    ↓
NXDOMAIN error
```

**Problems with VIP**:
- DNS entries not always registered correctly
- Common in overlay networks with encrypted traffic
- Worse in multi-node clusters
- Particularly affects stateful services

### DNSRR (DNS Round Robin) Mode - Recommended

```
Client Container
    ↓
    nslookup kafka
    ↓
Docker DNS (127.0.0.11)
    ↓
Returns actual container IP(s)
    ↓
Direct connection to Kafka
```

**Benefits of DNSRR**:
- Direct DNS resolution to task IPs
- More reliable for stateful services
- Works consistently across nodes
- Standard DNS behavior

---

## Best Practices

### When to Use Each Mode

**Use `endpoint_mode: dnsrr` for**:
- ✅ Stateful services (Kafka, MongoDB, ZooKeeper, Redis)
- ✅ Services with persistent connections
- ✅ Services that don't scale horizontally
- ✅ When you need reliable DNS resolution

**Use VIP mode (default) for**:
- ✅ Stateless services (API servers, web apps)
- ✅ Services that scale horizontally (sensors, workers)
- ✅ When you need load balancing across replicas
- ✅ When you need a stable virtual IP

### Our Configuration

```yaml
services:
  # VIP mode (default) - scalable stateless services
  sensor:
    deploy:
      replicas: 2-5  # Can scale
      # No endpoint_mode = VIP (default)
  
  processor:
    deploy:
      replicas: 1
      # No endpoint_mode = VIP (default)
  
  # DNSRR mode - stateful services
  kafka:
    deploy:
      replicas: 1
      endpoint_mode: dnsrr  # Stateful, needs reliable DNS
  
  mongodb:
    deploy:
      replicas: 1
      # Consider adding: endpoint_mode: dnsrr
  
  zookeeper:
    deploy:
      replicas: 1
      # Consider adding: endpoint_mode: dnsrr
```

---

## Prevention

### 1. Always Test DNS After Deployment

Add to your deployment validation:

```bash
#!/bin/bash
# test-dns-resolution.sh

echo "Testing Kafka DNS resolution..."
docker exec $(docker ps -q -f name=sensor | head -1) nslookup kafka

if [ $? -eq 0 ]; then
    echo "✓ Kafka DNS resolution works"
else
    echo "✗ Kafka DNS resolution failed - check endpoint_mode"
    exit 1
fi
```

### 2. Monitor Service Logs

Check for connection errors during deployment:

```bash
# Watch for DNS/connection errors
docker service logs plant-monitoring_processor --follow | grep -i "error\|enotfound\|timeout"
```

### 3. Use Health Checks

Add to services in docker-compose.yml:

```yaml
  processor:
    healthcheck:
      test: ["CMD-SHELL", "node -e 'require(\"net\").createConnection(9092, \"kafka\").on(\"error\", () => process.exit(1))'"]
      interval: 30s
      timeout: 10s
      retries: 3
```

---

## Related Issues

### MongoDB Connection Issues

If you see similar errors with MongoDB:
```
MongoNetworkError: getaddrinfo ENOTFOUND mongodb
```

**Same solution**: Add `endpoint_mode: dnsrr` to MongoDB service.

### ZooKeeper Connection Issues

If Kafka can't connect to ZooKeeper:
```
org.apache.zookeeper.KeeperException$ConnectionLossException
```

**Same solution**: Add `endpoint_mode: dnsrr` to ZooKeeper service.

---

## The Real Issue: Overlay Network IP Conflict

### How We Discovered the Root Cause

During troubleshooting, we observed a strange pattern:
- **Services on manager node**: ✅ Connected to Kafka successfully
- **Services on worker nodes**: ❌ Connection timeout (even after DNS fix)

### The Investigation Trail

1. **First suspicion**: DNS resolution (VIP vs DNSRR)
   - Added `endpoint_mode: dnsrr` to Kafka
   - DNS started resolving correctly
   - **But connections still timed out on workers!**

2. **Second suspicion**: Service endpoint mode
   - Tried both VIP and DNSRR modes
   - Verified DNS resolution worked with both
   - **Still timeouts from worker nodes**

3. **Key discovery**: Location-dependent behavior
   ```bash
   # Manager node (10.0.1.52)
   sensor.1@manager → kafka ✅ WORKS
   
   # Worker nodes (10.0.2.x)
   sensor.2@worker-1 → kafka ❌ TIMEOUT
   sensor.3@worker-2 → kafka ❌ TIMEOUT
   ```

4. **Root cause found**: IP range conflict
   ```bash
   # Check overlay network
   $ docker network inspect plant-monitoring_plant-network
   IPAM.Config: [{10.0.1.0/24  10.0.1.1 map[]}]
   
   # Check AWS subnets
   AWS Public Subnet (Manager):  10.0.1.0/24  ← SAME RANGE!
   AWS Private Subnet (Workers): 10.0.2.0/24
   ```

### Why This Caused Timeouts (Not DNS Errors)

**DNS resolved correctly**, but routing failed:

```
Worker container trying to reach Kafka VIP (10.0.1.68):

1. DNS query for "kafka"
   ✅ Returns: 10.0.1.68 (overlay VIP)

2. Container routing decision:
   - Destination: 10.0.1.68
   - Routing table sees two paths:
     * 10.0.1.0/24 → overlay network (VXLAN tunnel)
     * 10.0.1.0/24 → AWS network (eth0)
   - ❌ AMBIGUOUS! Which path to use?

3. Result:
   - Packets sent to wrong interface
   - Never reach Kafka container
   - Connection timeout (not DNS error!)
```

### The Complete Fix

**Both issues needed to be fixed**:

1. **Overlay network IP conflict** (PRIMARY):
   ```yaml
   networks:
     plant-network:
       ipam:
         config:
           - subnet: 10.10.0.0/24  # Different from AWS 10.0.x.x
   ```

2. **DNS resolution** (SECONDARY - may not be needed with fix #1):
   ```yaml
   kafka:
     deploy:
       endpoint_mode: dnsrr  # Better DNS for stateful services
   ```

**After fixing the overlay network subnet, VIP mode works fine!** The DNS issue was less critical than we thought - it was the routing conflict causing most problems.

---

## Lessons Learned

### 1. Connection Timeouts ≠ DNS Failures

**We assumed**: "Can't connect" means DNS isn't resolving  
**Reality**: DNS resolved fine, but packets couldn't route correctly

### 2. Working Services Can Mislead

**We thought**: "Works on manager, fails on workers" = worker-specific issue  
**Reality**: Manager node had no routing ambiguity (same subnet), hiding the real problem

### 3. Layer the Debugging

```
Application Layer:  Can service connect? ❌ NO
  ↓
Transport Layer:    Are ports open? ✅ YES
  ↓
Network Layer:      Can packets route? ❌ NO (routing conflict)
  ↓
DNS Layer:          Does name resolve? ✅ YES
  ↓
ROOT CAUSE:         IP address overlap between overlay and AWS networks
```

### 4. Always Specify Overlay Subnets in Production

**DON'T** let Docker auto-assign overlay network IPs:
```yaml
networks:
  mynetwork:
    driver: overlay  # ❌ Auto-assigned - might conflict!
```

**DO** explicitly configure non-conflicting ranges:
```yaml
networks:
  mynetwork:
    driver: overlay
    ipam:
      config:
        - subnet: 10.10.0.0/24  # ✅ Explicit, documented
```

---

## References

- [Docker Swarm Networking Docs](https://docs.docker.com/engine/swarm/networking/)
- [Docker Service Endpoint Mode](https://docs.docker.com/engine/swarm/services/#configure-service-discovery)
- [Known Issue: VIP DNS Resolution](https://github.com/moby/moby/issues/32299)
- [Overlay Network DNS Issues](https://github.com/moby/moby/issues/23910)
- **[Full Overlay Network IP Conflict Analysis](OVERLAY_NETWORK_IP_CONFLICT.md)** ← **READ THIS FIRST**

---

## Summary

**Original Assumption**: VIP endpoint mode causes DNS resolution failures  
**Actual Root Cause**: Overlay network IP range conflicted with AWS subnet  
**Secondary Issue**: VIP mode can have DNS quirks with stateful services  
**Complete Solution**: Fix overlay subnet + optionally use DNSRR mode  

**The critical fix**:
```yaml
networks:
  plant-network:
    driver: overlay
    ipam:
      config:
        - subnet: 10.10.0.0/24  # ← This solves the routing issue!
```

After applying the overlay network fix, services communicate reliably regardless of endpoint mode.
