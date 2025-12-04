# CA4: Edge-to-Cloud IoT System with VPN

**Course**: CS5287 - Cloud Computing  
**Assignment**: CA4 - Edge-to-Cloud Plant Monitoring System  
**Student**: Tricia Brown  
**Date**: November 23, 2025

---

## 📋 Assignment Overview

This assignment implements a complete edge-to-cloud IoT architecture for the plant monitoring system, addressing feedback from CA2 and CA3:

### Grading Rubric (100 points total)

#### 1. System Architecture & Design (20 points)
- **Network Segmentation** (8 pts): Multi-tier overlay networks (frontend, messaging, data)
- **VPN Implementation** (8 pts): WireGuard VPN connecting edge sensors to cloud Kafka
- **Edge Site Configuration** (4 pts): Sensors running at edge, not in cloud

#### 2. Security & Isolation (20 points)
- **Network Isolation** (8 pts): Services cannot cross network boundaries
- **Secrets Management** (6 pts): All credentials via Docker secrets (no hardcoded passwords)
- **VPN Security** (6 pts): Kafka only accessible via VPN (AWS security group enforcement)

#### 3. Deployment Automation (20 points)
- **Infrastructure as Code** (8 pts): Terraform for AWS resources
- **Docker Swarm Orchestration** (6 pts): Automated swarm initialization and service deployment
- **VPN Automation** (6 pts): Automated WireGuard key generation and config deployment

#### 4. Observability & Monitoring (15 points)
- **Service Health** (5 pts): Docker service status monitoring
- **VPN Connectivity** (5 pts): End-to-end connectivity verification
- **Data Flow** (5 pts): Sensor → Kafka → Processor → MongoDB → Home Assistant

#### 5. Resilience & Testing (15 points)
- **Failure Drills** (10 pts): VPN failure, Kafka failure, network partition scenarios
- **Recovery Procedures** (5 pts): Automated recovery verification

#### 6. Scaling Demonstration (10 points)
- **Processor Scaling** (5 pts): Scale 1→3→1 replicas
- **Performance Metrics** (5 pts): Kafka lag, throughput, latency measurements

---

## 🎯 Key Improvements from CA2/CA3

### From CA2 Feedback
1. ✅ **Network Segmentation** (+4 pts Security): 3-tier network architecture
2. ✅ **Service Isolation** (+4 pts Security): Home Assistant cannot access Kafka/MongoDB
3. ✅ **Processor Scaling** (+3 pts Observability): Configured for horizontal scaling

### From CA3 Feedback
1. ✅ **Security Hardening**: All credentials via Docker secrets
2. ✅ **Automated Deployment**: Single command deployment with verification
3. ✅ **Edge Architecture**: Sensors moved from cloud to edge site

---

## 🏗️ Architecture

### Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                         EDGE SITE (Local)                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Sensor 001   Sensor 002   Sensor 003                    │  │
│  │     │             │             │                         │  │
│  │     └─────────────┴─────────────┘                         │  │
│  │              WireGuard VPN (10.20.0.2)                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                    VPN Tunnel (UDP 51820)
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      CLOUD SITE (AWS)                            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         WireGuard Gateway (10.20.0.1)                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          FRONTEND TIER (10.10.1.0/24)                    │  │
│  │              Home Assistant (Public: 8123)                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          MESSAGING TIER (10.10.2.0/24)                   │  │
│  │         Kafka (VPN: 10.20.0.1:9092)                      │  │
│  │              ZooKeeper                                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │            DATA TIER (10.10.3.0/24)                      │  │
│  │         MongoDB    Processor    Mosquitto                 │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Service Placement

| Service | Tier | Networks | Public Access |
|---------|------|----------|---------------|
| Home Assistant | Frontend | frontend-net | ✅ Port 8123 |
| Kafka | Messaging | messaging-net | ❌ VPN only (10.20.0.0/24) |
| ZooKeeper | Messaging | messaging-net | ❌ Internal only |
| MongoDB | Data | data-net | ❌ Internal only |
| Mosquitto | Data/Frontend | data-net, frontend-net | ❌ Internal only |
| Processor | Data/Messaging | data-net, messaging-net | ❌ Internal only |

---

## 📦 Prerequisites

### System Requirements

1. **Local Machine**
   - Ubuntu 20.04+ or similar Linux distribution
   - Sudo access for WireGuard installation
   - Docker & Docker Compose installed
   - 4GB RAM minimum, 8GB recommended

2. **AWS Account**
   - Valid AWS credentials configured (`~/.aws/credentials`)
   - EC2 permissions for launching instances
   - VPC/Networking permissions
   - Default region: us-east-2 (configurable)

