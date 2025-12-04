# CA4 Architecture Summary

**Project**: Plant Monitoring System - Edge-to-Cloud Deployment  
**Topology**: Edge → Cloud (Multi-Site Hybrid)

---

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│                              CA4 MULTI-SITE ARCHITECTURE                            │
└────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────┐                      ┌─────────────────────────────┐
│      EDGE SITE (Local)      │                      │    CLOUD SITE (AWS)         │
│      Your Laptop/VM         │                      │    us-east-2                │
│                             │                      │                             │
│  Network: 192.168.1.0/24    │                      │  VPC: 10.0.0.0/16           │
│  VPN IP:  10.20.0.2         │                      │  VPN IP: 10.20.0.1          │
├─────────────────────────────┤                      ├─────────────────────────────┤
│                             │                      │                             │
│  ┌───────────────────────┐  │      WireGuard VPN   │  ┌───────────────────────┐  │
│  │ Docker Compose        │  │      (Encrypted)     │  │ Docker Swarm          │  │
│  │ (Bridge Network)      │  │                      │  │ (5-node cluster)      │  │
│  ├───────────────────────┤  │                      │  ├───────────────────────┤  │
│  │                       │  │                      │  │                       │  │
│  │ 🌱 Plant Sensors      │  │   ┌──────────────┐   │  │ Manager Node:         │  │
│  │   ├─ sensor-1         │──┼───│ UDP:51820    │───┼─→│  • ZooKeeper         │  │
│  │   │  Monstera         │  │   │ Encrypted    │   │  │  • Mosquitto (MQTT)  │  │
│  │   │  Office           │  │   │ Tunnel       │   │  │  • Home Assistant    │  │
│  │   │                   │  │   │              │   │  │  • Processor         │  │
│  │   ├─ sensor-2         │  │   │ 10.20.0.0/24 │   │  │  • WireGuard Gateway │  │
│  │   │  Sansevieria      │  │   │              │   │  │                       │  │
│  │   │  Living Room      │  │   └──────────────┘   │  │ Worker Nodes (2x):    │  │
│  │   │                   │  │                      │  │  • Kafka :9092        │  │
│  │   └─ sensor-3         │  │                      │  │  • MongoDB :27017     │  │
│  │      Monstera         │  │                      │  │                       │  │
│  │      Kitchen          │  │                      │  │ Overlay Network:      │  │
│  │                       │  │                      │  │  10.10.0.0/24         │  │
│  └───────────────────────┘  │                      │  │  (IPsec Encrypted)    │  │
│                             │                      │  └───────────────────────┘  │
│  Environment Config:        │                      │                             │
│  KAFKA_BROKERS=             │                      │  Public Access:             │
│    10.20.0.1:9092 ─────────┼──────────────────────┼─→ Port 8123 (Home Asst.)   │
│                             │                      │  Port 51820 (WireGuard)     │
└─────────────────────────────┘                      └─────────────────────────────┘

                                  DATA FLOW
                                  ─────────
    
    1. Sensors generate plant data (moisture, light, temp, humidity)
    2. Data sent to Kafka over VPN tunnel (10.20.0.1:9092)
    3. Processor consumes from Kafka
    4. Processor stores in MongoDB
    5. Processor publishes to MQTT
    6. Home Assistant subscribes to MQTT and displays dashboard
