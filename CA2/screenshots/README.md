# CA2 Screenshots - Required Deliverables

## 📸 Screenshots Needed for Grading

This directory should contain visual evidence of the deployed system as required by the CA2 assignment rubric.

---

## 🔴 CRITICAL (Required for Full Credit)

### 1. Cluster Status - `docker node ls`
**Filename**: `cluster-nodes.png`

**Command to capture**:
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.188.102 'docker node ls'
```

**Should show**:
- 5 total nodes (1 manager, 4 workers)
- All nodes in "Ready" state
- Manager node with "Leader" status
- Node IDs and hostnames

---

### 2. Stack Services Status - `docker stack ps`
**Filename**: `stack-services-distribution.png`

**Command to capture**:
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.188.102 'docker stack ps plant-monitoring --no-trunc'
```

**Should show**:
- All 7 services deployed
- Services distributed across different nodes
- Current state (Running)
- Service placement (manager vs workers)

---

### 3. Service Health - `docker service ls`
**Filename**: `service-health.png`

**Command to capture**:
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.188.102 'docker service ls'
```

**Should show**:
- plant-monitoring_zookeeper: 1/1
- plant-monitoring_kafka: 1/1
- plant-monitoring_mongodb: 1/1
- plant-monitoring_processor: 1/1
- plant-monitoring_mosquitto: 1/1
- plant-monitoring_homeassistant: 1/1
- plant-monitoring_sensor: 2/2
- All services at 100% health

---

### 4. Network Configuration - Overlay Network
**Filename**: `overlay-network-config.png`

**Command to capture**:
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.188.102 'docker network inspect plant-monitoring_plant-network --format "{{json .}}" | jq'
```

**Should show**:
- Driver: overlay
- Scope: swarm
- Encrypted: true
- Subnet: 10.10.0.0/24
- Containers attached to network

**Alternative**: Screenshot of `docker-compose.yml` network section (lines 264-270)

---

## 🟡 RECOMMENDED (Strengthens Submission)

### 5. Scaling Test Results Visualization
**Filename**: `scaling-results-chart.png`

**Source data**: `plant-monitor-swarm-IaC/scaling-results-20251019-184018.txt`

**Should show**:
- Bar chart or line graph
- X-axis: Number of replicas (1, 2, 5)
- Y-axis: Messages per second or throughput
- Clear 150% improvement annotation
- Title: "Sensor Service Horizontal Scaling Results"

**Tools**: Excel, Google Sheets, Python matplotlib, or online chart generator

---

### 6. Cross-Node Communication Proof
**Filename**: `cross-node-communication.png`

**Commands to capture**:
```bash
# Show processor connecting to Kafka on different node
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.188.102 \
  'docker service logs plant-monitoring_processor --tail 10 | grep -i kafka'

# Show service placement on different nodes
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.188.102 \
  'docker service ps plant-monitoring_processor && docker service ps plant-monitoring_kafka'
```

**Should show**:
- Processor logs: "✅ Connected to Kafka"
- Kafka running on node: 10.0.2.101 (worker)
- Processor running on node: 10.0.1.6 (manager)
- Proof of manager→worker communication

---

### 7. Home Assistant Dashboard
**Filename**: `homeassistant-dashboard.png`

**URL**: http://3.137.188.102:8123

**Should show**:
- Home Assistant UI loaded
- Plant sensor data visible
- Sensor readings (moisture, temperature, light)
- Timestamp showing recent data
- Automations/alerts configured

---

### 8. Secrets Management
**Filename**: `secrets-list.png`