3. **Software Dependencies**
   ```bash
   # Terraform (v1.0+)
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   
   # WireGuard (for VPN)
   sudo apt update
   sudo apt install -y wireguard wireguard-tools
   
   # jq (for JSON parsing)
   sudo apt install -y jq
   ```

4. **SSH Key**
   - SSH key pair: `~/.ssh/docker-swarm-key`
   - Generate if needed:
     ```bash
     ssh-keygen -t rsa -b 4096 -f ~/.ssh/docker-swarm-key -N ""
     ```

5. **Network Access**
   - Outbound internet access for package downloads
   - AWS security groups will be configured automatically
   - UDP port 51820 allowed for WireGuard (configured by Terraform)

---

## 🚀 Quick Start Deployment

### Option 1: Full Automated Deployment

Deploy everything (cloud + VPN + edge) with a single command:

```bash
cd CA4/scripts
./deploy-all.sh deploy
```

This will:
1. ✅ Deploy AWS infrastructure with Terraform (5 EC2 instances)
2. ✅ Initialize Docker Swarm cluster (1 manager + 4 workers)
3. ✅ Deploy cloud services (Kafka, MongoDB, Home Assistant, etc.)
4. ✅ Generate WireGuard VPN keys
5. ✅ Configure VPN on cloud and edge
6. ✅ Deploy edge sensors
7. ✅ Verify end-to-end connectivity

**Estimated Time**: 10-15 minutes

---

### Option 2: Step-by-Step Deployment

For more control, deploy in phases:

#### Phase 1: Cloud Infrastructure

```bash
cd CA4/scripts
./deploy-all.sh cloud
```

**What it does**:
- Creates AWS VPC, subnets, NAT gateway, security groups
- Launches 5 EC2 instances (t2.medium)
- Initializes Docker Swarm cluster
- Deploys 6 cloud services
- Verifies MongoDB user creation
- Saves manager IP to `.manager-ip` file

**Verify**:
```bash
# Check service status
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat ../. manager-ip) 'sudo docker service ls'

# All services should show 1/1 replicas
```

#### Phase 2: VPN Configuration

```bash
cd CA4/scripts
./deploy-all.sh vpn
```

**What it does**:
- Generates WireGuard public/private key pairs
- Creates VPN configs from templates
- Deploys VPN to cloud (AWS manager node)
- Prompts to deploy VPN to edge (your local machine)
- Tests VPN connectivity (ping 10.20.0.1)

**Verify**:
```bash
# Check VPN status
sudo wg show

# Test cloud gateway
ping -c 3 10.20.0.1

# Test Kafka access
telnet 10.20.0.1 9092
```

#### Phase 3: Edge Sensors

```bash
cd CA4/scripts
./deploy-all.sh edge
```

**What it does**:
- Verifies VPN connectivity to cloud
- Deploys 3 sensor containers via Docker Compose
- Starts publishing data to Kafka (via VPN)

**Verify**:
```bash
# Check sensors running
cd ../edge-site
docker compose ps

# Should show 3 containers (plant-sensor-001, 002, 003) running
```

---

## 🔍 Verification & Testing

### 1. Service Health Check

```bash
cd CA4/scripts
./deploy-all.sh verify
```

Checks:
- ✅ Cloud services (6/6 running)
- ✅ VPN status (wg0 up and running)
- ✅ Edge sensors (3/3 running)
- ✅ Network connectivity (ping tests)
- ✅ Kafka connectivity (port 9092 accessible)

### 2. End-to-End Data Flow

```bash
# View processor logs (should show data processing)
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service logs --tail 50 plant-monitoring_processor'

# Check MongoDB for sensor data
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker exec $(sudo docker ps -qf name=mongodb) mongosh plant_monitoring --eval "db.sensor_data.countDocuments()"'

# Access Home Assistant dashboard
# Open browser: http://<MANAGER_IP>:8123
```

### 3. VPN Connectivity Tests

```bash
# From edge: Ping cloud gateway
ping -c 3 10.20.0.1

# From edge: Test Kafka port
nc -zv 10.20.0.1 9092

# From cloud: Check VPN peers
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) 'sudo wg show'
```

---

## 🧪 Failure Drills & Resilience Tests

This assignment includes comprehensive failure resilience testing to validate system behavior under various failure conditions. All tests have been executed and validated.

### Available Failure Drills

Three automated failure drill scripts are provided in `failure-drills/`:

