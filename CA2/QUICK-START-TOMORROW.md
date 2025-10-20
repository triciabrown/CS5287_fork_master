# Quick Start Guide for Tomorrow

## The Plan: Use Kafka VIP Instead of DNS

**Time needed**: ~30 minutes

### Step 1: Get Kafka VIP (5 min)
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC

# Get manager IP
MANAGER_IP=$(cd terraform && terraform output -raw manager_public_ip)

# Get Kafka VIP
ssh -i ~/.ssh/docker-swarm-key ubuntu@$MANAGER_IP \
  'docker service inspect plant-monitoring_kafka --format "{{json .Endpoint.VirtualIPs}}" | python3 -m json.tool'

# Look for the VIP on plant-monitoring_plant-network
# Example output: "Addr": "10.10.0.15/24"
# The VIP is 10.10.0.15
```

### Step 2: Update docker-compose.yml (10 min)
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC
vim docker-compose.yml
```

**Find and replace** (use actual VIP from Step 1):
- Line ~199: `KAFKA_BROKER: 'kafka:9092'` → `KAFKA_BROKER: '10.10.0.15:9092'`
- Line ~235: `KAFKA_BROKER: 'kafka:9092'` → `KAFKA_BROKER: '10.10.0.15:9092'`
- Line ~270: `KAFKA_BROKERS: 'kafka:9092'` → `KAFKA_BROKERS: '10.10.0.15:9092'`

### Step 3: Copy and Redeploy (10 min)
```bash
# Copy updated docker-compose.yml to manager
scp -i ~/.ssh/docker-swarm-key docker-compose.yml ubuntu@$MANAGER_IP:/home/ubuntu/plant-monitor/

# SSH to manager
ssh -i ~/.ssh/docker-swarm-key ubuntu@$MANAGER_IP

# Redeploy stack
cd /home/ubuntu/plant-monitor
docker stack rm plant-monitoring
sleep 15
docker stack deploy -c docker-compose.yml plant-monitoring

# Wait for services
sleep 45
docker service ls
```

### Step 4: Verify (5 min)
```bash
# Check services are running
docker service ps plant-monitoring_processor plant-monitoring_sensor

# Check logs - should see "Connected" messages, NO "ENOTFOUND" errors
docker service logs plant-monitoring_processor --tail 20

# Exit SSH
exit

# Run scaling test
./scaling-test.sh
```

## Expected Result
- ✅ Processor: 1/1 running
- ✅ Sensors: 2/2 running  
- ✅ Scaling test shows increasing message throughput

---

## If It Still Doesn't Work

### Plan B: Force All to Manager (Fallback)
```bash
# Edit docker-compose.yml
# Add to EVERY service:
deploy:
  placement:
    constraints:
      - node.role == manager

# Redeploy
./deploy.sh

# Document in README that multi-node DNS is broken
```

This at least shows:
- ✅ IaC automation works
- ✅ One-command deployment works
- ✅ Security architecture works
- ✅ All services functional

Just can't demonstrate cross-node scaling due to Docker Swarm bug.

---

## Key Files
- **Plan**: `CA2/TODO-DNS-FIX-PLAN.md` (detailed)
- **Config**: `CA2/plant-monitor-swarm-IaC/docker-compose.yml`
- **Deploy**: `CA2/plant-monitor-swarm-IaC/deploy.sh`
- **Test**: `CA2/plant-monitor-swarm-IaC/scaling-test.sh`

## Manager IP
Get fresh IP each time after deployment:
```bash
cd CA2/plant-monitor-swarm-IaC/terraform
terraform output manager_public_ip
```
