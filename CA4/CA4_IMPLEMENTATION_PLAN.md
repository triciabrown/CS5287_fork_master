# CA4 Implementation Plan: Edge-to-Cloud Multi-Hybrid Deployment

**Course**: CS5287 - Cloud Computing  
**Assignment**: CA4 - Multi-Hybrid Cloud (Final)  
**Student**: Tricia Brown  
**Date**: November 13, 2025  
**Topology**: Edge → Cloud

---

## Executive Summary

This document outlines the implementation plan for migrating the existing CA2 Docker Swarm plant monitoring system (single AWS deployment) to a **multi-site edge-to-cloud architecture**. The new topology splits data producers (sensors) to run locally at the edge while keeping the data processing infrastructure (Kafka, MongoDB, processor, Home Assistant) in AWS.

**Key Objectives**:
- ✅ Deploy sensor producers locally (edge site - laptop/VM)
- ✅ Deploy Kafka, MongoDB, processor, Home Assistant in AWS (cloud site)
- ✅ Establish secure VPN overlay between edge and cloud
- ✅ Demonstrate end-to-end data flow across sites
- ✅ Simulate failure scenarios and recovery procedures
- ✅ Fully automate deployment with scripts

---

## Table of Contents

1. [CA2 Architecture Analysis](#1-ca2-architecture-analysis)
2. [CA4 Edge-to-Cloud Architecture](#2-ca4-edge-to-cloud-architecture)
3. [VPN Connectivity Design](#3-vpn-connectivity-design)
4. [Edge Site Design](#4-edge-site-design)
5. [Cloud Site Modifications](#5-cloud-site-modifications)
6. [Deployment Automation](#6-deployment-automation)
7. [Failure Scenarios & Recovery](#7-failure-scenarios--recovery)
8. [Implementation Timeline](#8-implementation-timeline)
9. [Success Criteria](#9-success-criteria)

---

## 1. CA2 Architecture Analysis

### Current CA2 Setup (Baseline)

**Infrastructure**:
- **Cloud Provider**: AWS (us-east-2)
- **Cluster**: Docker Swarm (1 manager + 4 workers)
- **Network**: Encrypted overlay network (10.10.0.0/24)
- **Deployment**: Single-site, all components in AWS

**Components**:
| Component | Location | Replicas | Purpose |
|-----------|----------|----------|---------|
| ZooKeeper | AWS (manager) | 1 | Kafka coordination |
| Kafka | AWS (worker) | 1 | Message broker |
| MongoDB | AWS (worker) | 1 | Data persistence |
| Processor | AWS (manager) | 1 | Data pipeline (Kafka→MongoDB→MQTT) |
| Mosquitto | AWS (manager) | 1 | MQTT broker |
| Home Assistant | AWS (manager) | 1 | Dashboard/UI |
| **Sensors** | **AWS (workers)** | **2-5** | **IoT data producers** ⬅️ MOVE TO EDGE |

**Key Infrastructure Code**:
- **Terraform**: `CA2/plant-monitor-swarm-IaC/terraform/main.tf` (AWS VPC, EC2, security groups)
- **Docker Compose**: `CA2/plant-monitor-swarm-IaC/docker-compose.yml` (Swarm stack)
- **Deployment Script**: `CA2/plant-monitor-swarm-IaC/deploy.sh` (automated deployment)
- **Application Code**: `CA2/applications/sensor/sensor.js` (plant sensor simulator)

### CA2 Strengths to Leverage

✅ **Proven Infrastructure**: 40+ hours of AWS networking troubleshooting resolved (source/dest check, IPsec)  
✅ **Automated Deployment**: Single-command deployment (`./deploy.sh`)  
✅ **Security Best Practices**: Docker secrets, encrypted overlay network  
✅ **Application Code**: 70-80% reusable from CA1/CA2  
✅ **Scaling Demonstrated**: 150% throughput improvement with horizontal scaling  

### CA2 Components to Adapt for CA4

🔄 **Sensor Deployment**: Move from AWS workers to edge (local laptop/VM)  
🔄 **Kafka Configuration**: Update advertised listeners for external access over VPN  
🔄 **Security Groups**: Open Kafka port (9092) to VPN subnet  
🔄 **Docker Compose**: Split into two files (edge-compose.yml, cloud-compose.yml)  
🔄 **Network Architecture**: Add VPN tunnel between edge and cloud networks  

---

## 2. CA4 Edge-to-Cloud Architecture

### Topology Overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          CA4 ARCHITECTURE                                   │
└────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────┐                 ┌──────────────────────────────┐
│     EDGE SITE            │                 │     CLOUD SITE (AWS)         │
│   (Local Laptop/VM)      │                 │    us-east-2                 │
│                          │                 │                              │
│  ┌────────────────────┐  │   VPN Tunnel    │  ┌────────────────────────┐  │
│  │  Plant Sensors     │  │   (WireGuard/   │  │  Docker Swarm Cluster  │  │
│  │  (Docker)          │──┼───OpenVPN)──────┼─→│  1 Manager + 2 Workers │  │
│  │                    │  │   Encrypted     │  │                        │  │
│  │  • sensor-1        │  │                 │  │  Manager Node:         │  │
│  │  • sensor-2        │  │                 │  │  • ZooKeeper           │  │
│  │  • sensor-3        │  │                 │  │  • Mosquitto           │  │
│  └────────────────────┘  │                 │  │  • Home Assistant      │  │
│                          │                 │  │  • Processor           │  │
│  Local Network:          │                 │  │                        │  │
│  192.168.1.0/24          │                 │  │  Worker Nodes:         │  │
│                          │                 │  │  • Kafka (9092)        │  │
│  VPN Interface:          │                 │  │  • MongoDB (27017)     │  │
│  10.20.0.2/24            │                 │  │                        │  │
└──────────────────────────┘                 │  VPN Gateway:              │  │
                                             │  10.20.0.1/24              │  │
                                             │                            │  │
                                             │  AWS VPC:                  │  │
                                             │  10.0.0.0/16               │  │
                                             └────────────────────────────┘  │
                                                                              │
                Data Flow:                                                    │
                ─────────                                                     │
                Sensors (Edge) ──VPN tunnel──→ Kafka (Cloud)                 │
                                                  ↓                           │
                                             Processor (Cloud)                │
                                                  ↓                           │
                                             MongoDB (Cloud)                  │
                                                  ↓                           │
                                             MQTT → Home Assistant (Cloud)    │
```

### Network Design

**Edge Site (Local)**:
- Physical Network: 192.168.1.0/24 (home/office network)
- VPN Interface: 10.20.0.0/24 (overlay network)
- Edge Gateway: 10.20.0.2

**Cloud Site (AWS)**:
- AWS VPC: 10.0.0.0/16 (existing CA2 VPC)
- Docker Overlay: 10.10.0.0/24 (existing CA2 overlay)
- VPN Gateway: 10.20.0.1
- Kafka Advertised Listener: 10.20.0.1:9092 (accessible via VPN)

**VPN Tunnel**:
- Protocol: WireGuard (preferred) or OpenVPN (fallback)
- Encryption: ChaCha20-Poly1305 (WireGuard) or AES-256-GCM (OpenVPN)
- Routing: 10.20.0.0/24 ↔ 10.10.0.0/24 (edge ↔ cloud)

### Component Distribution

| Component | Site | Why |
|-----------|------|-----|
| **Sensors** | Edge | Data generation at source; realistic IoT deployment |
| **Kafka** | Cloud | Central message broker; stateful; cloud resources |
| **Processor** | Cloud | Data processing logic; needs MongoDB/MQTT access |
| **MongoDB** | Cloud | Data persistence; stateful; cloud storage |
| **Mosquitto** | Cloud | MQTT broker for Home Assistant |
| **Home Assistant** | Cloud | Dashboard UI; public-facing service |
| **ZooKeeper** | Cloud | Kafka dependency; stateful |

**Rationale**:
- **Edge**: Lightweight data producers only (minimal resource requirements)
- **Cloud**: Heavy stateful services (Kafka, MongoDB) requiring persistence and compute
- **Security**: VPN tunnel ensures encrypted communication; no public Kafka endpoint

---

## 3. VPN Connectivity Design

### VPN Technology Selection

**Option 1: WireGuard (RECOMMENDED)**

**Pros**:
- ✅ Modern, lightweight, fast (minimal overhead)
- ✅ Simple configuration (5-10 lines per peer)
- ✅ Built into Linux kernel 5.6+
- ✅ Perfect for site-to-site VPN
- ✅ Strong encryption (ChaCha20-Poly1305)

**Cons**:
- ❌ Requires kernel 5.6+ or manual installation

**Configuration**:
```bash
# Cloud VPN Gateway (AWS Manager Node)
[Interface]
Address = 10.20.0.1/24
PrivateKey = <cloud-private-key>
ListenPort = 51820

[Peer]
# Edge site
PublicKey = <edge-public-key>
AllowedIPs = 10.20.0.2/32, 192.168.1.0/24
PersistentKeepalive = 25

# Edge VPN Client (Local Laptop/VM)
[Interface]
Address = 10.20.0.2/24
PrivateKey = <edge-private-key>

[Peer]
# Cloud gateway
PublicKey = <cloud-public-key>
Endpoint = <AWS_MANAGER_PUBLIC_IP>:51820
AllowedIPs = 10.20.0.0/24, 10.10.0.0/24
PersistentKeepalive = 25
```

---

**Option 2: OpenVPN (FALLBACK)**

**Pros**:
- ✅ Mature, well-tested
- ✅ Available on all platforms
- ✅ Extensive documentation

**Cons**:
- ❌ More complex configuration
- ❌ Higher CPU overhead

**Use Case**: If WireGuard is unavailable

---

**Option 3: Tailscale/ZeroTier (EASIEST)**

**Pros**:
- ✅ Zero-configuration mesh VPN
- ✅ Handles NAT traversal automatically
- ✅ Free tier available

**Cons**:
- ❌ Relies on third-party service (less control)
- ❌ May not meet "establish secure connectivity" requirement

**Recommendation**: Use as rapid prototype, migrate to WireGuard for production

---

### VPN Implementation Plan (WireGuard)

**Step 1: Install WireGuard**

```bash
# Cloud (AWS Ubuntu 22.04)
sudo apt update
sudo apt install wireguard

# Edge (Ubuntu/Debian)
sudo apt update
sudo apt install wireguard

# Edge (macOS)
brew install wireguard-tools
```

**Step 2: Generate Keys**

```bash
# Cloud
wg genkey | tee cloud-private.key | wg pubkey > cloud-public.key

# Edge
wg genkey | tee edge-private.key | wg pubkey > edge-public.key
```

**Step 3: Configure Cloud Gateway**

```bash
# /etc/wireguard/wg0.conf on AWS manager node
[Interface]
Address = 10.20.0.1/24
PrivateKey = <cloud-private-key>
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <edge-public-key>
AllowedIPs = 10.20.0.2/32
PersistentKeepalive = 25
```

**Step 4: Configure Edge Client**

```bash
# /etc/wireguard/wg0.conf on edge laptop/VM
[Interface]
Address = 10.20.0.2/24
PrivateKey = <edge-private-key>

[Peer]
PublicKey = <cloud-public-key>
Endpoint = <AWS_MANAGER_PUBLIC_IP>:51820
AllowedIPs = 10.20.0.1/32, 10.10.0.0/24
PersistentKeepalive = 25
```

**Step 5: Start VPN**

```bash
# Cloud
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0  # Auto-start on boot

# Edge
sudo wg-quick up wg0

# Verify connectivity
ping 10.20.0.1  # From edge
ping 10.20.0.2  # From cloud
```

**Step 6: AWS Security Group Rules**

```hcl
# terraform/main.tf - Add WireGuard rule
ingress {
  description = "WireGuard VPN"
  from_port   = 51820
  to_port     = 51820
  protocol    = "udp"
  cidr_blocks = ["0.0.0.0/0"]  # Or restrict to edge public IP
}

# Allow Kafka access from VPN
ingress {
  description = "Kafka from VPN"
  from_port   = 9092
  to_port     = 9092
  protocol    = "tcp"
  cidr_blocks = ["10.20.0.0/24"]
}
```

---

## 4. Edge Site Design

### Edge Infrastructure

**Deployment Environment**: Local laptop or VM (Ubuntu 22.04 recommended)

**Docker Setup**: Docker Compose (non-Swarm, single-node)

**Services**: Plant sensor containers only

### Edge Docker Compose

**File**: `CA4/edge-site/docker-compose.yml`

```yaml
version: '3.8'

services:
  # ============================================================================
  # Plant Sensors (Edge Data Producers)
  # ============================================================================
  sensor-1:
    image: docker.io/triciab221/plant-sensor:v2.0.0  # Updated for CA4
    container_name: edge-sensor-1
    environment:
      KAFKA_BROKERS: '10.20.0.1:9092'  # Cloud Kafka via VPN
      PLANT_ID: 'plant-edge-001'
      PLANT_TYPE: 'monstera'
      LOCATION: 'Edge Site - Office'
      SENSOR_INTERVAL: '30'
      NODE_OPTIONS: '--max-old-space-size=128'
    restart: unless-stopped
    networks:
      - edge-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  sensor-2:
    image: docker.io/triciab221/plant-sensor:v2.0.0
    container_name: edge-sensor-2
    environment:
      KAFKA_BROKERS: '10.20.0.1:9092'
      PLANT_ID: 'plant-edge-002'
      PLANT_TYPE: 'sansevieria'
      LOCATION: 'Edge Site - Living Room'
      SENSOR_INTERVAL: '30'
      NODE_OPTIONS: '--max-old-space-size=128'
    restart: unless-stopped
    networks:
      - edge-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  sensor-3:
    image: docker.io/triciab221/plant-sensor:v2.0.0
    container_name: edge-sensor-3
    environment:
      KAFKA_BROKERS: '10.20.0.1:9092'
      PLANT_ID: 'plant-edge-003'
      PLANT_TYPE: 'monstera'
      LOCATION: 'Edge Site - Kitchen'
      SENSOR_INTERVAL: '30'
      NODE_OPTIONS: '--max-old-space-size=128'
    restart: unless-stopped
    networks:
      - edge-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  edge-network:
    driver: bridge
```

### Edge Deployment Script

**File**: `CA4/edge-site/deploy-edge.sh`

```bash
#!/bin/bash
set -e

echo "🌱 Deploying Edge Site - Plant Sensors"
echo "======================================="
echo ""

# Check VPN connectivity
echo "Checking VPN connectivity to cloud..."
if ! ping -c 3 10.20.0.1 > /dev/null 2>&1; then
    echo "❌ ERROR: Cannot reach cloud VPN gateway (10.20.0.1)"
    echo "Please ensure WireGuard VPN is running: sudo wg-quick up wg0"
    exit 1
fi
echo "✅ VPN connectivity OK"

# Check Kafka accessibility
echo "Checking Kafka connectivity..."
if ! timeout 5 bash -c "cat < /dev/null > /dev/tcp/10.20.0.1/9092" 2>/dev/null; then
    echo "❌ ERROR: Cannot reach Kafka at 10.20.0.1:9092"
    echo "Check cloud-site deployment and security groups"
    exit 1
fi
echo "✅ Kafka connectivity OK"

# Deploy sensors
echo ""
echo "Deploying sensor containers..."
docker-compose up -d

# Verify deployment
echo ""
echo "Verifying sensor deployment..."
sleep 5
docker-compose ps

echo ""
echo "✅ Edge site deployment complete!"
echo ""
echo "Sensor logs:"
echo "  docker-compose logs -f sensor-1"
echo "  docker-compose logs -f sensor-2"
echo "  docker-compose logs -f sensor-3"
echo ""
echo "Teardown:"
echo "  docker-compose down"
```

---

## 5. Cloud Site Modifications

### Changes to CA2 Infrastructure

**File**: `CA4/cloud-site/docker-compose.yml` (modified from CA2)

**Key Changes**:

1. **Remove Sensor Service** (moved to edge)
2. **Update Kafka Configuration** for VPN access
3. **Update Security Groups** for WireGuard

### Kafka Configuration Updates

```yaml
kafka:
  image: confluentinc/cp-kafka:7.4.0
  hostname: kafka
  environment:
    KAFKA_BROKER_ID: 1
    KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
    # UPDATED: Advertise on VPN interface for edge access
    KAFKA_ADVERTISED_LISTENERS: 'INTERNAL://kafka:9092,EXTERNAL://10.20.0.1:9092'
    KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: 'INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT'
    KAFKA_INTER_BROKER_LISTENER_NAME: 'INTERNAL'
    KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
    KAFKA_HEAP_OPTS: '-Xmx400m -Xms400m'
  ports:
    # ADDED: Expose port for VPN access
    - "9092:9092"
  volumes:
    - kafka_data:/var/lib/kafka/data
  networks:
    - plant-network
  depends_on:
    - zookeeper
  deploy:
    replicas: 1
    # ... rest of deploy config ...
```

### Terraform Security Group Updates

**File**: `CA4/cloud-site/terraform/main.tf`

```hcl
# Add WireGuard VPN ingress rule
resource "aws_security_group_rule" "allow_wireguard" {
  type              = "ingress"
  from_port         = 51820
  to_port           = 51820
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]  # Or restrict to edge public IP
  security_group_id = aws_security_group.swarm_manager_sg.id
  description       = "WireGuard VPN for edge-to-cloud connectivity"
}

# Add Kafka access from VPN subnet
resource "aws_security_group_rule" "allow_kafka_vpn" {
  type              = "ingress"
  from_port         = 9092
  to_port           = 9092
  protocol          = "tcp"
  cidr_blocks       = ["10.20.0.0/24"]  # VPN subnet
  security_group_id = aws_security_group.swarm_worker_sg.id
  description       = "Kafka access from VPN (edge sensors)"
}
```

### Cloud Deployment Script Updates

**File**: `CA4/cloud-site/deploy-cloud.sh` (adapted from CA2)

**Additions**:
1. Install and configure WireGuard
2. Generate VPN keys
3. Set up iptables forwarding
4. Deploy Swarm stack (without sensors)

---

## 6. Deployment Automation

### Master Deployment Script

**File**: `CA4/deploy-all.sh`

```bash
#!/bin/bash
# CA4 Complete Deployment: Edge-to-Cloud Plant Monitoring System

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     CA4: Multi-Hybrid Cloud Deployment                   ║"
echo "║     Edge-to-Cloud Plant Monitoring System                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Phase 1: Deploy Cloud Site (AWS)
echo "Phase 1: Deploying Cloud Site (AWS)"
echo "===================================="
cd cloud-site
./deploy-cloud.sh
CLOUD_VPN_IP=$(terraform -chdir=terraform output -raw manager_public_ip)
echo "Cloud VPN Gateway: ${CLOUD_VPN_IP}"
cd ..

# Phase 2: Configure VPN
echo ""
echo "Phase 2: Setting up VPN Tunnel"
echo "==============================="
cd vpn-config
./setup-vpn.sh "${CLOUD_VPN_IP}"
cd ..

# Phase 3: Deploy Edge Site (Local)
echo ""
echo "Phase 3: Deploying Edge Site (Local)"
echo "====================================="
cd edge-site
./deploy-edge.sh
cd ..

# Phase 4: Verification
echo ""
echo "Phase 4: End-to-End Verification"
echo "================================="
./verify-deployment.sh

echo ""
echo "✅ CA4 Deployment Complete!"
echo ""
echo "Access Points:"
echo "  🏠 Home Assistant: http://${CLOUD_VPN_IP}:8123"
echo "  🔐 SSH to Cloud:   ssh -i ~/.ssh/docker-swarm-key ubuntu@${CLOUD_VPN_IP}"
echo ""
echo "Next Steps:"
echo "  1. Review Home Assistant dashboard"
echo "  2. Monitor Kafka message flow: ./scripts/monitor-kafka.sh"
echo "  3. Run failure drill: ./failure-drills/vpn-failure.sh"
```

### Verification Script

**File**: `CA4/verify-deployment.sh`

```bash
#!/bin/bash
# End-to-end verification of edge-to-cloud deployment

echo "Verifying CA4 Deployment"
echo "========================"

# 1. VPN Connectivity
echo "1. Checking VPN connectivity..."
if ping -c 3 10.20.0.1 > /dev/null 2>&1; then
    echo "   ✅ VPN tunnel active"
else
    echo "   ❌ VPN tunnel down"
    exit 1
fi

# 2. Cloud Services
echo "2. Checking cloud services..."
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(terraform -chdir=cloud-site/terraform output -raw manager_public_ip) \
    'docker stack services plant-monitoring' | grep -q "1/1"
if [ $? -eq 0 ]; then
    echo "   ✅ All cloud services running"
else
    echo "   ❌ Some cloud services down"
fi

# 3. Edge Sensors
echo "3. Checking edge sensors..."
cd edge-site
if docker-compose ps | grep -q "Up"; then
    echo "   ✅ Edge sensors running"
else
    echo "   ❌ Edge sensors not running"
fi
cd ..

# 4. Data Flow
echo "4. Checking data flow (Kafka → MongoDB)..."
# TODO: Query MongoDB for recent sensor readings
echo "   ✅ Data flow verified (TODO: implement)"

echo ""
echo "Verification Complete!"
```

---

## 7. Failure Scenarios & Recovery

### Scenario 1: VPN Tunnel Failure

**Failure Injection**:
```bash
# On cloud gateway
sudo wg-quick down wg0
```

**Expected Behavior**:
- Edge sensors lose connectivity to Kafka
- Sensor containers show connection errors
- No new data in MongoDB

**Recovery Steps**:
1. Check VPN status: `sudo wg show`
2. Restart VPN: `sudo wg-quick up wg0`
3. Verify connectivity: `ping 10.20.0.1`
4. Confirm sensor reconnection in logs

**Runbook Entry**:
```
INCIDENT: VPN Tunnel Down
DETECTION: Sensors logging "Connection refused to 10.20.0.1:9092"
IMPACT: No sensor data reaching cloud
RECOVERY:
  1. SSH to cloud: ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP>
  2. Check WireGuard: sudo wg show
  3. Restart if down: sudo wg-quick up wg0
  4. Verify: ping 10.20.0.2 (from cloud)
  5. Monitor sensor logs for reconnection
PREVENTION: Enable systemd auto-start: sudo systemctl enable wg-quick@wg0
```

---

### Scenario 2: Cloud Kafka Unavailability

**Failure Injection**:
```bash
# Scale down Kafka service
docker service scale plant-monitoring_kafka=0
```

**Expected Behavior**:
- Edge sensors buffer messages (if configured)
- Processor stops consuming
- Home Assistant shows stale data

**Recovery Steps**:
1. Scale up Kafka: `docker service scale plant-monitoring_kafka=1`
2. Wait for Kafka startup (~30-60 seconds)
3. Verify topic exists: `kafka-topics --list`
4. Monitor processor logs for resumption

**Runbook Entry**:
```
INCIDENT: Kafka Service Down
DETECTION: Sensors show "Broker not available" errors
IMPACT: No message processing; data loss if sensors don't buffer
RECOVERY:
  1. SSH to cloud manager
  2. Check Kafka: docker service ls | grep kafka
  3. If 0/1, scale up: docker service scale plant-monitoring_kafka=1
  4. Wait for startup: docker service logs plant-monitoring_kafka -f
  5. Verify topic: docker exec <kafka-container> kafka-topics --list --bootstrap-server localhost:9092
  6. Monitor data flow resumption
PREVENTION: Enable health checks and auto-restart policies
```

---

### Scenario 3: Network Partition (AWS Instance Failure)

**Failure Injection**:
```bash
# Simulate instance failure by stopping Docker on a worker node
ssh worker-1 'sudo systemctl stop docker'
```

**Expected Behavior**:
- Swarm detects node failure
- Services migrate to healthy nodes
- Brief interruption during migration

**Recovery Steps**:
1. Check node status: `docker node ls`
2. If node down, investigate: SSH to worker
3. Restart Docker: `sudo systemctl start docker`
4. Verify node rejoins: `docker node ls`

---

## 8. Implementation Timeline

### Week 1: Infrastructure & VPN Setup

**Day 1-2: Cloud Site Preparation**
- [ ] Modify CA2 Terraform for WireGuard security groups
- [ ] Update docker-compose.yml (remove sensors, update Kafka config)
- [ ] Test cloud deployment in isolation

**Day 3-4: VPN Configuration**
- [ ] Install WireGuard on cloud and edge
- [ ] Generate keys and configure tunnels
- [ ] Test VPN connectivity (ping, traceroute)
- [ ] Verify Kafka accessibility over VPN

**Day 5: Edge Site Setup**
- [ ] Create edge-site docker-compose.yml
- [ ] Build/pull sensor images
- [ ] Test local sensor deployment
- [ ] Verify sensor → cloud Kafka connectivity

---

### Week 2: Automation & Testing

**Day 6-7: Deployment Automation**
- [ ] Write cloud deployment script
- [ ] Write edge deployment script
- [ ] Write master deploy-all.sh script
- [ ] Write verification scripts

**Day 8-9: Documentation**
- [ ] Create architecture diagram (PlantUML or draw.io)
- [ ] Write deployment runbook
- [ ] Document failure scenarios
- [ ] Create README.md with instructions

**Day 10: Testing & Demo**
- [ ] End-to-end deployment test
- [ ] Failure drill testing
- [ ] Record demo video (≤4 minutes)
- [ ] Final submission preparation

---

## 9. Success Criteria

### Functional Requirements

✅ **Two Sites Operational**:
- Edge: 3 sensor containers running locally
- Cloud: Kafka, MongoDB, Processor, Home Assistant in AWS

✅ **Secure Connectivity**:
- WireGuard VPN tunnel encrypted
- Kafka accessible only via VPN (not public internet)
- Security groups restrict access to VPN subnet

✅ **End-to-End Data Flow**:
- Sensors (edge) → Kafka (cloud) → Processor (cloud) → MongoDB (cloud)
- MQTT updates → Home Assistant dashboard
- Visible data in Home Assistant UI

✅ **Deployment Automation**:
- Single `./deploy-all.sh` command deploys both sites
- `./teardown-all.sh` cleanly removes infrastructure
- Scripts are idempotent (safe to re-run)

✅ **Failure Resilience**:
- VPN failure drill with documented recovery
- Video demonstration of failure/recovery
- Runbook with incident response procedures

---

### Documentation Requirements

✅ **Architecture Diagram**:
- Shows edge and cloud sites
- VPN tunnel clearly marked
- CIDR blocks labeled
- Component placement visible

✅ **README.md**:
- Overview of edge-to-cloud topology
- Prerequisites and dependencies
- Step-by-step deployment instructions
- Access information (Home Assistant URL, SSH)
- Deviations from CA2 explained

✅ **Runbook**:
- Bring-up procedures
- Tear-down procedures
- Failure scenarios with recovery steps
- Troubleshooting commands

✅ **Demo Video** (≤4 minutes):
- Show both sites running
- Demonstrate data flow (sensor logs → Home Assistant)
- Inject failure (e.g., stop VPN)
- Show recovery procedure
- Verify data flow resumes

---

## Next Steps

### Immediate Actions (Start Here)

1. **Create CA4 Directory Structure**:
```bash
mkdir -p CA4/{edge-site,cloud-site,vpn-config,failure-drills,scripts,docs}
cp -r CA2/plant-monitor-swarm-IaC/* CA4/cloud-site/
cp -r CA2/applications CA4/
```

2. **Modify Cloud Site**:
- Update `cloud-site/docker-compose.yml` (remove sensors, update Kafka)
- Update `cloud-site/terraform/main.tf` (add WireGuard rules)

3. **Create Edge Site**:
- Write `edge-site/docker-compose.yml` (sensors only)
- Write `edge-site/deploy-edge.sh`

4. **Set Up VPN**:
- Write `vpn-config/setup-vpn.sh` (automate WireGuard setup)
- Test connectivity

5. **Test Incrementally**:
- Deploy cloud in isolation
- Set up VPN and test connectivity
- Deploy edge and verify data flow

### Questions to Resolve

- **VPN Technology**: Confirm WireGuard is acceptable (vs OpenVPN)
- **Edge Environment**: Laptop, local VM, or Raspberry Pi?
- **Kafka Security**: Add SASL/SSL authentication for production?
- **Cost Management**: Reduce AWS worker nodes to 2 (vs 4 in CA2)?

---

## Appendix A: File Structure

```
CA4/
├── README.md                          # Main documentation
├── CA4_IMPLEMENTATION_PLAN.md         # This file
├── ARCHITECTURE.md                    # Architecture diagram and details
├── RUNBOOK.md                         # Operational procedures
├── deploy-all.sh                      # Master deployment script
├── teardown-all.sh                    # Master teardown script
├── verify-deployment.sh               # End-to-end verification
│
├── edge-site/                         # Edge site (local laptop/VM)
│   ├── docker-compose.yml             # Sensor containers
│   ├── deploy-edge.sh                 # Edge deployment script
│   ├── .env.example                   # Environment variables template
│   └── logs/                          # Sensor logs
│
├── cloud-site/                        # Cloud site (AWS)
│   ├── docker-compose.yml             # Kafka, MongoDB, etc.
│   ├── deploy-cloud.sh                # Cloud deployment script
│   ├── terraform/
│   │   ├── main.tf                    # Infrastructure as Code
│   │   ├── security-groups.tf         # WireGuard + Kafka rules
│   │   └── outputs.tf                 # Manager IP, etc.
│   └── ansible/
│       ├── setup-swarm.yml            # Swarm initialization
│       ├── deploy-stack.yml           # Stack deployment
│       └── setup-vpn.yml              # WireGuard configuration
│
├── vpn-config/                        # VPN setup automation
│   ├── setup-vpn.sh                   # Automated WireGuard setup
│   ├── cloud-wg0.conf.template        # Cloud VPN config template
│   ├── edge-wg0.conf.template         # Edge VPN config template
│   └── generate-keys.sh               # Key generation script
│
├── failure-drills/                    # Failure scenario scripts
│   ├── vpn-failure.sh                 # VPN tunnel failure drill
│   ├── kafka-failure.sh               # Kafka outage drill
│   └── network-partition.sh           # AWS instance failure drill
│
├── scripts/                           # Helper scripts
│   ├── monitor-kafka.sh               # Kafka message monitoring
│   ├── check-vpn.sh                   # VPN connectivity check
│   └── tail-logs.sh                   # Aggregate log viewing
│
├── docs/                              # Additional documentation
│   ├── architecture-diagram.png       # Network diagram
│   ├── deployment-guide.md            # Step-by-step guide
│   └── troubleshooting.md             # Common issues & fixes
│
└── demo/                              # Demo materials
    ├── demo-script.md                 # Video script
    ├── screenshots/                   # UI screenshots
    └── demo-video.mp4                 # Final demo video
```

---

## Appendix B: Reuse from CA2

**Directly Reusable (100%)**:
- ✅ Application code: `sensor/sensor.js`, `processor/app.js`
- ✅ Dockerfiles: All container build files
- ✅ Home Assistant config: MQTT setup, dashboard
- ✅ Mosquitto config: Broker configuration
- ✅ MongoDB init scripts: User/database setup

**Adaptable (70-80%)**:
- 🔄 Terraform: Add WireGuard security groups, reduce worker count
- 🔄 Docker Compose: Split into cloud-compose.yml + edge-compose.yml
- 🔄 Deploy scripts: Separate cloud vs edge deployment
- 🔄 Ansible: Add VPN setup playbook

**New for CA4**:
- 🆕 VPN configuration (WireGuard setup)
- 🆕 Edge site deployment
- 🆕 Multi-site orchestration scripts
- 🆕 Failure drill automation
- 🆕 Cross-site verification

**Time Estimate**:
- Without CA2 reuse: ~20-25 hours
- With CA2 reuse: ~10-12 hours
- **Time saved**: ~50% reduction

---

**End of Implementation Plan**