| Drill | Script | Purpose | Test Results |
|-------|--------|---------|--------------|
| **VPN Failure** | [`vpn-failure.sh`](failure-drills/vpn-failure.sh) | Simulates VPN tunnel failure between edge and cloud | [`vpn-failure-drill.log`](failure-drills/vpn-failure-drill.log) |
| **Kafka Failure** | [`kafka-failure.sh`](failure-drills/kafka-failure.sh) | Simulates Kafka broker failure by scaling service to 0 | [`kafka-failure-drill.log`](failure-drills/kafka-failure-drill.log) |
| **Network Partition** | [`network-partition.sh`](failure-drills/network-partition.sh) | Simulates network partition using iptables rules | [`network-partition-drill.log`](failure-drills/network-partition-drill.log) |

### Run Failure Drills

```bash
cd CA4/failure-drills

# Test VPN failure and recovery
./vpn-failure.sh

# Test Kafka broker failure
./kafka-failure.sh

# Test network partition
./network-partition.sh
```

Each drill:
1. **Pre-flight checks** - Verifies system is healthy before test
2. **Baseline capture** - Records normal operating metrics
3. **Failure injection** - Introduces specific failure condition
4. **Observation period** - Monitors system behavior for 30 seconds
5. **Recovery** - Restores normal operation
6. **Verification** - Confirms full recovery and data flow
7. **Results report** - Generates detailed log file with timestamps and metrics

**Test Results Summary**:
- ✅ **VPN Failure**: Sensors detect connectivity loss, buffer data locally, automatically reconnect when VPN restored, no data loss
- ✅ **Kafka Failure**: Processor logs connection errors, retries with exponential backoff, reconnects after Kafka restart, consumer group rebalances successfully
- ✅ **Network Partition**: iptables DROP rules isolate edge from cloud, sensors unable to publish, rules removed successfully, connectivity restored, end-to-end flow resumes

For detailed test execution logs, see the `*-drill.log` files in `failure-drills/`. For implementation details and troubleshooting, see [`failure-drills/README.md`](failure-drills/README.md).

### Operations Runbook

Comprehensive incident response procedures are documented in [`RUNBOOK.md`](RUNBOOK.md), including:

- **Standard Operations**: Daily health checks, deployment procedures, shutdown procedures
- **Incident Response**: Step-by-step recovery for VPN failure, Kafka failure, network partition, processor failure, MongoDB issues, and sensor failures
- **Troubleshooting Guide**: Common issues and solutions
- **Emergency Procedures**: Contact information and escalation paths

Each incident response includes:
1. Detection methods and symptoms
2. Diagnosis steps with commands
3. Recovery procedures with multiple options
4. Verification steps to confirm resolution
5. Post-incident review checklist

---

## 📊 Scaling Demonstration

### Processor Horizontal Scaling

The system demonstrates horizontal scaling capabilities by scaling the processor service from 1 to 3 replicas and back to 1, measuring performance at each phase.

#### Run Scaling Test

```bash
cd CA4/scripts
./processor-scaling-test.sh
```

**Test Duration**: ~5-7 minutes  
**Test Output**: Timestamped log file with detailed metrics

#### What the Test Does

The scaling test automatically:

1. **Phase 1 - Baseline (1 replica)**
   - Measures baseline throughput and consumer lag
   - Captures resource utilization (CPU/Memory)
   - Observes for 60 seconds

2. **Phase 2 - Scaled Up (3 replicas)**
   - Scales processor service to 3 replicas
   - Waits for Kafka consumer group rebalancing
   - Measures improved throughput
   - Observes for 60 seconds

3. **Phase 3 - Scaled Down (1 replica)**
   - Scales back to 1 replica
   - Verifies graceful degradation
   - Confirms no data loss during scaling
   - Observes for 60 seconds

#### Test Results

**Test Run**: December 3, 2025 17:42:05  
**Results File**: [`processor-scaling-test-20251203_174205.log`](processor-scaling-test-20251203_174205.log)

| Phase | Replicas | Throughput (msg/s) | Consumer Lag | CPU Usage |
|-------|----------|-------------------|--------------|-----------|
| **Phase 1** (Baseline) | 1 | 0.36 | Low (kept up) | ~2.8% |
| **Phase 2** (Scaled) | 3 | 0.32 | Low (kept up) | ~2.1% per replica |
| **Phase 3** (Back to 1) | 1 | 0.36 | Low (kept up) | ~2.8% |

**Key Observations**:
- ✅ **No data loss** - All messages processed successfully during scaling operations
- ✅ **Graceful scaling** - Service handled replica changes smoothly
- ✅ **Consumer group rebalancing** - Kafka partitions automatically redistributed
- ✅ **Low resource usage** - System operates efficiently even at baseline
- ✅ **Maintained low lag** - Processor kept up with incoming sensor data throughout all phases

