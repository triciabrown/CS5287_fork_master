# CA4 Implementation Progress

**Date Started**: November 23, 2025  
**Last Updated**: November 23, 2025  
**Status**: Phase 2 Complete - VPN & Edge Configured  
**Next**: Deployment Testing

---

## ✅ Completed Tasks

### 1. Planning & Documentation
- ✅ Created `VPN_TECHNOLOGY_DECISION.md` - WireGuard vs ZeroTier analysis
- ✅ Created `CA2_FEEDBACK_IMPROVEMENTS.md` - Addressing grader feedback
- ✅ Created `CA4_IMPLEMENTATION_PLAN.md` - Complete implementation guide
- ✅ Created `ARCHITECTURE_SUMMARY.md` - Visual architecture reference
- ✅ Created `START_HERE.md` - Quick start guide

### 2. Directory Structure
```
CA4/
├── cloud-site/              ✅ Copied from CA2
├── edge-site/               ✅ Created (empty, ready for config)
├── vpn-config/              ✅ Created (ready for WireGuard templates)
├── failure-drills/          ✅ Created (ready for drill scripts)
├── scripts/                 ✅ Created (ready for monitoring scripts)
├── docs/                    ✅ Created (ready for diagrams)
├── demo/screenshots/        ✅ Created (ready for demo materials)
└── applications/            ✅ Copied from CA2
```

### 3. Cloud Site Modifications

**File Created**: `cloud-site/docker-compose-ca4.yml`

**Key Improvements**:

#### Network Segmentation (CA2 Feedback +4 points)
```yaml
networks:
  frontend-net:    # 10.10.1.0/24 - Home Assistant ONLY
  messaging-net:   # 10.10.2.0/24 - Kafka, ZooKeeper
  data-net:        # 10.10.3.0/24 - MongoDB, Processor, Mosquitto
```

**Service Network Assignments**:
| Service | Frontend | Messaging | Data | Security Improvement |
|---------|----------|-----------|------|---------------------|
| Home Assistant | ✅ | ❌ | ❌ | Cannot access Kafka/MongoDB |
| Mosquitto | ✅ | ❌ | ✅ | Bridges frontend ↔ data |
| Processor | ❌ | ✅ | ✅ | Bridges messaging ↔ data |
| Kafka | ❌ | ✅ | ❌ | Isolated from frontend |
| MongoDB | ❌ | ❌ | ✅ | Isolated from frontend & messaging |

**Result**: Lateral movement restricted, principle of least privilege enforced

---

#### Kafka VPN Configuration
```yaml
kafka:
  environment:
    # Dual listeners: internal + external (VPN)
    KAFKA_ADVERTISED_LISTENERS: 'INTERNAL://kafka:9092,EXTERNAL://10.20.0.1:9092'
    KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: 'INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT'
  ports:
    - "9092:9092"  # Exposed for VPN (secured by security group)
```

**Result**: Edge sensors can access Kafka via VPN, cloud services use internal listener

---

#### Processor Scaling Preparation (CA2 Feedback +3 points)
```yaml
processor:
  deploy:
    replicas: 1  # Default (can scale to 3 for tests)
    labels:
      SERVICE_SCALABLE: "true"  # Marked for scaling tests
```

**Result**: Ready for scaling tests with Kafka lag/latency measurements

---

#### Sensor Removal (Edge Migration)
```yaml
# CA4 NOTE: Sensor service REMOVED - now running at edge site
```

**Result**: Sensors will run locally at edge, not in AWS

---

## 📋 Next Steps (In Order)

### ✅ Phase 2: VPN Configuration (COMPLETE)

#### ✅ Step 1: WireGuard Templates Created
**Files Created**:
- ✅ `vpn-config/cloud-wg0.conf.template` - Cloud VPN gateway config
- ✅ `vpn-config/edge-wg0.conf.template` - Edge VPN client config
- ✅ `vpn-config/generate-keys.sh` - WireGuard key pair generation
- ✅ `vpn-config/setup-vpn.sh` - Automated VPN deployment script
- ✅ `vpn-config/.gitignore` - Protect private keys from version control

