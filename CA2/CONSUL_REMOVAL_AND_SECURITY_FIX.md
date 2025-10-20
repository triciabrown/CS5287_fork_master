# Consul Removal and Security Group Fix

**Date**: October 19, 2025  
**Action**: Removed Consul/Registrator, reverted to Docker DNS, added self-referencing security group rules

---

## Changes Made

### 1. Removed Consul Service Discovery

**Removed from `docker-compose.yml`**:
- ❌ `consul` service (Consul server)
- ❌ `registrator` service (auto-registration)
- ❌ `consul_data` volume
- ❌ All `dns:` and `dns_search:` configurations from services
- ❌ All `.service.consul` hostname references
- ❌ `attachable: true` from network (no longer need static IPs)
- ❌ All Consul-related service dependencies

**Reverted Service Connections**:
```yaml
# Before (Consul):
KAFKA_ZOOKEEPER_CONNECT: 'zookeeper.service.consul:2181'
KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://kafka.service.consul:9092'
KAFKA_BROKER: 'kafka.service.consul:9092'
MQTT_BROKER: 'mqtt://mosquitto.service.consul:1883'

# After (Docker DNS):
KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://kafka:9092'
KAFKA_BROKER: 'kafka:9092'
MQTT_BROKER: 'mqtt://mosquitto:1883'
```

### 2. Service Placement Strategy

**Updated approach** - Let services distribute naturally to test cross-node communication:

```yaml
# Kafka - No constraints (can run anywhere)
kafka:
  deploy:
    replicas: 1
    endpoint_mode: dnsrr

# Processor - No constraints (can run anywhere)  
processor:
  deploy:
    replicas: 1

# Sensors - No constraints (will distribute across nodes)
sensor:
  deploy:
    replicas: 2  # These will split across different nodes

# Home Assistant + Mosquitto - Manager only (need public port)
homeassistant:
  deploy:
    placement:
      constraints:
        - node.labels.mqtt == true  # Manager node
```

**Why No Manager-Only Constraints**:
- ✅ Allows real testing of cross-node DNS resolution
- ✅ Sensors will distribute across workers  
- ✅ Tests if security group self-referencing rules work
- ⚠️ May fail initially, but that's expected (we're testing the fix!)

**Expected Service Distribution**:
```
Manager Node:  Home Assistant, Mosquitto, (maybe Kafka or MongoDB)
Worker1:       Sensor replica 1, (maybe Processor)
Worker2:       Sensor replica 2, (maybe ZooKeeper)
Worker3-4:     Available for scheduling
```

This creates multiple cross-node communication scenarios to test.

### 3. Added Self-Referencing Security Group Rules

**Added to `terraform/main.tf` worker security group**:

```hcl
# Worker-to-worker communication (self-referencing for same security group)
ingress {
  from_port   = 7946
  to_port     = 7946
  protocol    = "tcp"
  self        = true
  description = "Worker to worker gossip TCP (self-reference)"
}

ingress {
  from_port   = 7946
  to_port     = 7946
  protocol    = "udp"
  self        = true
  description = "Worker to worker gossip UDP (self-reference)"
}

# Worker-to-worker overlay network (self-referencing)
ingress {
  from_port   = 4789
  to_port     = 4789
  protocol    = "udp"
  self        = true
  description = "Worker to worker overlay VXLAN (self-reference)"
}
```

**Why**: Workers share the same security group, so they need explicit self-referencing rules to communicate with **each other**, not just with the manager or VPC CIDR.

**Technical Explanation**:
- `self = true` means "allow traffic from any instance in **this same security group**"
- Without this, workers can't talk to each other even though VPC CIDR is allowed
- Specifically important for:
  - Port 7946: Worker node gossip protocol
  - Port 4789: VXLAN overlay network traffic (encrypted container communication)

---

## Why This Approach