**Note**: With only 3 edge sensors publishing every 10 seconds (~0.3 msg/s total), the system easily keeps up even with 1 replica. The test demonstrates the *capability* to scale horizontally - in a production environment with hundreds of sensors, the 3-replica configuration would show significant throughput improvements.

#### Metrics Captured

For each phase, the test captures:
- **Messages Processed**: Kafka consumer group current offset
- **Kafka Messages**: Total messages in topic
- **Consumer Lag**: Messages behind (should be near zero)
- **Throughput**: Messages processed per second
- **Resource Utilization**: CPU and memory per replica

#### Production Scaling Recommendations

For production deployments:
- **Light load** (< 10 sensors): 1 replica sufficient
- **Medium load** (10-100 sensors): 2-3 replicas for redundancy
- **Heavy load** (100+ sensors): Scale to N replicas where N = sensors/50
- **High availability**: Minimum 2 replicas even under light load


---

## 🗂️ Project Structure

```
CA4/
├── README.md                      # This file - assignment overview
├── cloud-site/
│   ├── docker-compose.yml         # Cloud services stack
│   ├── terraform/                 # AWS infrastructure
│   │   ├── main.tf                # EC2, VPC, security groups
│   │   ├── variables.tf           # Configurable parameters
│   │   └── outputs.tf             # Manager IP, worker IPs
│   └── scripts/
│       ├── create-secrets.sh      # Docker secrets creation
│       └── create-configs.sh      # Docker configs creation
├── edge-site/
│   ├── docker-compose.yml         # Edge sensors (3 containers)
│   └── deploy-edge.sh             # Edge deployment script
├── vpn-config/
│   ├── cloud-wg0.conf.template    # WireGuard cloud config
│   ├── edge-wg0.conf.template     # WireGuard edge config
│   ├── generate-keys.sh           # VPN key generation
│   └── setup-vpn.sh               # VPN deployment automation
├── scripts/
│   ├── deploy-all.sh                      # Master deployment script
│   ├── verify-deployment.sh               # End-to-end verification
│   ├── processor-scaling-test.sh          # Horizontal scaling test (automated)
│   ├── processor-scaling-test-*.log       # Scaling test results (timestamped)
│   └── SCALING_TEST_FIX.md                # Scaling test debugging notes
├── failure-drills/
│   ├── vpn-failure.sh                     # VPN failure simulation
│   ├── kafka-failure.sh                   # Kafka broker failure
│   ├── network-partition.sh               # Network partition test
│   ├── vpn-failure-drill.log              # VPN drill test results
│   ├── kafka-failure-drill.log            # Kafka drill test results
│   ├── network-partition-drill.log        # Partition drill test results
│   ├── README.md                          # Drill documentation
│   └── BUGFIX-kafka-drill.md              # Bug fixes and lessons learned
├── RUNBOOK.md                             # Operations runbook & incident response
└── docs/
    ├── MONGODB_SECURITY_FIX.md            # Security improvements
    └── NETWORK_ARCHITECTURE.md            # Network design details
```

---

## 🧹 Cleanup

### Remove All Resources

```bash
cd CA4/scripts
./deploy-all.sh cleanup
```

This will:
1. Stop edge sensors (Docker Compose down)
2. Stop edge VPN (wg-quick down wg0)
3. Destroy cloud infrastructure (Terraform destroy)
4. Clean up generated files

**⚠️ WARNING**: This permanently deletes:
- All AWS resources (EC2 instances, VPC, etc.)
- All data in MongoDB volumes
- All WireGuard VPN configs
- All generated keys

---

## 📝 Configuration & Customization

### AWS Region

Default: `us-east-2`

To change:
```bash
# Edit CA4/cloud-site/terraform/variables.tf
variable "aws_region" {
  default = "us-west-2"  # Change to your preferred region
}
```

### Instance Types

Default: `t2.medium` (manager and workers)

To change:
```bash
# Edit CA4/cloud-site/terraform/variables.tf
variable "manager_instance_type" {
  default = "t2.large"  # For more resources
}
```

### VPN Subnet

Default: `10.20.0.0/24`

To change:
```bash
# Edit CA4/vpn-config/cloud-wg0.conf.template
Address = 10.20.0.1/24  # Cloud gateway
AllowedIPs = 10.20.0.2/32  # Edge client

# Edit CA4/vpn-config/edge-wg0.conf.template
Address = 10.20.0.2/24  # Edge client
AllowedIPs = 10.20.0.0/24  # Route to cloud
```

### Number of Sensors

Default: 3 sensors

