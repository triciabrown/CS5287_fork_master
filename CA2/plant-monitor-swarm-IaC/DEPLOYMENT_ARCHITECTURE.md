# Complete Deployment Architecture

## How It All Works Together

This document explains how the infrastructure provisioning, Docker Swarm configuration, and application deployment work together in a single command.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SINGLE COMMAND DEPLOYMENT                         │
│                      ./deploy.sh (MODE=aws)                          │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 1: Infrastructure Provisioning (Terraform)                    │
│                                                                      │
│  Terraform creates:                                                 │
│  ├── AWS VPC (10.0.0.0/16)                                         │
│  ├── Internet Gateway                                              │
│  ├── Public Subnet                                                 │
│  ├── Security Groups (Swarm ports + application ports)            │
│  ├── SSH Key Pair                                                  │
│  ├── Manager Node (1x t2.small - more resources for coordination) │
│  └── Worker Nodes (4x t2.micro - minimal resources)               │
│                                                                      │
│  User Data Script (on each EC2):                                   │
│  ├── Install Docker                                                │
│  ├── Enable Docker service                                         │
│  └── Add ubuntu user to docker group                              │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 2: Swarm Configuration (Ansible)                              │
│                                                                      │
│  ansible/setup-swarm.yml:                                           │
│                                                                      │
│  On Manager Node:                                                   │
│  ├── Wait for cloud-init to complete                              │
│  ├── Check if Swarm already initialized (idempotent)              │
│  ├── Initialize Docker Swarm                                       │
│  ├── Get join tokens (manager & worker)                           │
│  └── Save tokens for workers                                       │
│                                                                      │
│  On Worker Nodes:                                                   │
│  ├── Wait for cloud-init to complete                              │
│  ├── Check if already in swarm (idempotent)                       │
│  ├── Leave old swarm if exists                                    │
│  └── Join swarm using worker token                                │
│                                                                      │
│  Finalization:                                                      │
│  ├── Wait for all nodes to join                                   │
│  ├── Label nodes for service placement                            │
│  └── Create application directories                               │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 3: Application Deployment (Ansible)                           │
│                                                                      │
│  ansible/deploy-stack.yml:                                          │
│                                                                      │
│  File Transfer:                                                     │
│  ├── Copy docker-compose.yml to manager                           │
│  ├── Copy sensor-config.json                                      │
│  └── Copy mosquitto.conf                                          │
│                                                                      │
│  Secrets Creation (idempotent):                                    │
│  ├── Check which secrets already exist                            │
│  ├── Generate random passwords for missing secrets                │
│  ├── Create Docker secrets (encrypted in Swarm)                   │
│  └── Skip if secrets already exist                                │
│                                                                      │
│  Configs Creation (idempotent):                                    │
│  ├── Remove old configs                                            │
│  └── Create new configs                                            │
│                                                                      │
│  Stack Deployment:                                                  │
│  ├── Deploy stack with docker stack deploy                        │
│  ├── Swarm distributes services across nodes                      │
│  ├── Services pull images from Docker Hub                         │
│  └── Containers start on appropriate nodes                        │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────────────┐
│ RESULT: Running Application                                         │
│                                                                      │
│  Manager Node:                                                      │
│  ├── ZooKeeper (persistent storage)                               │
│  ├── Kafka (persistent storage)                                   │
│  ├── MongoDB (persistent storage)                                 │
│  ├── Mosquitto (MQTT broker)                                      │
│  └── Home Assistant (dashboard)                                   │
│                                                                      │
│  Worker Nodes (auto-distributed):                                  │
│  ├── Processor (1 replica)                                        │
│  └── Sensors (2 replicas, scalable)                              │
│                                                                      │
│  Networking:                                                        │
│  ├── Encrypted overlay network (plant-network)                    │
│  ├── Service discovery via DNS                                    │
│  ├── Load balancing across replicas                              │
│  └── TLS encryption between nodes                                 │
└─────────────────────────────────────────────────────────────────────┘
```

## Where Docker Swarm Runs

**Docker Swarm runs INSIDE the EC2 instances**, not as a separate AWS service.

```
AWS Account
  └── VPC
       ├── EC2 Instance (Manager)
       │    └── Docker Engine
       │         └── Docker Swarm (Manager)
       │              ├── Swarm Raft DB (encrypted)
       │              ├── Service Orchestrator
       │              └── Containers
       │                   ├── ZooKeeper
       │                   ├── Kafka
       │                   ├── MongoDB
       │                   └── ...
       │
       ├── EC2 Instance (Worker 1)
       │    └── Docker Engine
       │         └── Docker Swarm (Worker)
       │              └── Containers
       │                   ├── Processor
       │                   └── Sensor
       │
       └── EC2 Instance (Worker 2-4)
            └── (same pattern)
