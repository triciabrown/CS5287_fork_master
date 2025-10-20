# Docker Swarm DNS Fix - Comprehensive Plan

**Date**: October 19, 2025  
**Problem**: Docker Swarm overlay network DNS resolution fails on worker nodes  
**Symptom**: Services on workers cannot resolve "kafka", "mongodb", etc. - get ENOTFOUND or Connection timeout  
**Root Cause**: Docker Swarm overlay network DNS bug combined with AWS EC2 network offloading issues

---

## Problem Summary

After 8+ hours of troubleshooting:
- ✅ Fixed Ansible playbook to use `--advertise-addr` on worker join
- ✅ Workers properly rejoin with advertise address
- ✅ All Swarm ports open (2377, 7946, 4789)
- ✅ Overlay network created correctly (10.10.0.0/24)
- ❌ **DNS STILL FAILS** - services on workers cannot resolve service hostnames

**Current Status**:
- Kafka: Running on manager (ip-10-0-1-45)
- Processor: 0/1 (fails on workers with "Connection timeout kafka:9092")
- Sensors: 1/2 (only one running, constant failures)
- All failures: Cannot resolve "kafka" hostname

---

## Solutions to Try (Priority Order)

### ⭐ Solution 1: Use Kafka VIP IP Directly (RECOMMENDED)
**Why**: Completely bypass DNS by using Kafka's Virtual IP address directly in connection strings  
**Pros**: Most reliable, no DNS dependency  
**Cons**: Need to update on stack redeploy if VIP changes

#### Steps:
1. **Remove `endpoint_mode: dnsrr` from Kafka** (already done in docker-compose.yml)
2. **Deploy stack and get Kafka VIP**:
   ```bash
   ssh manager 'docker service inspect plant-monitoring_kafka --format "{{json .Endpoint.VirtualIPs}}"'
   # Look for plant-monitoring_plant-network VIP (e.g., 10.10.0.15)
   ```

3. **Update docker-compose.yml to use VIP**:
   ```yaml
   # In sensor service:
   environment:
     KAFKA_BROKER: '10.10.0.15:9092'  # Use actual VIP
   
   # In processor service:
   environment:
     KAFKA_BROKER: '10.10.0.15:9092'  # Use actual VIP
   
   # In homeassistant service:
   environment:
     KAFKA_BROKERS: '10.10.0.15:9092'  # Use actual VIP
   ```

4. **Also update MongoDB and Mosquitto references** (if any services use them)

5. **Redeploy stack**:
   ```bash
   cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC
   ./deploy.sh
   ```

6. **Test**:
   ```bash
   ./scaling-test.sh
   # Should show proper message throughput scaling
   ```

---

### Solution 2: Use Static Overlay Network IPs
**Why**: Assign fixed IPs to services on overlay network  
**Pros**: Predictable IPs, can hardcode in configs  
**Cons**: More complex setup, IPs must be managed

#### Steps:
1. **Update docker-compose.yml overlay network**:
   ```yaml
   networks:
     plant-network:
       driver: overlay
       driver_opts:
         encrypted: "true"
       ipam:
         config:
           - subnet: 10.10.0.0/24
             ip_range: 10.10.0.192/26  # Reserve 10.10.0.1-191 for static IPs
   ```

2. **Assign static IPs to services**:
   ```yaml
   kafka:
     # ... existing config ...
     networks:
       plant-network:
         ipv4_address: 10.10.0.10  # Fixed IP for Kafka
   
   mongodb:
     # ... existing config ...
     networks:
       plant-network:
         ipv4_address: 10.10.0.11  # Fixed IP for MongoDB
   
   mosquitto:
     # ... existing config ...
     networks:
       plant-network:
         ipv4_address: 10.10.0.12  # Fixed IP for Mosquitto
   ```

3. **Update service connection strings**:
   ```yaml
   sensor:
     environment:
       KAFKA_BROKER: '10.10.0.10:9092'
   
   processor:
     environment:
       KAFKA_BROKER: '10.10.0.10:9092'
       MONGODB_URI: 'mongodb://10.10.0.11:27017/plant_monitoring'
   ```