```

---

## Network Architecture

### IP Addressing Plan

| Network | CIDR | Purpose | Location |
|---------|------|---------|----------|
| **Edge Local Network** | 192.168.1.0/24 | Physical home/office network | Local |
| **VPN Overlay** | 10.20.0.0/24 | WireGuard tunnel network | Edge ↔ Cloud |
| **AWS VPC** | 10.0.0.0/16 | Cloud infrastructure | AWS |
| **AWS Public Subnet** | 10.0.1.0/24 | Manager node (public IP) | AWS |
| **AWS Private Subnet** | 10.0.2.0/24 | Worker nodes (private) | AWS |
| **Docker Overlay** | 10.10.0.0/24 | Swarm service mesh | Cloud only |

### VPN Tunnel Details

**Technology**: WireGuard (UDP port 51820)

**Endpoints**:
- **Cloud Gateway**: 10.20.0.1 (AWS Manager Node)
  - Public endpoint: `<AWS_MANAGER_IP>:51820`
  - Routes to Docker overlay: 10.10.0.0/24
  
- **Edge Client**: 10.20.0.2 (Local Laptop/VM)
  - Connects to cloud gateway
  - Accesses Kafka at 10.20.0.1:9092

**Encryption**: ChaCha20-Poly1305 (WireGuard default)

**NAT Traversal**: Persistent keepalive every 25 seconds

---

## Service Distribution

### Edge Site Services (Local Docker Compose)

| Service | Container | CPU | Memory | Purpose |
|---------|-----------|-----|--------|---------|
| sensor-1 | edge-sensor-1 | 0.1 core | 128M | Monstera data producer |
| sensor-2 | edge-sensor-2 | 0.1 core | 128M | Sansevieria data producer |
| sensor-3 | edge-sensor-3 | 0.1 core | 128M | Monstera data producer |

**Total Resources**: ~0.3 CPU cores, 384M RAM (easily runs on laptop)

### Cloud Site Services (AWS Docker Swarm)

| Service | Node Type | Replicas | Memory | Purpose |
|---------|-----------|----------|--------|---------|
| ZooKeeper | Manager | 1 | 256M | Kafka coordination |
| Kafka | Worker | 1 | 512M | Message broker |
| MongoDB | Worker | 1 | 512M | Data persistence |
| Processor | Manager | 1 | 512M | ETL pipeline |
| Mosquitto | Manager | 1 | 128M | MQTT broker |
| Home Assistant | Manager | 1 | 512M | Dashboard UI |

**Total Resources**: ~2.4GB RAM, 3 EC2 instances (1 manager + 2 workers)

---

## Data Flow Sequence

```
┌─────────┐     ┌─────────┐     ┌──────────┐     ┌─────────┐     ┌──────────┐
│ Sensor  │────→│   VPN   │────→│  Kafka   │────→│Process. │────→│ MongoDB  │
│ (Edge)  │     │ Tunnel  │     │ (Cloud)  │     │ (Cloud) │     │ (Cloud)  │
└─────────┘     └─────────┘     └──────────┘     └─────────┘     └──────────┘
                                                       │
                                                       ↓
                                                 ┌──────────┐     ┌──────────┐
                                                 │   MQTT   │────→│   Home   │
                                                 │(Mosquitto│     │Assistant │
                                                 └──────────┘     └──────────┘
```

**Step-by-Step**:

1. **Data Generation** (Edge)
   - Sensors simulate plant conditions every 30 seconds
   - Generate JSON: `{plantId, location, sensors: {moisture, light, temp, humidity}}`

2. **Transport** (VPN)
   - Sensor connects to Kafka at `10.20.0.1:9092`
   - Traffic encrypted by WireGuard tunnel
   - Travels through internet to AWS

3. **Ingestion** (Cloud - Kafka)
   - Kafka receives message on `plant-sensors` topic
   - Message persisted to disk (in case of processor failure)

4. **Processing** (Cloud - Processor)
   - Consumes from Kafka
   - Enriches data (calculates health score)
   - Writes to MongoDB `sensor_readings` collection

5. **Publishing** (Cloud - MQTT)
   - Processor publishes to MQTT topic: `homeassistant/sensor/plant-{id}/state`
   - Home Assistant auto-discovers sensors

6. **Visualization** (Cloud - Home Assistant)
   - Displays live sensor data on dashboard
   - Accessible at `http://<AWS_MANAGER_IP>:8123`

---

## Security Architecture

### Network Security

**Firewall Rules** (AWS Security Groups):

```
Manager Node (Public):
  Inbound:
    - SSH (22):        <Your IP>/32 only
    - Home Asst (8123): 0.0.0.0/0 (public dashboard)
    - WireGuard (51820/udp): 0.0.0.0/0 (or edge IP only)
    - Swarm (2377/tcp): VPC CIDR only
    - Docker overlay (7946, 4789): VPC CIDR only

Worker Nodes (Private):
    - Kafka (9092):     10.20.0.0/24 (VPN subnet only)
    - MongoDB (27017):  10.10.0.0/24 (overlay only)
    - Docker overlay:   VPC CIDR only
    - NO public IPs
```

### Encryption Layers

1. **Transport Encryption**: WireGuard VPN (ChaCha20-Poly1305)
2. **Overlay Encryption**: Docker Swarm overlay network (IPsec)
3. **Application Layer**: MongoDB/Kafka can add TLS (optional for CA4)

### Secrets Management

- **MongoDB credentials**: Docker secrets (encrypted at rest)
- **WireGuard keys**: File-based, 600 permissions
- **MQTT passwords**: Docker secrets

---

## Failure Modes & Recovery

### 1. VPN Tunnel Failure

**Symptoms**:
- Edge sensors: "Connection refused to 10.20.0.1:9092"
- No new data in MongoDB
- Home Assistant shows stale data

**Recovery**:
```bash
# On cloud
sudo wg-quick down wg0 && sudo wg-quick up wg0

# On edge
sudo wg-quick down wg0 && sudo wg-quick up wg0

# Verify
ping 10.20.0.1  # from edge
ping 10.20.0.2  # from cloud
```

---

### 2. Kafka Service Down

**Symptoms**:
- Edge sensors: "Broker not available"
- Processor stops consuming
- MongoDB no new inserts

**Recovery**:
```bash
# Check Kafka status
docker service ls | grep kafka

# Scale up if 0/1
docker service scale plant-monitoring_kafka=1

# Verify
docker service logs plant-monitoring_kafka -f
```

---

### 3. Network Partition (AWS Instance Failure)

**Symptoms**:
- Worker node unreachable
- Services migrate to healthy nodes
- Brief data flow interruption

**Recovery**:
```bash
# Check node status
docker node ls

# If node down, SSH to worker
ssh worker-1 'sudo systemctl start docker'

# Verify rejoin
docker node ls
```

---

## Technology Stack

### Edge Site
- **OS**: Ubuntu 22.04 / macOS / Windows (with Docker)
- **Container Runtime**: Docker Engine 20.10+
- **Orchestration**: Docker Compose v3.8
- **VPN Client**: WireGuard
- **Language**: Node.js 18 (sensor application)

### Cloud Site
- **Cloud Provider**: AWS (us-east-2)
- **Compute**: EC2 t2.micro (3 instances)
- **OS**: Ubuntu 22.04 LTS
- **Container Runtime**: Docker Engine 20.10+
- **Orchestration**: Docker Swarm
- **VPN Gateway**: WireGuard
- **IaC**: Terraform 1.3+
- **Config Mgmt**: Ansible 2.14+

### Applications
- **Message Broker**: Apache Kafka 7.4.0
- **Database**: MongoDB 6.0.4
- **MQTT Broker**: Eclipse Mosquitto 2.0
- **Dashboard**: Home Assistant 2023.8.0
- **Processing**: Node.js 18 custom app

---

## Deployment Automation

### Scripts Overview

```
CA4/
├── deploy-all.sh              # Master deployment (cloud + VPN + edge)
├── teardown-all.sh            # Complete teardown
├── verify-deployment.sh       # End-to-end verification
│
├── cloud-site/
│   ├── deploy-cloud.sh        # Deploy AWS infrastructure + Swarm
│   └── teardown-cloud.sh      # Remove cloud resources
│
├── vpn-config/
│   ├── setup-vpn.sh           # Automated WireGuard setup
│   └── generate-keys.sh       # VPN key generation
│
└── edge-site/
    ├── deploy-edge.sh         # Deploy local sensors
    └── teardown-edge.sh       # Stop local sensors
```

### Deployment Order

1. **Cloud Site First**: Deploy Kafka, MongoDB, etc. to AWS
2. **VPN Next**: Establish tunnel between cloud and edge
3. **Edge Last**: Deploy sensors pointing to cloud Kafka

**Rationale**: Must have Kafka running before sensors try to connect

---

## Monitoring & Observability

### Key Metrics to Track

**Edge Site**:
- Sensor container status (up/down)
- Kafka connection errors
- VPN tunnel status

**Cloud Site**:
- Kafka message rate (messages/sec)
- MongoDB insert rate (docs/sec)
- Home Assistant update frequency
- VPN peer connectivity

### Monitoring Commands

```bash
# Edge: Check sensor logs
docker-compose logs -f

# Cloud: Check Kafka message count
docker exec <kafka-container> kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group plant-processor-group \
  --describe

# Cloud: Check MongoDB document count
docker exec <mongodb-container> mongosh \
  -u admin -p <password> \
  --eval "db.sensor_readings.countDocuments()"

# VPN: Check tunnel status
sudo wg show
```

---

## Comparison: CA2 vs CA4

| Aspect | CA2 (Single-Site) | CA4 (Multi-Site) |
|--------|-------------------|------------------|
| **Deployment Sites** | 1 (AWS only) | 2 (Edge + Cloud) |
| **Sensor Location** | AWS workers | Local edge |
| **Network Topology** | Single overlay | VPN + overlay |
| **VPN Required** | No | Yes (WireGuard) |
| **Kafka Access** | Internal only | VPN tunnel |
| **Complexity** | Medium | High |
| **Realism** | Lab setup | Production-like IoT |
| **AWS Resources** | 5 EC2 instances | 3 EC2 instances |
| **Cost** | Higher | Lower (fewer instances) |
| **Code Reuse from CA2** | N/A | 70-80% |

---

## Success Criteria Checklist

### Functional Requirements

- [ ] **Two sites operational**
  - [ ] Edge: 3 sensor containers running
  - [ ] Cloud: Kafka, MongoDB, Processor, Home Assistant running

- [ ] **Secure connectivity established**
  - [ ] WireGuard VPN tunnel active
  - [ ] Kafka accessible only via VPN (not public)
  - [ ] Security groups properly configured

- [ ] **End-to-end data flow**
  - [ ] Sensors → Kafka → Processor → MongoDB → MQTT → Home Assistant
  - [ ] Visible data in Home Assistant dashboard
  - [ ] MongoDB contains sensor readings

- [ ] **Deployment automation**
  - [ ] Single `./deploy-all.sh` command works
  - [ ] Scripts are idempotent (safe to re-run)
  - [ ] Clean teardown with `./teardown-all.sh`

- [ ] **Failure resilience**
  - [ ] VPN failure drill completed
  - [ ] Recovery procedures documented
  - [ ] Video demonstration recorded (≤4 min)

---

## Next Steps

1. **Review this architecture** - Ensure you understand all components
2. **Read implementation plan** - `CA4_IMPLEMENTATION_PLAN.md` for detailed steps
3. **Set up project structure** - Create directories for edge/cloud/vpn
4. **Start with cloud site** - Modify CA2 infrastructure first
5. **Add VPN layer** - Test connectivity before adding edge
6. **Deploy edge site** - Complete the architecture
7. **Test failure scenarios** - Demonstrate resilience
8. **Document and record** - Create deliverables

---

**Good luck with your implementation!** 🚀
