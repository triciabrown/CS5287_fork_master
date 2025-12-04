# CA4 Cloud Site - Plant Monitoring System

**Assignment**: CA4 - Multi-Hybrid Cloud Architecture  
**Site Type**: Cloud (AWS)  
**Date**: November 2025

---

## Overview

This directory contains the cloud-side infrastructure for the CA4 plant monitoring system. The cloud site runs on AWS EC2 instances using Docker Swarm and hosts the processing, storage, and visualization services.

### Architecture

```
Cloud Site (AWS - Docker Swarm)
┌─────────────────────────────────────────────────────────────┐
│  Manager Node (Public Subnet)                               │
│  ├── Home Assistant (Frontend - 8123)                       │
│  ├── WireGuard VPN Gateway (10.20.0.1)                      │
│  └── Swarm Manager                                          │
│                                                              │
│  Worker Nodes (Private Subnet)                              │
│  ├── Kafka + ZooKeeper (Messaging Tier)                     │
│  ├── MongoDB + Processor (Data Tier)                        │
│  └── Mosquitto MQTT Broker                                  │
└─────────────────────────────────────────────────────────────┘
                          │
                    VPN Tunnel
                    (WireGuard)
                          │
┌─────────────────────────────────────────────────────────────┐
│  Edge Site (Local)                                          │
│  ├── Plant Sensor 1 (Tomato)                                │
│  ├── Plant Sensor 2 (Basil)                                 │
│  └── Plant Sensor 3 (Lettuce)                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Features (CA4 Improvements)

### 1. **3-Tier Network Segmentation** (Security Enhancement)
```yaml
networks:
  frontend-net:   # 10.10.1.0/24 - Home Assistant only
  messaging-net:  # 10.10.2.0/24 - Kafka, ZooKeeper
  data-net:       # 10.10.3.0/24 - MongoDB, Processor, Mosquitto
```

**Security Benefits**:
- Home Assistant cannot directly access Kafka or MongoDB
- Kafka isolated from frontend
- Least privilege network access per service

### 2. **VPN-Based Edge Connectivity**
- **VPN Gateway**: WireGuard on manager node (10.20.0.1)
- **Kafka External Listener**: Accessible only via VPN (10.20.0.0/24)
- **Encryption**: ChaCha20-Poly1305
- **Firewall**: Security groups restrict Kafka to VPN subnet only

### 3. **Scalable Processor**
```yaml
processor:
  deploy:
    replicas: 1  # Can scale to 3 for high load
```

---

## Directory Structure

```
cloud-site/
├── docker-compose.yml          # Main stack definition (3-tier networks)
├── terraform/                  # AWS infrastructure as code
│   ├── main.tf                 # VPC, subnets, security groups, EC2 instances
│   ├── variables.tf            # Configurable parameters
│   └── outputs.tf              # Manager IP, worker IPs, etc.
├── scripts/
│   └── create-secrets.sh       # Generate MongoDB/Kafka secrets
└── README.md                   # This file
```

---

## Deployment

### Quick Start
```bash
# From CA4 root directory
cd /home/tricia/dev/CS5287_fork_master/CA4/scripts

# Full deployment (cloud + VPN + edge)
./deploy-all.sh deploy

# Cloud only
./deploy-all.sh cloud
```

### Manual Deployment

#### 1. Deploy Infrastructure
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

#### 2. Initialize Swarm
```bash
# SSH to manager
MANAGER_IP=$(terraform output -raw manager_public_ip)
ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP}

# Initialize swarm
sudo docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')

# Get worker join token
sudo docker swarm join-token worker
```

#### 3. Join Workers
```bash
# On each worker node (via manager as bastion)
ssh -o ProxyJump=ubuntu@${MANAGER_IP} -i ~/.ssh/docker-swarm-key ubuntu@<WORKER_IP>
sudo docker swarm join --token <TOKEN> <MANAGER_PRIVATE_IP>:2377
```

#### 4. Deploy Stack
```bash
# On manager node
sudo docker stack deploy -c ~/docker-compose.yml plant-monitoring
```

---

## Services

| Service | Port | Network Tier | Description |
|---------|------|--------------|-------------|
| **home-assistant** | 8123 | frontend-net | Web UI for monitoring |
| **mosquitto** | 1883 | frontend-net, data-net | MQTT broker (bridge tier) |
| **kafka** | 9092 | messaging-net | Message broker (internal + VPN) |
| **zookeeper** | 2181 | messaging-net | Kafka coordination |
| **processor** | - | messaging-net, data-net | Kafka→MongoDB pipeline |
| **mongodb** | 27017 | data-net | Time-series database |

### Kafka Listeners
- **INTERNAL**: `kafka:9092` (Docker overlay, swarm services only)
- **EXTERNAL**: `10.20.0.1:9092` (VPN overlay, edge sensors only)

---

## Network Architecture

### Overlay Networks
```yaml
frontend-net:
  driver: overlay
  ipam:
    config:
      - subnet: 10.10.1.0/24