**Command to capture**:
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.188.102 'docker secret ls'
```

**Should show**:
- 7 secrets listed:
  - mongo_root_username
  - mongo_root_password
  - mongo_app_username
  - mongo_app_password
  - mongodb_connection_string
  - mqtt_username
  - mqtt_password
- Created timestamps
- No secret values visible (security proof)

---

## 🟢 OPTIONAL (Nice to Have)

### 9. Network Topology Diagram
**Filename**: `network-topology-diagram.png`

**Content**: Visual diagram showing:
- AWS VPC structure
- Public subnet (manager: 3.137.188.102)
- Private subnet (4 workers with NAT gateway)
- Overlay network (10.10.0.0/24) connecting all services
- IPsec encryption indicators
- Service placement across nodes

**Tools**: draw.io, Lucidchart, AWS Architecture Icons, PlantUML

---

### 10. AWS Infrastructure
**Filename**: `aws-infrastructure.png`

**Content**: Screenshot from AWS Console showing:
- EC2 instances (5 total, all running)
- VPC configuration
- Security groups with IPsec rules
- EBS volumes attached

---

### 11. Scaling in Action
**Filename**: `scaling-in-progress.png`

**Command to capture**:
```bash
# Scale up to 5 replicas
docker service scale plant-monitoring_sensor=5

# Immediately capture while scaling
docker service ps plant-monitoring_sensor
```

**Should show**:
- Services starting on different nodes
- Some replicas in "Running", some in "Starting"
- Distribution across workers

---

## 📝 Quick Screenshot Capture Script

Create this script to capture all required screenshots automatically:

```bash
#!/bin/bash
# capture-screenshots.sh

MANAGER_IP="3.137.188.102"
SSH_KEY="~/.ssh/docker-swarm-key"
SSH_CMD="ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MANAGER_IP"

echo "Capturing CA2 Screenshots..."
echo "================================"

echo "1. Cluster Nodes Status..."
$SSH_CMD 'docker node ls'
read -p "Screenshot saved? Press Enter..."

echo "2. Stack Services Distribution..."
$SSH_CMD 'docker stack ps plant-monitoring --no-trunc'
read -p "Screenshot saved? Press Enter..."

echo "3. Service Health..."
$SSH_CMD 'docker service ls'
read -p "Screenshot saved? Press Enter..."

echo "4. Overlay Network Configuration..."
$SSH_CMD 'docker network inspect plant-monitoring_plant-network'
read -p "Screenshot saved? Press Enter..."

echo "5. Secrets List..."
$SSH_CMD 'docker secret ls'
read -p "Screenshot saved? Press Enter..."

echo "6. Cross-Node Communication..."
$SSH_CMD 'docker service ps plant-monitoring_processor && echo "" && docker service ps plant-monitoring_kafka'
read -p "Screenshot saved? Press Enter..."

echo "7. Processor Logs (Kafka Connection)..."
$SSH_CMD 'docker service logs plant-monitoring_processor --tail 20 | grep -i "kafka\|connected\|stored"'
read -p "Screenshot saved? Press Enter..."

echo ""
echo "✅ All terminal screenshots captured!"
echo ""
echo "Still needed:"
echo "- Home Assistant dashboard (browser): http://$MANAGER_IP:8123"
echo "- Scaling results chart (create from scaling-results-20251019-184018.txt)"
echo "- Optional: Network topology diagram"
```

---

## 📊 Assignment Rubric - Screenshot Requirements

From CA2 Assignment README:

> **Outputs**:
> - Screenshot of `kubectl get all -A` or `docker stack ps` ✅
> - NetworkPolicy YAML or Swarm network diagram ✅
> - Scaling results snapshot (chart or table) ✅

---

## Status Checklist

- [ ] `cluster-nodes.png` - Docker node ls output
- [ ] `stack-services-distribution.png` - Service placement across nodes
- [ ] `service-health.png` - All services healthy (1/1 or 2/2)
- [ ] `overlay-network-config.png` - Encrypted network configuration
- [ ] `scaling-results-chart.png` - Visual chart of 150% improvement
- [ ] `homeassistant-dashboard.png` - UI showing plant data
- [ ] `cross-node-communication.png` - Manager→Worker traffic proof
- [ ] `secrets-list.png` - Docker secrets ls output

**Time Estimate**: 30-45 minutes to capture all critical screenshots

**Tool Recommendations**:
- **macOS**: Cmd+Shift+4 (select area)
- **Windows**: Snipping Tool or Win+Shift+S
- **Linux**: gnome-screenshot or Flameshot

---

**Next Steps**:
1. Run commands on manager node
2. Take screenshots of terminal output
3. Save to this directory with proper filenames
4. Update main README with screenshot references
5. Submit CA2 assignment! 🚀