**Features**:
- Cloud gateway: 10.20.0.1/24, listens on UDP 51820
- Edge client: 10.20.0.2/24, connects to AWS manager
- Automatic iptables rules for routing and NAT
- Persistent keepalive (25s) for NAT traversal
- Parameterized templates with placeholder substitution

---

#### ✅ Step 2: Terraform Security Groups Updated
**File Modified**: `cloud-site/terraform/main.tf`

**Changes Made**:
```hcl
# WireGuard VPN ingress (UDP 51820)
ingress {
  from_port   = 51820
  to_port     = 51820
  protocol    = "udp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "WireGuard VPN for edge site connectivity"
}

# Kafka access ONLY from VPN subnet
ingress {
  from_port   = 9092
  to_port     = 9092
  protocol    = "tcp"
  cidr_blocks = ["10.20.0.0/24"]  # VPN-only!
  description = "Kafka external listener (VPN clients only)"
}
```

**Security Enhancement**: Kafka 9092 restricted to VPN subnet (10.20.0.0/24), not public internet

---

### ✅ Phase 3: Edge Site Configuration (COMPLETE)

#### ✅ Step 1: Edge Docker Compose Created
**File Created**: `edge-site/docker-compose.yml`

**Configuration**:
- 3 sensor services: tomato, basil, lettuce
- Sensor IDs: `edge-sensor-001`, `edge-sensor-002`, `edge-sensor-003`
- Kafka broker: `10.20.0.1:9092` (cloud via VPN)
- Local bridge network: `172.30.0.0/24`
- Different plant profiles (temp, humidity, soil, light ranges)

---

#### ✅ Step 2: Edge Deployment Script Created
**File Created**: `edge-site/deploy-edge.sh`

**Features**:
- Pre-deployment checks:
  - ✅ WireGuard interface `wg0` exists
  - ✅ VPN IP `10.20.0.2` assigned
  - ✅ Cloud VPN gateway reachable (ping test)
  - ✅ Kafka connectivity via VPN (TCP test)
- Docker & docker-compose validation
- Pull images, deploy sensors, verify health
- Log analysis for connectivity issues
- Cleanup mode: `./deploy-edge.sh cleanup`

---

### ✅ Phase 4: Deployment Automation (COMPLETE)

**Files Created**:
- ✅ `scripts/deploy-all.sh` - Master orchestration (cloud + VPN + edge)
- ✅ `scripts/verify-deployment.sh` - Comprehensive verification suite

#### deploy-all.sh Features:
```bash
# Full deployment
./deploy-all.sh deploy          # Cloud + VPN + Edge

# Individual phases
./deploy-all.sh cloud           # Cloud infrastructure only
./deploy-all.sh vpn             # VPN setup only
./deploy-all.sh edge            # Edge sensors only

# Verification & cleanup
./deploy-all.sh verify          # Run verification tests
./deploy-all.sh cleanup         # Destroy everything

# Options
--skip-terraform               # Use existing infrastructure
--no-cloud / --no-vpn / --no-edge
```

**Automation Features**:
- ✅ Terraform init, plan, apply
- ✅ Docker Swarm initialization
- ✅ Worker node joining
- ✅ Stack deployment
- ✅ VPN key generation & configuration
- ✅ SSH-based VPN deployment (cloud & edge)
- ✅ Connectivity verification
- ✅ Color-coded output & progress indicators

---

#### verify-deployment.sh Features:
**Comprehensive Test Suites**:
1. **Cloud Infrastructure Tests**
   - Manager SSH connectivity
   - Swarm cluster status (5 nodes)
   - Service deployment (home-assistant, kafka, zookeeper, mongodb, processor)
   - Service replica health