4. **Redeploy and test**

---

### Solution 3: Use External DNS Service
**Why**: Replace Docker's embedded DNS with CoreDNS or Consul  
**Pros**: More reliable DNS, production-grade  
**Cons**: Complex setup, additional service to manage

#### Steps (if Solutions 1 & 2 fail):
1. **Deploy CoreDNS as a Swarm service**
2. **Configure Docker to use CoreDNS** (modify daemon.json on all nodes)
3. **Update service discovery to use CoreDNS**
4. **Redeploy application stack**

**Skip this unless absolutely necessary** - too complex for assignment timeline.

---

### Solution 4: Force All Services to Manager Node (FALLBACK)
**Why**: If cross-node networking cannot be fixed, demonstrate on single node  
**Pros**: Guaranteed to work  
**Cons**: Defeats purpose of multi-node scalability demo

#### Steps (ONLY IF ALL ELSE FAILS):
1. **Update docker-compose.yml with manager constraint for ALL services**:
   ```yaml
   # Add to ALL services:
   deploy:
     placement:
       constraints:
         - node.role == manager
   ```

2. **Update README to document limitation**:
   ```markdown
   ## Known Limitation
   Due to Docker Swarm overlay network DNS issues in AWS EC2 environment,
   all services currently run on manager node. This is a known issue with
   Docker Swarm + AWS networking. In production, consider:
   - Using Kubernetes instead
   - External service mesh (Consul, Linkerd)
   - Static IP assignments
   ```

3. **Focus on other assignment aspects**:
   - IaC automation ✅
   - Security implementation ✅
   - Monitoring/logging ✅
   - One-command deployment ✅

---

## Additional Fixes to Apply

### Network Offload Fix (CRITICAL)
Even with IP-based solution, apply this fix for UDP packet reliability:

**Update**: `/home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC/ansible/setup-swarm.yml`

Already added but verify it's working:
```yaml
- name: Disable TX offloading features (fix for Docker Swarm overlay UDP packet drops)
  command: ethtool -K {{ network_interface.stdout }} tso off gso off sg off
```

**Verify after deployment**:
```bash
ssh manager 'sudo ethtool -k eth0 | grep -E "(scatter-gather|tcp-segmentation|generic-segmentation)"'
# Should show "off" for these features
```

---

## Testing Plan

### Test 1: Basic Connectivity
```bash
ssh manager 'docker service ps plant-monitoring_processor plant-monitoring_sensor'
# Check: Services running on workers? Any failures?

ssh manager 'docker service logs plant-monitoring_processor --tail 20'
# Check: Any "ENOTFOUND" or "Connection timeout" errors?
```

### Test 2: Message Flow
```bash
ssh manager 'docker exec $(docker ps -q --filter "name=kafka") kafka-console-consumer --bootstrap-server localhost:9092 --topic sensor-data --from-beginning --max-messages 10'
# Should see sensor messages if system is working
```

### Test 3: Scaling Test
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC
./scaling-test.sh
# Expected results:
# 1 replica: ~2 messages/30s
# 2 replicas: ~4 messages/30s
# 5 replicas: ~10 messages/30s
```

---

## Deployment Checklist

### Before Starting
- [ ] Teardown existing infrastructure: `./teardown.sh`
- [ ] Review docker-compose.yml changes
- [ ] Ensure Ansible playbook has network offload fix
- [ ] Ensure Ansible playbook has --advertise-addr fix

### Deployment
- [ ] Run: `./deploy.sh` (or `./deploy.sh 2>&1 | tee deploy.log`)
- [ ] Wait for all services: `docker service ls` (all should show X/X replicas)
- [ ] Check for service failures: `docker service ps <service> | grep Failed`

### Verification
- [ ] Get Kafka VIP: `docker service inspect plant-monitoring_kafka --format "{{json .Endpoint.VirtualIPs}}"`
- [ ] Update connection strings if using Solution 1
- [ ] Check processor logs: `docker service logs plant-monitoring_processor --tail 20`
- [ ] Check sensor logs: `docker service logs plant-monitoring_sensor --tail 20`
- [ ] Run scaling test: `./scaling-test.sh`

### If Still Failing
- [ ] Check network offload: `sudo ethtool -k eth0`
- [ ] Check Swarm nodes: `docker node ls` (all Ready?)
- [ ] Check overlay network: `docker network inspect plant-monitoring_plant-network`
- [ ] Check service distribution: `docker service ps --filter "desired-state=running" <service>`
- [ ] Fall back to Solution 4 (all on manager)

---

## Files to Modify

### 1. docker-compose.yml
**Location**: `/home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC/docker-compose.yml`

**Changes needed** (Solution 1):
```yaml
# Line ~199 (sensor service)
environment:
  KAFKA_BROKER: '10.10.0.X:9092'  # Replace X with actual Kafka VIP

