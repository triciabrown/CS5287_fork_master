# CA4 Operations Runbook

**System**: Edge-to-Cloud Plant Monitoring System  
**Last Updated**: December 2, 2025  
**Maintained By**: Tricia Brown

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Standard Operations](#standard-operations)
3. [Incident Response Procedures](#incident-response-procedures)
4. [Troubleshooting Guide](#troubleshooting-guide)
5. [Emergency Contacts](#emergency-contacts)

---

## System Overview

### Architecture Summary

- **Edge Site**: Local machine running 3 sensor containers
- **Cloud Site**: AWS EC2 (5 instances) running Docker Swarm
- **Connectivity**: WireGuard site-to-site VPN (10.20.0.0/24)
- **Data Flow**: Sensors → VPN → Kafka → Processor → MongoDB + MQTT → Home Assistant

### Critical Services

| Service | Location | Purpose | Health Check |
|---------|----------|---------|--------------|
| WireGuard VPN | Edge + Cloud | Site-to-site connectivity | `sudo wg show` |
| Kafka | Cloud (10.20.0.1:9092) | Message broker | `docker service ls` |
| ZooKeeper | Cloud | Kafka coordination | `docker service ls` |
| MongoDB | Cloud | Sensor data storage | `docker service ls` |
| Processor | Cloud | Data processing pipeline | `docker service ls` |
| Mosquitto | Cloud | MQTT broker | `docker service ls` |
| Home Assistant | Cloud | Dashboard UI | `docker service ls` |
| Plant Sensors | Edge | Data producers | `docker compose ps` |

### Key IP Addresses

- **Cloud VPN Gateway**: 10.20.0.1
- **Edge VPN Client**: 10.20.0.2
- **Manager Node**: Check `.manager-ip` file
- **Frontend Network**: 10.10.1.0/24
- **Messaging Network**: 10.10.2.0/24
- **Data Network**: 10.10.3.0/24

---

## Standard Operations

### Daily Health Checks

Run these commands daily to verify system health:

```bash
# 1. Check all cloud services
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) 'sudo docker service ls'
# Expected: All services show 1/1 replicas

# 2. Verify VPN connectivity
ping -c 3 10.20.0.1
# Expected: 0% packet loss, ~20-30ms RTT

# 3. Check edge sensors
cd CA4/edge-site && docker compose ps
# Expected: 3 containers in "running" state

# 4. Verify data flow
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service logs --tail 20 plant-monitoring_processor | grep "Stored to MongoDB"'
# Expected: Recent log entries showing data processing
```

### Deployment Procedures

#### Full System Deployment

```bash
cd CA4/scripts
./deploy-all.sh deploy
```

**Duration**: 10-15 minutes  
**Validates**: Infrastructure, VPN, services, end-to-end data flow

#### Cloud-Only Deployment

```bash
cd CA4/scripts
./deploy-all.sh cloud
```

**Duration**: 8-10 minutes  
**Deploys**: AWS infrastructure and Docker Swarm services only

#### VPN-Only Deployment

```bash
cd CA4/scripts
./deploy-all.sh vpn
```

**Prerequisites**: Cloud infrastructure must be running  
**Duration**: 2-3 minutes

#### Edge-Only Deployment

```bash
cd CA4/scripts
./deploy-all.sh edge
```

**Prerequisites**: VPN must be established  
**Duration**: 1-2 minutes

### Shutdown Procedures

#### Graceful Shutdown (Data Preservation)

```bash
# 1. Stop edge sensors
cd CA4/edge-site
docker compose down
# Containers stopped, data in Kafka preserved

# 2. Stop edge VPN
sudo wg-quick down wg0
# VPN tunnel down, cloud still running

# 3. Cloud services continue running for other clients (if any)
```

#### Full Teardown (Delete All Resources)

```bash
cd CA4/scripts
./deploy-all.sh cleanup
```

**⚠️ WARNING**: This permanently deletes:
- All AWS resources (EC2 instances, VPC, etc.)
- All data in MongoDB
- All generated VPN configs

**Duration**: 5-8 minutes

---

## Incident Response Procedures

### Incident 1: VPN Tunnel Failure

**Severity**: 🔴 Critical (blocks all edge-to-cloud communication)

#### Detection

**Symptoms**:
- Edge sensors cannot reach Kafka (connection refused errors)
- Ping to cloud gateway (10.20.0.1) fails
- VPN interface `wg0` shows 0 bytes received

**Monitoring Commands**:
```bash
# Check VPN status
sudo wg show

# Test connectivity
ping -c 3 10.20.0.1

# Check sensor logs
cd CA4/edge-site
docker compose logs plant-sensor-001 --tail 50
```

#### Diagnosis

1. **Check VPN interface status**:
   ```bash
   sudo wg show wg0
   ```
   - If no output → VPN is down
   - If shows handshake timestamp → Check if recent (< 2 min ago)

2. **Check cloud-side VPN**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) 'sudo wg show'
   ```
   - Verify peer (10.20.0.2) is listed
   - Check latest handshake timestamp

3. **Check network connectivity**:
   ```bash
   # Test internet connectivity
   ping -c 3 8.8.8.8
   
   # Test AWS security group (UDP 51820)
   nc -u -v <MANAGER_IP> 51820
   ```

#### Recovery

**Option 1: Restart VPN (Edge Side)**
```bash
# Stop VPN
sudo wg-quick down wg0

# Wait 5 seconds
sleep 5

# Start VPN
sudo wg-quick up wg0

# Verify connectivity
ping -c 3 10.20.0.1
```

**Expected Recovery Time**: 10-15 seconds

**Option 2: Restart VPN (Cloud Side)**
```bash
# SSH to manager
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip)

# Restart VPN
sudo wg-quick down wg0
sleep 5
sudo wg-quick up wg0

# Verify
sudo wg show
```

**Option 3: Regenerate VPN Configuration**
```bash
cd CA4/vpn-config

# Generate new keys
./generate-keys.sh

# Deploy to cloud
./setup-vpn.sh cloud

# Deploy to edge
./setup-vpn.sh edge
```

**Expected Recovery Time**: 3-5 minutes

#### Verification

1. **VPN Interface Active**:
   ```bash
   sudo wg show wg0
   # Should show interface, peer, and recent handshake
   ```

2. **Connectivity Restored**:
   ```bash
   ping -c 5 10.20.0.1
   # Should show 0% packet loss
   ```

3. **Kafka Accessible**:
   ```bash
   nc -zv 10.20.0.1 9092
   # Should show "succeeded"
   ```

4. **Sensors Publishing**:
   ```bash
   cd CA4/edge-site
   docker compose logs plant-sensor-001 --tail 20
   # Should show successful message sends
   ```

5. **Data Reaching Processor**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker service logs --tail 20 plant-monitoring_processor'
   # Should show recent data processing
   ```

#### Post-Incident

- Document duration of outage
- Check if sensor data buffered or lost
- Review WireGuard logs: `sudo journalctl -u wg-quick@wg0 -n 100`
- Consider implementing VPN monitoring alert

**Automated Drill**: See `failure-drills/vpn-failure.sh` and `vpn-failure-drill.log`

---

### Incident 2: Kafka Broker Failure

**Severity**: 🟠 High (stops data processing pipeline)

#### Detection

**Symptoms**:
- Processor logs show "Connection refused" or "Broker not available"
- Kafka service shows 0/1 replicas
- Sensors continue publishing (no immediate errors due to async producer)
- Home Assistant stops receiving updates

**Monitoring Commands**:
```bash
# Check Kafka service status
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service ls --filter name=kafka'

# Check processor logs for errors
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service logs --tail 100 plant-monitoring_processor | grep -i error'

# Check Kafka container logs
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service logs --tail 100 plant-monitoring_kafka'
```

#### Diagnosis

1. **Check service replica count**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker service ls'
   ```
   - If Kafka shows 0/1 → Service crashed or scaled down
   - If shows 1/1 but old → Container restart loop

2. **Check Kafka logs for errors**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker service logs --tail 200 plant-monitoring_kafka | grep -i error'
   ```
   - Common issues: ZooKeeper connection, port conflicts, OOM

3. **Check ZooKeeper health**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker service ls --filter name=zookeeper'
   ```
   - Kafka depends on ZooKeeper; if ZK is down, Kafka won't start

4. **Check resource constraints**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker stats --no-stream'
   ```
   - Look for high CPU/memory usage

#### Recovery

**Option 1: Scale Service (if at 0/0)**
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service scale plant-monitoring_kafka=1'

# Monitor convergence
watch 'ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) "sudo docker service ls"'
```

**Expected Recovery Time**: 30-60 seconds (Kafka startup time)

**Option 2: Force Service Update**
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service update --force plant-monitoring_kafka'
```

**Expected Recovery Time**: 30-60 seconds

**Option 3: Remove and Redeploy Service**
```bash
# SSH to manager
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip)

# Navigate to compose file
cd /home/ubuntu/plant-monitor-swarm-IaC

# Remove Kafka service
sudo docker service rm plant-monitoring_kafka

# Wait for cleanup
sleep 10

# Redeploy stack
sudo docker stack deploy -c docker-compose.yml plant-monitoring
```

**Expected Recovery Time**: 1-2 minutes

**Option 4: Full Stack Redeploy**
```bash
cd CA4/scripts
./deploy-all.sh cloud
```

**Expected Recovery Time**: 8-10 minutes

#### Verification

1. **Service Running**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker service ls --filter name=kafka'
   # Should show 1/1 replicas
   ```

2. **Kafka Listening on Port**:
   ```bash
   # From edge
   nc -zv 10.20.0.1 9092
   # Should succeed
   ```

3. **Consumer Group Active**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker exec $(sudo docker ps -qf name=kafka) kafka-consumer-groups \
       --bootstrap-server localhost:9092 --describe --group plant-processor-group'
   # Should show processor as consumer with low lag
   ```

4. **Processor Consuming Messages**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker service logs --tail 20 plant-monitoring_processor'
   # Should show recent message processing
   ```

5. **Data in MongoDB**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker exec $(sudo docker ps -qf name=mongodb) \
       mongosh plant_monitoring --eval "db.sensor_data.countDocuments()"'
   # Count should be increasing
   ```

#### Post-Incident

- Check Kafka logs for root cause: `docker service logs plant-monitoring_kafka`
- Review resource usage during incident
- Check if topic partitions are healthy
- Verify consumer group lag returned to near-zero
- Consider implementing Kafka health monitoring

**Automated Drill**: See `failure-drills/kafka-failure.sh` and `kafka-failure-drill.log`

---

### Incident 3: Network Partition (Edge ↔ Cloud)

**Severity**: 🔴 Critical (isolates edge from cloud)

#### Detection

**Symptoms**:
- Sensors cannot reach Kafka (timeout errors)
- VPN appears up but traffic blocked
- Ping to cloud gateway succeeds but Kafka connection fails
- Firewall or iptables rules blocking traffic

**Monitoring Commands**:
```bash
# Check iptables rules
sudo iptables -L -n -v

# Test connectivity
ping -c 3 10.20.0.1
nc -zv 10.20.0.1 9092

# Check sensor logs
cd CA4/edge-site
docker compose logs --tail 50
```

#### Diagnosis

1. **Check iptables rules (Edge)**:
   ```bash
   sudo iptables -L OUTPUT -n -v
   sudo iptables -L INPUT -n -v
   ```
   - Look for DROP or REJECT rules targeting 10.20.0.0/24

2. **Check iptables rules (Cloud)**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo iptables -L -n -v'
   ```
   - Look for rules blocking VPN subnet (10.20.0.0/24)

3. **Check AWS Security Groups**:
   ```bash
   # List security groups
   aws ec2 describe-security-groups --region us-east-2 \
     --filters "Name=group-name,Values=docker-swarm-*"
   ```
   - Verify UDP 51820 (WireGuard) allowed
   - Verify TCP 9092 allowed from 10.20.0.0/24

4. **Test specific ports**:
   ```bash
   # From edge
   telnet 10.20.0.1 9092
   nc -zv 10.20.0.1 9092
   ```

#### Recovery

**Option 1: Clear iptables Rules (Edge)**
```bash
# Flush OUTPUT chain
sudo iptables -F OUTPUT

# Flush INPUT chain
sudo iptables -F INPUT

# Verify
sudo iptables -L -n -v
```

**Expected Recovery Time**: Immediate

**Option 2: Clear iptables Rules (Cloud)**
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo iptables -F'
```

**Option 3: Remove Specific Rules**
```bash
# List rules with line numbers
sudo iptables -L OUTPUT -n --line-numbers

# Delete specific rule (replace X with line number)
sudo iptables -D OUTPUT X

# Verify
sudo iptables -L OUTPUT -n -v
```

**Option 4: Restart Networking**
```bash
# Edge side
sudo systemctl restart networking
sudo wg-quick down wg0 && sudo wg-quick up wg0

# Cloud side
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo systemctl restart networking'
```

**Expected Recovery Time**: 15-30 seconds

**Option 5: Fix AWS Security Group**
```bash
# Add inbound rule for Kafka from VPN subnet
aws ec2 authorize-security-group-ingress \
  --region us-east-2 \
  --group-id <SECURITY_GROUP_ID> \
  --protocol tcp \
  --port 9092 \
  --cidr 10.20.0.0/24
```

#### Verification

1. **No Blocking Rules**:
   ```bash
   sudo iptables -L OUTPUT -n -v | grep 10.20
   # Should show no DROP/REJECT rules
   ```

2. **ICMP Connectivity**:
   ```bash
   ping -c 5 10.20.0.1
   # Should show 0% packet loss
   ```

3. **Kafka Port Open**:
   ```bash
   nc -zv 10.20.0.1 9092
   # Should succeed
   ```

4. **Sensors Publishing**:
   ```bash
   cd CA4/edge-site
   docker compose logs plant-sensor-001 --tail 20
   # Should show successful sends
   ```

5. **End-to-End Flow**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker service logs --tail 20 plant-monitoring_processor'
   # Should show recent data processing
   ```

#### Post-Incident

- Document what caused the partition (manual rule, automation error, etc.)
- Review firewall automation scripts
- Check if any scheduled tasks modify iptables
- Consider implementing network monitoring alerts

**Automated Drill**: See `failure-drills/network-partition.sh` and `network-partition-drill.log`

---

### Incident 4: Processor Service Failure

**Severity**: 🟡 Medium (data buffered in Kafka, no immediate loss)

#### Detection

**Symptoms**:
- Processor service shows 0/1 replicas
- Kafka consumer group shows increasing lag
- MongoDB not receiving new data
- Home Assistant sensors showing old values

**Monitoring Commands**:
```bash
# Check processor status
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service ls --filter name=processor'

# Check consumer lag
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker exec $(sudo docker ps -qf name=kafka) kafka-consumer-groups \
    --bootstrap-server localhost:9092 --describe --group plant-processor-group'
```

#### Diagnosis

1. **Check processor logs**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker service logs --tail 200 plant-monitoring_processor'
   ```
   - Common errors: MongoDB connection, Kafka connection, Python exceptions

2. **Check MongoDB connectivity**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker service ls --filter name=mongodb'
   ```

3. **Verify secrets exist**:
   ```bash
   ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
     'sudo docker secret ls'
   ```
   - Should show: mongodb_user, mongodb_password, mongodb_uri

#### Recovery

**Option 1: Scale Service**
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service scale plant-monitoring_processor=1'
```

**Option 2: Force Update**
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service update --force plant-monitoring_processor'
```

**Option 3: Check MongoDB User**
```bash
# Verify MongoDB user exists
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker exec $(sudo docker ps -qf name=mongodb) \
    mongosh plant_monitoring --eval "db.getUsers()"'

# If user missing, recreate
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip)
cd /home/ubuntu/plant-monitor-swarm-IaC/scripts
./wait-for-mongodb.sh
```

#### Verification

1. **Service Running**: Check `docker service ls`
2. **Consumer Lag Decreasing**: Monitor consumer group
3. **Data in MongoDB**: Query sensor_data collection
4. **MQTT Messages**: Check Home Assistant sensors updating

---

### Incident 5: MongoDB Connection Issues

**Severity**: 🟡 Medium (processor fails, data buffered in Kafka)

#### Detection

**Symptoms**:
- Processor logs show "Authentication failed" or "Connection refused"
- MongoDB service running but processor cannot connect
- Secrets may be misconfigured

#### Diagnosis

```bash
# Check MongoDB logs
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service logs --tail 100 plant-monitoring_mongodb'

# Check processor logs
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service logs --tail 100 plant-monitoring_processor | grep -i mongo'

# Verify MongoDB user
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker exec $(sudo docker ps -qf name=mongodb) \
    mongosh admin --eval "db.getUsers()"'
```

#### Recovery

**Option 1: Recreate MongoDB User**
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip)
cd /home/ubuntu/plant-monitor-swarm-IaC/scripts
./wait-for-mongodb.sh
```

**Option 2: Update Secrets**
```bash
# Remove old secrets
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip)
sudo docker secret rm mongodb_user mongodb_password mongodb_uri

# Recreate
cd /home/ubuntu/plant-monitor-swarm-IaC/scripts
./create-secrets.sh

# Update processor
sudo docker service update --force plant-monitoring_processor
```

#### Verification

1. Test MongoDB connection from processor container
2. Check processor logs for successful connection
3. Verify data appearing in MongoDB

---

### Incident 6: Edge Sensor Failure

**Severity**: 🟢 Low (only affects one sensor, others continue)

#### Detection

**Symptoms**:
- One sensor container stopped or crashing
- Logs show Python exceptions or connection errors
- Missing data for specific plant ID

#### Diagnosis

```bash
cd CA4/edge-site

# Check container status
docker compose ps

# Check logs
docker compose logs plant-sensor-001 --tail 100
```

#### Recovery

```bash
# Restart specific sensor
docker compose restart plant-sensor-001

# Or restart all sensors
docker compose restart

# Or rebuild and restart
docker compose up -d --build
```

#### Verification

```bash
# Check all sensors running
docker compose ps

# Verify publishing
docker compose logs plant-sensor-001 --tail 20
```

---

## Troubleshooting Guide

### Common Issues

#### Issue: "Permission denied" when running scripts

**Solution**:
```bash
chmod +x CA4/scripts/*.sh
chmod +x CA4/failure-drills/*.sh
chmod +x CA4/vpn-config/*.sh
```

#### Issue: Cannot SSH to manager node

**Solutions**:
```bash
# Check SSH key exists
ls -la ~/.ssh/docker-swarm-key

# Check manager IP
cat CA4/.manager-ip

# Check security group allows SSH from your IP
# AWS Console → EC2 → Security Groups → docker-swarm-manager-sg

# Get your public IP
curl -s ifconfig.me
```

#### Issue: Terraform apply fails

**Solutions**:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Destroy and retry
cd CA4/cloud-site/terraform
terraform destroy -auto-approve
terraform apply
```

#### Issue: Docker Swarm node not joining

**Solutions**:
```bash
# Regenerate join token
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker swarm join-token worker'

# Use new token on worker node
```

#### Issue: VPN handshake never completes

**Solutions**:
```bash
# Check UDP 51820 allowed in AWS security group
# Check cloud VPN is up: ssh to manager, run 'sudo wg show'
# Check clocks synchronized (WireGuard sensitive to time skew)
sudo timedatectl status

# Regenerate keys if needed
cd CA4/vpn-config
./generate-keys.sh
./setup-vpn.sh cloud
./setup-vpn.sh edge
```

#### Issue: Kafka startup timeout

**Cause**: Kafka takes 30-60 seconds to start after ZooKeeper

**Solution**:
```bash
# Wait longer, then check
sleep 60
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service ls'
```

---

## Emergency Contacts

### On-Call Schedule

- **Primary**: Tricia Brown
- **Backup**: [Team Member Name]
- **Escalation**: [Instructor/TA Name]

### Useful Links

- **GitHub Repository**: https://github.com/triciabrown/CS5287_fork_master
- **AWS Console**: https://console.aws.amazon.com/
- **Course Materials**: [Course URL]

### Key Scripts

| Script | Purpose | Location |
|--------|---------|----------|
| `deploy-all.sh` | Full deployment | `CA4/scripts/` |
| `verify-deployment.sh` | Health checks | `CA4/scripts/` |
| `vpn-failure.sh` | VPN failure drill | `CA4/failure-drills/` |
| `kafka-failure.sh` | Kafka failure drill | `CA4/failure-drills/` |
| `network-partition.sh` | Network partition drill | `CA4/failure-drills/` |

---

## Appendix

### Log Locations

```bash
# Cloud service logs
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service logs <SERVICE_NAME>'

# Edge sensor logs
cd CA4/edge-site
docker compose logs <SERVICE_NAME>

# VPN logs
sudo journalctl -u wg-quick@wg0 -n 100

# System logs (cloud)
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo journalctl -n 100'
```

### Service Dependencies

```
Home Assistant
    ↓
Mosquitto (MQTT)
    ↓
Processor ← → Kafka ← VPN ← Sensors
    ↓           ↓
MongoDB    ZooKeeper
```

### Network Port Reference

| Port | Service | Access |
|------|---------|--------|
| 22 | SSH | Manager public IP |
| 51820/udp | WireGuard | Manager public IP |
| 8123 | Home Assistant | Manager public IP |
| 9092 | Kafka | VPN only (10.20.0.1) |
| 27017 | MongoDB | Internal only |
| 1883 | Mosquitto | Internal only |
| 2181 | ZooKeeper | Internal only |

---

**Document Version**: 1.0  
**Last Reviewed**: December 2, 2025  
**Next Review**: [Set review schedule]