2. **VPN Connectivity Tests**
   - WireGuard installation & interface
   - Edge VPN IP assignment (10.20.0.2)
   - Cloud gateway reachability (ping 10.20.0.1)
   - Kafka TCP connectivity via VPN

3. **Edge Deployment Tests**
   - Docker availability
   - 3 sensors running (plant-sensor-1/2/3)
   - Sensor log error checking
   - Edge network existence

4. **Network Architecture Tests**
   - 3-tier overlay networks (frontend, messaging, data)
   - Network segmentation verification
   - Home Assistant isolation check

5. **End-to-End Tests**
   - Kafka topic creation (`plant-sensors`)
   - MongoDB database (`plant_monitoring`)
   - Home Assistant UI accessibility (port 8123)

6. **Security Tests**
   - WireGuard ChaCha20Poly1305 encryption
   - Private key file permissions (600)
   - .gitignore effectiveness

**Output**:
- Color-coded pass/fail/warning results
- Success rate calculation
- Component status dashboard
- Exit code 0 (all pass) or 1 (failures)

---

### Phase 5: Failure Drills (NEXT PRIORITY)

#### Step 1: Create WireGuard Templates
**Files to Create**:
- `vpn-config/cloud-wg0.conf.template`
- `vpn-config/edge-wg0.conf.template`
- `vpn-config/generate-keys.sh`
- `vpn-config/setup-vpn.sh`

**Template Example** (cloud-wg0.conf.template):
```bash
[Interface]
Address = 10.20.0.1/24
PrivateKey = {{CLOUD_PRIVATE_KEY}}
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = {{EDGE_PUBLIC_KEY}}
AllowedIPs = 10.20.0.2/32
PersistentKeepalive = 25
```

---

#### Step 2: Update Terraform Security Groups
**File to Modify**: `cloud-site/terraform/main.tf`

**Add**:
```hcl
# WireGuard VPN ingress
resource "aws_security_group_rule" "wireguard_vpn" {
  type              = "ingress"
  from_port         = 51820
  to_port           = 51820
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]  # Or restrict to edge IP
  security_group_id = aws_security_group.swarm_manager_sg.id
  description       = "WireGuard VPN for edge-to-cloud connectivity"
}

# Kafka access ONLY from VPN subnet
resource "aws_security_group_rule" "kafka_vpn_only" {
  type              = "ingress"
  from_port         = 9092
  to_port           = 9092
  protocol          = "tcp"
  cidr_blocks       = ["10.20.0.0/24"]  # VPN subnet ONLY
  security_group_id = aws_security_group.swarm_worker_sg.id
  description       = "Kafka accessible ONLY via VPN"
}
```

---

### Phase 3: Edge Site Configuration

#### Step 1: Create Edge Docker Compose
**File to Create**: `edge-site/docker-compose.yml`

```yaml
version: '3.8'

services:
  sensor-1:
    image: docker.io/triciab221/plant-sensor:v1.0.0
    environment:
      KAFKA_BROKERS: '10.20.0.1:9092'  # Cloud Kafka via VPN
      PLANT_ID: 'plant-edge-001'
      PLANT_TYPE: 'monstera'
      LOCATION: 'Edge Site - Office'
  
  sensor-2:
    # ...similar config...
  
  sensor-3:
    # ...similar config...
```

---

#### Step 2: Create Edge Deployment Script
**File to Create**: `edge-site/deploy-edge.sh`

```bash
#!/bin/bash
# Check VPN connectivity
ping -c 3 10.20.0.1 || { echo "VPN down"; exit 1; }

# Check Kafka accessibility
timeout 5 bash -c "cat < /dev/null > /dev/tcp/10.20.0.1/9092" || { echo "Kafka unreachable"; exit 1; }

# Deploy sensors
docker-compose up -d
```

---

### Phase 4: Deployment Automation

**Files to Create**:
- `deploy-all.sh` - Master deployment (cloud + VPN + edge)
- `cloud-site/deploy-cloud.sh` - Cloud deployment with VPN setup
- `verify-deployment.sh` - End-to-end verification
- `teardown-all.sh` - Complete teardown