```

## Deployment Modes

### AWS Mode (Multi-Node) - **DEFAULT**
```bash
./deploy.sh
# This is the default mode - provisions AWS infrastructure
```

**What happens:**
1. ✓ Provision AWS infrastructure (Terraform)
   - Creates VPC, subnets, security groups
   - Launches EC2 instances (1 manager + 4 workers)
   - Installs Docker on all nodes

2. ✓ Configure Docker Swarm (Ansible)
   - Initialize swarm on manager
   - Join workers to swarm
   - Label nodes for placement

3. ✓ Deploy applications (Ansible)
   - Create secrets and configs
   - Deploy stack
   - Verify deployment

**Where it runs:**
- AWS EC2 instances in us-east-2
- Docker Swarm spans all instances
- Services distributed across nodes

### Local Mode (Single Node) - Development Only
```bash
MODE=local ./deploy.sh
```

**What happens:**
1. ✓ Check Docker installed and running
2. ✓ Initialize Docker Swarm (if not already)
3. ✓ Create secrets
4. ✓ Create configs
5. ✓ Deploy stack
6. ✓ Run smoke tests

**Where it runs:**
- Your local machine becomes a single-node swarm
- All services run on one machine
- Perfect for development and testing

## Idempotency

Both scripts are **fully idempotent** - you can run them multiple times safely:

### deploy.sh Idempotency
- **Terraform**: Checks existing state, only creates missing resources
- **Ansible**: Checks if swarm initialized, skips if already done
- **Secrets**: Only creates secrets that don't exist
- **Configs**: Removes and recreates (configs are immutable)
- **Stack**: Updates existing stack or creates new one

### teardown.sh Idempotency
- **Stack Removal**: Checks if stack exists before removing
- **AWS Destruction**: Uses Terraform to cleanly destroy all resources
- **Resource Cleanup**: Safely handles missing resources
- **Volume Removal**: Asks for confirmation before deleting data

## File Structure

```
plant-monitor-swarm-IaC/
├── deploy.sh                    # Main deployment script (orchestrates everything)
├── teardown.sh                  # Complete cleanup script
├── docker-compose.yml           # Service definitions
├── sensor-config.json           # Sensor configuration
│
├── terraform/                   # Infrastructure as Code
│   └── main.tf                  # AWS resources definition
│
├── ansible/                     # Configuration Management
│   ├── setup-swarm.yml          # Initialize and configure swarm
│   ├── deploy-stack.yml         # Deploy applications
│   └── inventory.ini            # (auto-generated) Ansible hosts
│
└── scripts/                     # Utility scripts
    ├── create-secrets.sh        # Manual secret creation
    ├── scale-demo.sh            # Demonstrate scaling
    └── smoke-test.sh            # Validate deployment
```

## Communication Flow

### During Deployment

```
Local Machine
    │
    │ 1. Run ./deploy.sh
    │
    ├─→ Terraform
    │   └─→ AWS API
    │       └─→ Creates EC2 instances
    │           └─→ User data installs Docker
    │
    ├─→ Ansible (via SSH)
    │   ├─→ Manager Node
    │   │   └─→ docker swarm init
    │   │       └─→ Creates swarm cluster
    │   │
    │   └─→ Worker Nodes
    │       └─→ docker swarm join
    │           └─→ Join cluster
    │
    └─→ Ansible (via SSH)
        └─→ Manager Node
            └─→ docker stack deploy
                └─→ Swarm distributes services
                    └─→ Workers pull and run containers
```

### In Running System

```
Manager Node
    ├── Swarm Manager
    │   ├── Receives service definitions
    │   ├── Decides which node runs what
    │   └── Monitors service health
    │
    └── Running Services
        ├── Kafka (stateful)
        ├── MongoDB (stateful)
        └── Home Assistant

Worker Nodes
    ├── Swarm Worker
    │   ├── Receives tasks from manager
    │   ├── Pulls container images
    │   └── Runs assigned containers
    │
    └── Running Services
        ├── Processor (connects to Kafka, MongoDB, MQTT)
        └── Sensors (send data to Kafka)