messaging-net:
  driver: overlay
  ipam:
    config:
      - subnet: 10.10.2.0/24

data-net:
  driver: overlay
  ipam:
    config:
      - subnet: 10.10.3.0/24
```

### Service Network Mapping
```
┌─────────────────┬──────────┬──────────┬──────────┐
│ Service         │ Frontend │ Messaging│   Data   │
├─────────────────┼──────────┼──────────┼──────────┤
│ Home Assistant  │    ✓     │          │          │
│ Mosquitto       │    ✓     │          │    ✓     │
│ Processor       │          │    ✓     │    ✓     │
│ Kafka           │          │    ✓     │          │
│ ZooKeeper       │          │    ✓     │          │
│ MongoDB         │          │          │    ✓     │
└─────────────────┴──────────┴──────────┴──────────┘
```

---

## Security Groups (Terraform)

### Manager Node (Public Subnet)
- SSH (22) - from anywhere
- Home Assistant (8123) - from anywhere
- **WireGuard VPN (51820/udp)** - from anywhere (CA4 addition)
- **Kafka External (9092/tcp)** - from VPN subnet only (10.20.0.0/24)
- Swarm ports (2377, 7946, 4789) - from VPC
- Docker overlay (ESP, AH, IKE) - from VPC

### Worker Nodes (Private Subnet)
- SSH (22) - from manager only
- Swarm ports - from VPC
- Docker overlay - from VPC
- Internet access - via NAT Gateway

---

## Monitoring & Verification

### Check Service Status
```bash
# On manager node
sudo docker service ls
sudo docker service ps plant-monitoring_kafka
sudo docker service logs -f plant-monitoring_processor
```

### Verify Networks
```bash
sudo docker network ls --filter driver=overlay
sudo docker network inspect plant-monitoring_messaging-net
```

### Test Kafka Connectivity
```bash
# From edge site (via VPN)
timeout 5 bash -c "echo > /dev/tcp/10.20.0.1/9092"
```

---

## Scaling

### Scale Processor
```bash
# On manager node
sudo docker service scale plant-monitoring_processor=3

# Monitor Kafka consumer lag
sudo docker exec $(sudo docker ps -q -f name=kafka) \
  kafka-consumer-groups --bootstrap-server localhost:9092 \
  --group processor-group --describe
```

---

## Troubleshooting

### Service Not Starting
```bash
# Check service events
sudo docker service ps --no-trunc plant-monitoring_<service>

# Check node status
sudo docker node ls
```

### Network Connectivity Issues
```bash
# Verify overlay networks exist
sudo docker network ls --filter driver=overlay

# Check service endpoints
sudo docker service inspect plant-monitoring_kafka --format '{{json .Endpoint}}'
```

### VPN Issues
```bash
# On manager, check WireGuard status
sudo wg show

# Check firewall rules
sudo iptables -L -n -v | grep 51820
```

---

## Cleanup

### Remove Stack
```bash
sudo docker stack rm plant-monitoring
```

### Leave Swarm
```bash
# Workers first
sudo docker swarm leave

# Manager last
sudo docker swarm leave --force
```

### Destroy Infrastructure
```bash
cd terraform/
terraform destroy
```

---

## Related Files

- **VPN Configuration**: `../vpn-config/`
- **Edge Site**: `../edge-site/`
- **Deployment Scripts**: `../scripts/`
- **Documentation**: `../docs/`

---

## CA4 Improvements Summary

| Area | CA2 | CA4 | Improvement |
|------|-----|-----|-------------|
| Network Segmentation | Single overlay | 3-tier overlay | +4 pts security |
| Edge Connectivity | N/A | WireGuard VPN | Multi-hybrid cloud |
| Kafka Security | Public | VPN-only | Restricted access |
| Processor Scaling | Manual | Automated tests | +3 pts observability |

**CA2 Score**: 93/100  
**CA4 Target**: 100/100

---

**Last Updated**: November 23, 2025  
**Assignment**: CS5287 CA4 - Multi-Hybrid Cloud Architecture