# Line ~235 (processor service)
environment:
  KAFKA_BROKER: '10.10.0.X:9092'  # Replace X with actual Kafka VIP

# Line ~270 (homeassistant service - if needed)
environment:
  KAFKA_BROKERS: '10.10.0.X:9092'  # Replace X with actual Kafka VIP
```

**IMPORTANT**: Get the actual VIP from deployed Kafka service first!

### 2. ansible/setup-swarm.yml
**Location**: `/home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC/ansible/setup-swarm.yml`

**Verify these fixes are present**:
- [ ] Manager section has network offload fix (lines ~23-30)
- [ ] Worker section has network offload fix (lines ~100-107)
- [ ] Worker join uses `--advertise-addr` (line ~120)

### 3. README.md (if using fallback)
**Location**: `/home/tricia/dev/CS5287_fork_master/CA2/README.md`

**Add Known Limitations section** if using Solution 4.

---

## Quick Reference Commands

```bash
# Get current manager IP
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC/terraform
terraform output -raw manager_public_ip

# SSH to manager
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP>

# Check all services
docker service ls

# Check service logs
docker service logs plant-monitoring_<service> --tail 50

# Get Kafka VIP
docker service inspect plant-monitoring_kafka --format "{{json .Endpoint.VirtualIPs}}" | python3 -m json.tool

# Check network on container
docker exec <container-id> nslookup kafka
docker exec <container-id> ping -c 2 10.10.0.X

# Check network offload
sudo ethtool -k eth0 | grep -E "(scatter|segment)"

# Restart a service
docker service update --force plant-monitoring_<service>

# Scale a service
docker service scale plant-monitoring_sensor=5
```

---

## Expected Timeline

- **Solution 1** (VIP direct): 30-45 minutes
- **Solution 2** (Static IPs): 1-2 hours  
- **Solution 3** (External DNS): 3-4 hours (skip unless necessary)
- **Solution 4** (Fallback): 15 minutes

---

## Success Criteria

✅ **Minimum** (for assignment):
- All services running (X/X replicas)
- No constant failures/restarts
- Processor can connect to Kafka and MongoDB
- Sensors can connect to Kafka
- Scaling test shows some throughput increase

✅ **Ideal**:
- Services distributed across manager + workers
- DNS working OR documented workaround with IPs
- Scaling test shows linear throughput increase (2x, 5x)
- Zero service failures

---

## Resources

- **Docker Swarm DNS Issue**: https://github.com/moby/moby/issues/1429
- **VMware Network Issues**: Article about ethtool tx-checksum fixes
- **Stack Overflow**: Docker Swarm overlay networking UDP drops

---

## Notes from Today's Session

- `--advertise-addr` fix applied ✅
- Network offload fix applied ✅  
- All ports verified open ✅
- `endpoint_mode: dnsrr` doesn't help (no VIP, DNS still broken)
- `tx-checksum-ipv4` is **[fixed]** on AWS EC2 (can't be disabled)
- Disabling `tso`, `gso`, `sg` is possible and may help
- Kafka VIP when NOT using dnsrr: Need to check tomorrow
- Services work when on same node (manager)
- Services fail when on different nodes (cross-node overlay DNS broken)

**Bottom line**: DNS is fundamentally broken in this setup. Need to bypass it with IP addresses.