To change:
```bash
# Edit CA4/edge-site/docker-compose.yml
# Add more sensor services (plant-sensor-004, etc.)
# Update PLANT_ID environment variable
```

---

## 🐛 Troubleshooting

### Issue: VPN connection fails

**Symptoms**: Cannot ping 10.20.0.1

**Solutions**:
```bash
# Check WireGuard status
sudo wg show

# Restart VPN
sudo wg-quick down wg0
sudo wg-quick up wg0

# Check cloud VPN
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) 'sudo wg show'
```

### Issue: Processor not starting (0/1 replicas)

**Symptoms**: `plant-monitoring_processor` shows 0/1

**Solutions**:
```bash
# Check logs
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service logs --tail 100 plant-monitoring_processor'

# Verify MongoDB user exists
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker exec $(sudo docker ps -qf name=mongodb) mongosh plant_monitoring --eval "db.getUsers()"'

# Restart processor
ssh -i ~/.ssh/docker-swarn-key ubuntu@$(cat CA4/.manager-ip) \
  'sudo docker service update --force plant-monitoring_processor'
```

### Issue: Terraform apply fails

**Symptoms**: AWS resource creation errors

**Solutions**:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check AWS region
cat ~/.aws/config

# Destroy and retry
cd CA4/cloud-site/terraform
terraform destroy -auto-approve
terraform apply
```

### Issue: SSH connection refused

**Symptoms**: Cannot SSH to manager node

**Solutions**:
```bash
# Verify SSH key exists
ls -la ~/.ssh/docker-swarm-key

# Check security group allows SSH from your IP
# AWS Console → EC2 → Security Groups → docker-swarm-manager-sg
# Ensure port 22 open for your IP

# Get your public IP
curl -s ifconfig.me

# Wait longer (instances may still be initializing)
sleep 60
```

---

## 📚 Documentation

- **Operations Runbook**: See [`RUNBOOK.md`](RUNBOOK.md) - Incident response procedures
- **Architecture Details**: See [`docs/NETWORK_ARCHITECTURE.md`](docs/NETWORK_ARCHITECTURE.md)
- **Security Improvements**: See [`docs/MONGODB_SECURITY_FIX.md`](docs/MONGODB_SECURITY_FIX.md)
- **Failure Drills**: See [`failure-drills/README.md`](failure-drills/README.md)
- **CA2 Assignment**: See [`../CA2/README.md`](../CA2/README.md)
- **CA3 Assignment**: See [`../CA3/README.md`](../CA3/README.md)

---

## ✅ Submission Checklist

- [x] Cloud infrastructure deployed and running (6/6 services)
- [x] VPN configured and tested (ping 10.20.0.1 successful)
- [x] Edge sensors deployed and publishing data (3/3 containers)
- [x] End-to-end data flow verified (sensor → Kafka → MongoDB → HA)
- [x] Failure drills executed and results documented (3/3 tests completed with logs)
- [x] Processor scaling test completed with metrics (results in processor-scaling-test-*.log)
- [x] All services using Docker secrets (no hardcoded passwords)
- [x] Network segmentation enforced (3-tier architecture)
- [x] Demo video recorded (≤4 minutes)
- [x] All code pushed to GitHub repository
- [x] Resources cleaned up after demonstration

---

## 🎥 Demo Video Script

**Duration**: 3-4 minutes

1. **Introduction** (30 sec)
   - Show architecture diagram
   - Explain edge-to-cloud design

2. **Cloud Services** (45 sec)
   - `ssh` to manager, run `docker service ls`
   - Show all 6 services running (1/1 replicas)
   - Show network segmentation

3. **VPN Connectivity** (45 sec)
   - Show `sudo wg show` on edge
   - Ping cloud gateway (10.20.0.1)
   - Test Kafka connectivity

4. **Edge Sensors** (45 sec)
   - Show `docker compose ps` in edge-site
   - View sensor logs publishing to Kafka

5. **Data Flow** (45 sec)
   - Show processor logs processing messages
   - Query MongoDB for sensor data count
   - Open Home Assistant dashboard, show plant entities

6. **Failure Drill** (30 sec)
   - Run VPN failure drill
   - Show recovery and reconnection

7. **Cleanup** (15 sec)
   - Show `./deploy-all.sh cleanup` command
   - Resources destroyed

---

## 📧 Contact

**Instructor**: [Instructor Name]  
**Course**: CS5287 - Cloud Computing  
**Semester**: Fall 2025  
**University**: Vanderbilt University

---

**Last Updated**: December 3, 2025  
**Version**: 1.0  
**Status**: ✅ Ready for Submission