---

### Phase 5: Failure Drills

**Files to Create**:
- `failure-drills/vpn-failure.sh` - VPN tunnel failure + recovery
- `failure-drills/kafka-failure.sh` - Kafka outage + recovery
- `failure-drills/network-partition.sh` - AWS instance failure

---

### Phase 6: Observability & Scaling

**Files to Create**:
- `scripts/measure-processor-performance.sh` - Kafka lag, latency, throughput
- `scripts/processor-scaling-test.sh` - Automated 1→3→1 replica test
- `scripts/monitor-metrics.sh` - Real-time monitoring dashboard

---

### Phase 7: Documentation & Demo

**Files to Create**:
- `CA4/README.md` - Main documentation
- `CA4/RUNBOOK.md` - Operational procedures
- `docs/architecture-diagram.png` - Network diagram
- `demo/demo-script.md` - Video script
- Record demo video (≤4 minutes)

---

## 🎯 Grading Target

| Category | CA2 | CA4 Target | Improvement |
|----------|-----|------------|-------------|
| Security & Isolation | 16/20 | 20/20 | +4 (network segmentation) |
| Scaling & Observability | 17/20 | 20/20 | +3 (processor scaling) |
| Connectivity & Security | N/A | 20/20 | New (VPN setup) |
| **TOTAL** | 93/100 | **100/100** | **+7 points** |

---

## 📊 Implementation Timeline

**Estimated Total**: 10-12 days

- ✅ **Days 1-2**: Planning & directory structure (COMPLETE)
- ✅ **Days 3-4**: VPN configuration (COMPLETE)
- ✅ **Day 5**: Edge site setup (COMPLETE)
- ✅ **Days 6-7**: Deployment automation (COMPLETE)
- ⏳ **Days 8-9**: Failure drills & observability (NEXT)
- ⏳ **Days 10-12**: Documentation & demo

**Current Progress**: 65% complete (7/10 days)

---

## 🚀 Ready for Next Phase: Deployment Testing

**Status**: Core infrastructure complete - ready for deployment and testing

### What You Have Now:
1. ✅ **Cloud Infrastructure**: Modified Terraform with VPN security groups
2. ✅ **VPN Configuration**: Complete WireGuard templates and automation
3. ✅ **Edge Configuration**: 3-sensor setup with VPN connectivity checks
4. ✅ **Deployment Automation**: One-command deployment script
5. ✅ **Verification Suite**: Comprehensive testing framework

### Next Actions (In Order):

#### Option A: Full Deployment Test
```bash
cd /home/tricia/dev/CS5287_fork_master/CA4/scripts
./deploy-all.sh deploy
```
This will:
1. Deploy AWS infrastructure (Terraform)
2. Initialize Docker Swarm cluster
3. Deploy cloud services (Kafka, MongoDB, etc.)
4. Configure VPN (cloud + edge)
5. Deploy edge sensors
6. Run verification tests

#### Option B: Manual Step-by-Step
```bash
# 1. Deploy cloud
./deploy-all.sh cloud

# 2. Setup VPN
./deploy-all.sh vpn

# 3. Deploy edge
./deploy-all.sh edge

# 4. Verify
./deploy-all.sh verify
```

#### Option C: Continue Implementation
Before deploying, we can create:
- Failure drill scripts (VPN/Kafka/network failures)
- Processor scaling test automation
- Monitoring/metrics dashboard
- Architecture diagrams
- README documentation

### Recommended Workflow:
1. **First**: Create failure drills & scaling tests (will need them for demo)
2. **Then**: Deploy and test (to verify everything works)
3. **Finally**: Documentation, screenshots, video

**Would you like to**:
- A) Proceed with deployment testing now?
- B) Create failure drill scripts first?
- C) Create scaling test automation?
- D) Something else?