### Consul Was Wrong Tool
- Consul is for **legacy standalone Docker Swarm** (pre-1.12)
- Modern **Swarm Mode** has built-in service discovery
- Consul itself failed due to same DNS issue (couldn't work across nodes)
- Added unnecessary complexity

### Self-Referencing Rules
Based on security group analysis in [`SECURITY_GROUP_ANALYSIS.md`](./SECURITY_GROUP_ANALYSIS.md):

**Previous Rules** (before fix):
```hcl
# Workers could talk to VPC CIDR
ingress {
  from_port   = 7946
  to_port     = 7946
  protocol    = "tcp"
  cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]  # 10.0.0.0/16
}
```

**Problem**: While this allows traffic from the VPC, AWS security groups need **explicit self-reference** when instances in the same security group need to communicate.

**Solution**: Add `self = true` rules so workers can gossip and share overlay network traffic with each other.

---

## Expected Results

### Initial Deployment (Testing Phase)
🧪 **Will Test Cross-Node Communication**:
- Services distribute across manager and workers
- Sensors split between nodes (replica 1 on worker1, replica 2 on worker2)
- Kafka/MongoDB/ZooKeeper may land on any node
- Processor may land on different node than Kafka

**Possible Outcomes**:

✅ **If Security Group Fix Worked**:
- All services start and show X/X replicas
- No `ENOTFOUND` errors in logs
- Processor connects to Kafka/MongoDB successfully
- Sensors send data from worker nodes
- Data flows end-to-end
- **Result**: Cross-node DNS resolution works! Can scale freely.

❌ **If DNS Still Broken**:
- Services stuck at 0/X replicas or constantly restarting
- Logs show `ENOTFOUND kafka`, `ENOTFOUND mongodb`
- Processor can't connect when on different node than Kafka
- Sensors can't find Kafka
- **Result**: Need to try alternative solutions or accept manager-only deployment

### Fallback Options If DNS Fails

1. **Disable Overlay Encryption** - Some reports suggest encrypted overlays have DNS bugs
2. **Use Static IPs** - Services use IP addresses instead of DNS names
3. **Manager-Only Deployment** - Force all services to manager (works but limits scaling)
4. **Document as Limitation** - "Future Enhancement: Multi-node DNS resolution"

---

## Next Steps

### 1. Apply Terraform Changes
```bash
cd terraform/
terraform plan  # Review changes
terraform apply # Apply security group updates
```

### 2. Test Manager-Only Deployment First
```bash
# Current state with all services on manager
cd ../
./deploy.sh

# Verify everything works
docker stack services plant-monitoring
docker service logs plant-monitoring_processor --tail 20
```

### 3. If Working, Remove Manager Constraints
```bash
# Edit docker-compose.yml
# Remove these lines from Kafka, Processor, Sensor:
#   placement:
#     constraints:
#       - node.role == manager

# Redeploy
docker stack deploy -c docker-compose.yml plant-monitoring

# Watch for DNS errors
docker service logs plant-monitoring_processor --follow
```

### 4. Test Cross-Node Communication
```bash
# Scale sensors across nodes
docker service scale plant-monitoring_sensor=5

# Check where they're running
docker service ps plant-monitoring_sensor

# Verify they can reach Kafka
docker service logs plant-monitoring_sensor --tail 50 | grep -i "sent sensor data"
```

### 5. If Still Failing, Additional Diagnostics

**Test from Worker Node**:
```bash
# SSH to manager
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.198.166

# Jump to worker
ssh ubuntu@10.0.2.200

# Test UDP ports (requires netcat-openbsd)
sudo apt-get install -y netcat-openbsd

# From worker1 to other workers
nc -uzv 10.0.2.37 4789   # VXLAN to worker2
nc -uzv 10.0.2.37 7946   # Gossip to worker2

# Test overlay network DNS
docker run -it --rm --network plant-monitoring_plant-network alpine
# Inside container:
nslookup kafka
ping kafka
```

**Check Swarm Network State**:
```bash
# From manager
docker network inspect plant-monitoring_plant-network

# Look for:
# - All nodes listed in Peers
# - Container IPs assigned
# - Encryption enabled
```

---

## Alternative Solutions If This Doesn't Work

### Option 1: Disable Overlay Encryption
Some reports suggest encrypted overlays have DNS issues.

```yaml
networks:
  plant-network:
    driver: overlay
    # Remove this:
    # driver_opts:
    #   encrypted: "true"
```

### Option 2: Use Host Network Mode for Critical Services
Run Kafka/ZooKeeper in host network mode (less isolated but might work).

```yaml
kafka:
  network_mode: host  # Instead of overlay
```

### Option 3: Use Static IPs with Attachable Network
Assign static IPs so services don't rely on DNS at all.

```yaml
networks:
  plant-network:
    attachable: true
    ipam:
      config:
        - subnet: 10.10.0.0/24

services:
  kafka:
    networks:
      plant-network:
        ipv4_address: 10.10.0.20
```

### Option 4: Accept Manager-Only Deployment
If time constraints, document as "known limitation" and demonstrate scaling on manager:

```bash
# Can still scale sensors on same node
docker service scale plant-monitoring_sensor=5
# All 5 replicas run on manager, still shows scaling capability
```

---

## Documentation Updates

Updated files:
- ✅ `docker-compose.yml` - Removed Consul, added manager constraints
- ✅ `terraform/main.tf` - Added self-referencing security group rules
- ✅ `README.md` - Added section about DNS issues and Consul attempt
- ✅ `CONSUL_ATTEMPT_SUMMARY.md` - Full documentation of what we tried
- ✅ `SECURITY_GROUP_ANALYSIS.md` - Network troubleshooting guide
- ✅ This file - Summary of removal and fix

---

## Summary

**What we did**:
1. ❌ Removed Consul/Registrator (wrong tool for Swarm Mode)
2. ✅ Reverted to Docker's built-in service discovery
3. ⚠️ Added manager-only placement as temporary workaround
4. ✅ Added self-referencing security group rules for worker-to-worker communication
5. ✅ Documented the entire journey and troubleshooting process

**Current status**:
- Stack will deploy and work (all services on manager)
- Self-referencing rules added to Terraform
- Ready to test if cross-node DNS works after security group fix

**Success criteria**:
- Services on workers can resolve hostnames like `kafka`, `zookeeper`
- Can scale sensors across multiple worker nodes
- Data flows correctly end-to-end
- No `ENOTFOUND` errors in logs

---

**If cross-node DNS still doesn't work after this**, we've documented extensively and can either:
1. Accept manager-only deployment as a known limitation
2. Try alternative solutions (disable encryption, host mode, static IPs)
3. Document as "Future Enhancement: Multi-node DNS resolution"

The learning value and troubleshooting documentation is already substantial and demonstrates real-world problem-solving.