Overlay Network (plant-network)
    └── Encrypted mesh network across all nodes
        ├── Service discovery (kafka, mongodb, mosquitto)
        ├── Load balancing (multiple sensor replicas)
        └── TLS encryption (node-to-node)
```

## Port Configuration

### Swarm Cluster Ports (Internal)
- **2377/tcp**: Cluster management (manager only)
- **7946/tcp+udp**: Node communication
- **4789/udp**: Overlay network traffic

### Application Ports (Exposed)
- **8123/tcp**: Home Assistant web UI (published)
- **9092/tcp**: Kafka broker (published)
- **27017/tcp**: MongoDB (published for debugging)
- **1883/tcp**: MQTT broker (published)

### Security Groups (AWS)
```terraform
# SSH access from anywhere
22/tcp from 0.0.0.0/0

# Swarm ports (internal cluster only)
2377/tcp, 7946/tcp, 7946/udp, 4789/udp from self

# Application ports (public)
8123/tcp from 0.0.0.0/0  # Home Assistant

# Internal cluster communication
All TCP from self
```

## Secrets Management in AWS

```
Terraform Provisions
    └── EC2 Instances

Ansible Runs
    └── docker secret create mongo_password -
        └── Swarm Manager
            └── Encrypts with cluster key
                └── Stores in Raft log (encrypted at rest)

Container Starts
    └── Swarm Manager
        └── Sends encrypted secret over TLS
            └── Worker Node
                └── Mounts as /run/secrets/mongo_password
                    └── Container reads file
```

**Security Benefits:**
- ✅ Never stored in Terraform state
- ✅ Never in environment variables
- ✅ Encrypted at rest in Swarm
- ✅ Encrypted in transit via TLS
- ✅ Only accessible to authorized containers

## Cost Estimation (AWS Free Tier)

```
t2.small Manager:    750 hours/month free (1st year)
t2.micro Workers:    750 hours/month free (4 instances)
Data Transfer:       15 GB/month free
EBS Storage:         30 GB free

Estimated Monthly Cost (after free tier):
- Manager: ~$17/month (t2.small)
- Workers: ~$8.50/month each (t2.micro × 4 = $34/month)
- Storage: ~$3/month (100 GB EBS)
- Data Transfer: ~$5/month

Total: ~$59/month
Free Tier (1st year): ~$0/month
```

## Troubleshooting

### Check Infrastructure
```bash
# Terraform state
cd terraform && terraform show

# Ansible can connect
ansible all -i ansible/inventory.ini -m ping

# Swarm cluster health
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP> 'docker node ls'
```

### Check Application
```bash
# Service status
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP> 'docker stack services plant-monitoring'

# Service logs
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP> 'docker service logs plant-monitoring_sensor'

# Network connectivity
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP> 'docker network inspect plant-monitoring_plant-network'
```

### Common Issues

**"Terraform state locked"**
- Someone else running terraform, or crashed
- Delete `.terraform.tfstate.lock.info` if stuck

**"Permission denied (publickey)"**
- SSH key not found
- Check `~/.ssh/docker-swarm-key` exists
- Run `chmod 600 ~/.ssh/docker-swarm-key`

**"No space left on device"**
- EC2 instance out of disk space
- Increase root volume size in Terraform
- Run docker system prune

**"Service fails to start"**
- Check logs: `docker service logs <service>`
- Check image exists: `docker images`
- Check placement constraints: `docker service inspect <service>`

## Summary

**Single Command Deployment (AWS - DEFAULT):**
```bash
./deploy.sh
```

**This command:**
1. ✅ Provisions AWS infrastructure (VPC, EC2, security groups)
2. ✅ Installs Docker on all instances
3. ✅ Configures Docker Swarm cluster
4. ✅ Creates secrets and configs
5. ✅ Deploys all application services
6. ✅ Verifies deployment

**Single Command Teardown (AWS - DEFAULT):**
```bash
./teardown.sh
```

**This command:**
1. ✅ Removes application stack
2. ✅ Destroys ALL AWS resources
3. ✅ Cleans up Terraform state
4. ✅ Removes local configuration files

**Local Development Mode:**
```bash
MODE=local ./deploy.sh    # Local deployment
MODE=local ./teardown.sh  # Local cleanup
```

**Docker Swarm runs INSIDE the EC2 instances** that Terraform creates. The workflow is:
- Terraform → Create infrastructure
- Ansible → Configure software (Docker Swarm)
- Docker Swarm → Orchestrate containers

This is a complete, production-ready, idempotent deployment system! 🎉
