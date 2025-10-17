# Docker Swarm Migration Guide

**From**: Kubernetes on AWS  
**To**: Docker Swarm on AWS  
**Estimated Time**: 4-6 hours  
**Difficulty**: Medium

---

## Overview

This guide provides step-by-step instructions to migrate the Plant Monitoring System from Kubernetes to Docker Swarm while preserving all existing work.

---

## Pre-Migration Checklist

- [x] Kubernetes implementation fully documented in `KUBERNETES_ARCHIVE.md`
- [x] Migration rationale documented in `WHY_DOCKER_SWARM.md`
- [ ] AWS credentials configured (`~/.aws/credentials`)
- [ ] SSH key pair ready (`~/.ssh/k8s-cluster-key` or will be created)
- [ ] All Kubernetes resources torn down (or will be torn down)
- [ ] Current work committed to git

---

## Step 1: Archive Kubernetes Implementation (10 minutes)

### 1.1 Create Archive Directory
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2
mkdir -p kubernetes-archive
```

### 1.2 Move Kubernetes Files
```bash
# Move all Kubernetes-specific directories
mv plant-monitor-k8s-IaC kubernetes-archive/
mv aws-cluster-setup kubernetes-archive/ 2>/dev/null || true

# Copy applications (will be converted for Swarm)
cp -r applications kubernetes-archive/applications-k8s

# Move learning materials
mv learning-lab kubernetes-archive/ 2>/dev/null || true
```

### 1.3 Update Git
```bash
git add -A
git commit -m "Archive Kubernetes implementation before Swarm migration"
```

---

## Step 2: Tear Down Kubernetes Cluster (5-10 minutes)

### 2.1 Run Teardown Script
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/kubernetes-archive/plant-monitor-k8s-IaC
./teardown.sh
```

### 2.2 Verify Cleanup
```bash
# Check AWS resources are destroyed
aws ec2 describe-instances --filters "Name=tag:Project,Values=plant-monitoring" \
  --query "Reservations[].Instances[].[InstanceId,State.Name]"

# Should return empty or "terminated"
```

---

## Step 3: Create Docker Swarm Infrastructure (60-90 minutes)

### 3.1 Create Directory Structure
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2
mkdir -p plant-monitor-swarm-IaC/{terraform,ansible,scripts}
cd plant-monitor-swarm-IaC
```

### 3.2 Create Terraform Configuration

**File**: `terraform/main.tf`

```hcl
# Simplified Terraform for Docker Swarm
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  default = "us-east-2"
}

variable "cluster_name" {
  default = "plant-monitoring-swarm"
}

variable "manager_count" {
  default = 1
}

variable "worker_count" {
  default = 4
}

# VPC
resource "aws_vpc" "swarm_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.cluster_name}-vpc"
    Project = "plant-monitoring"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "swarm_igw" {
  vpc_id = aws_vpc.swarm_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Public Subnet (simplified - single subnet)
resource "aws_subnet" "swarm_public" {
  vpc_id                  = aws_vpc.swarm_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-subnet"
  }
}

# Route Table
resource "aws_route_table" "swarm_public_rt" {
  vpc_id = aws_vpc.swarm_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.swarm_igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "swarm_public_rta" {
  subnet_id      = aws_subnet.swarm_public.id
  route_table_id = aws_route_table.swarm_public_rt.id
}

# Security Group - Simplified for Swarm
resource "aws_security_group" "swarm_sg" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for Docker Swarm cluster"
  vpc_id      = aws_vpc.swarm_vpc.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Docker Swarm management
  ingress {
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    self        = true
    description = "Swarm management"
  }

  # Docker Swarm communication
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    self        = true
    description = "Swarm node communication TCP"
  }

  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    self        = true
    description = "Swarm node communication UDP"
  }

  # Overlay network
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    self        = true
    description = "Overlay network traffic"
  }

  # Home Assistant
  ingress {
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Home Assistant UI"
  }

  # All internal traffic
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-sg"
  }
}

# SSH Key Pair
resource "aws_key_pair" "swarm_key" {
  key_name   = "${var.cluster_name}-key"
  public_key = file("~/.ssh/k8s-cluster-key.pub")
}

# Manager Node
resource "aws_instance" "swarm_manager" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.small"  # Manager needs slightly more resources
  key_name      = aws_key_pair.swarm_key.key_name
  subnet_id     = aws_subnet.swarm_public.id

  vpc_security_group_ids = [aws_security_group.swarm_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              systemctl enable docker
              systemctl start docker
              usermod -aG docker ubuntu
              EOF

  tags = {
    Name    = "${var.cluster_name}-manager"
    Role    = "manager"
    Project = "plant-monitoring"
  }
}

# Worker Nodes
resource "aws_instance" "swarm_workers" {
  count         = var.worker_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.swarm_key.key_name
  subnet_id     = aws_subnet.swarm_public.id

  vpc_security_group_ids = [aws_security_group.swarm_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              systemctl enable docker
              systemctl start docker
              usermod -aG docker ubuntu
              EOF

  tags = {
    Name    = "${var.cluster_name}-worker-${count.index + 1}"
    Role    = "worker"
    Project = "plant-monitoring"
  }
}

# Data source for Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Outputs
output "manager_public_ip" {
  value = aws_instance.swarm_manager.public_ip
}

output "worker_public_ips" {
  value = aws_instance.swarm_workers[*].public_ip
}

output "ssh_command_manager" {
  value = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.swarm_manager.public_ip}"
}
```

### 3.3 Create Ansible Configuration

**File**: `ansible/inventory.ini`

```ini
[manager]
manager ansible_host={{ manager_ip }} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/k8s-cluster-key

[workers]
{% for ip in worker_ips %}
worker-{{ loop.index }} ansible_host={{ ip }} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/k8s-cluster-key
{% endfor %}

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

**File**: `ansible/swarm-init.yml`

```yaml
---
- name: Initialize Docker Swarm
  hosts: manager
  become: yes
  tasks:
    - name: Initialize Swarm on manager
      command: docker swarm init --advertise-addr {{ ansible_default_ipv4.address }}
      register: swarm_init
      ignore_errors: yes

    - name: Get worker join token
      command: docker swarm join-token -q worker
      register: worker_token

    - name: Save join command
      set_fact:
        join_command: "docker swarm join --token {{ worker_token.stdout }} {{ ansible_default_ipv4.address }}:2377"

- name: Join workers to Swarm
  hosts: workers
  become: yes
  tasks:
    - name: Join Swarm as worker
      command: "{{ hostvars[groups['manager'][0]]['join_command'] }}"
      ignore_errors: yes
```

### 3.4 Deploy Infrastructure
```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve

# Save outputs
terraform output -json > ../outputs.json
```

---

## Step 4: Initialize Docker Swarm (15 minutes)

### 4.1 Generate Ansible Inventory
```bash
cd ../ansible

# Extract IPs from Terraform output
MANAGER_IP=$(cat ../outputs.json | jq -r '.manager_public_ip.value')
WORKER_IPS=$(cat ../outputs.json | jq -r '.worker_public_ips.value[]' | paste -sd,)

# Create inventory
cat > inventory.ini <<EOF
[manager]
manager ansible_host=$MANAGER_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/k8s-cluster-key

[workers]
$(cat ../outputs.json | jq -r '.worker_public_ips.value[]' | awk '{print "worker-"NR" ansible_host="$1" ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/k8s-cluster-key"}')

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
```

### 4.2 Wait for Instances to be Ready
```bash
# Wait 60 seconds for user_data to complete Docker installation
echo "Waiting for instances to initialize..."
sleep 60
```

### 4.3 Initialize Swarm
```bash
ansible-playbook -i inventory.ini swarm-init.yml
```

### 4.4 Verify Swarm
```bash
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP "docker node ls"
```

**Expected Output**:
```
ID                            HOSTNAME                      STATUS    AVAILABILITY   MANAGER STATUS
abc123 *   ip-10-0-1-10.region.compute.internal   Ready     Active         Leader
def456     ip-10-0-1-11.region.compute.internal   Ready     Active
ghi789     ip-10-0-1-12.region.compute.internal   Ready     Active
...
```

---

## Step 5: Convert Applications to Docker Compose (60 minutes)

### 5.1 Create Docker Compose File

**File**: `docker-compose.yml`

```yaml
version: '3.8'

services:
  # MongoDB - Data Storage
  mongodb:
    image: mongo:6.0.4
    command: mongod --wiredTigerCacheSizeGB 0.25 --bind_ip 0.0.0.0
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: plantmon2024
    volumes:
      - mongodb-data:/data/db
    networks:
      - plant-network
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager  # Keep database on manager for simplicity
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3

  # Kafka - Message Broker (Simplified without KRaft complexity)
  kafka:
    image: confluentinc/cp-kafka:7.4.0
    hostname: kafka
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_HEAP_OPTS: "-Xmx160M -Xms160M"
      KAFKA_LOG4J_ROOT_LOGLEVEL: INFO
    volumes:
      - kafka-data:/var/lib/kafka/data
    networks:
      - plant-network
    deploy:
      replicas: 1
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 200M
      restart_policy:
        condition: on-failure
        delay: 10s
    depends_on:
      - zookeeper

  # Zookeeper (simpler than KRaft for this use case)
  zookeeper:
    image: confluentinc/cp-zookeeper:7.4.0
    hostname: zookeeper
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    volumes:
      - zookeeper-data:/var/lib/zookeeper/data
      - zookeeper-logs:/var/lib/zookeeper/log
    networks:
      - plant-network
    deploy:
      replicas: 1
      resources:
        limits:
          memory: 128M
        reservations:
          memory: 64M

  # Plant Processor
  plant-processor:
    image: triciabrown/plant-processor:latest
    environment:
      KAFKA_BOOTSTRAP_SERVERS: kafka:9092
      MONGODB_URI: mongodb://admin:plantmon2024@mongodb:27017/
      KAFKA_TOPIC: plant_monitoring_data
    networks:
      - plant-network
    deploy:
      replicas: 1
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M
      restart_policy:
        condition: on-failure
        delay: 10s
    depends_on:
      - kafka
      - mongodb

  # Plant Sensor - Plant 001
  plant-sensor-001:
    image: triciabrown/plant-sensor:latest
    environment:
      PLANT_ID: plant-001
      PLANT_NAME: "Monstera Deliciosa"
      KAFKA_BOOTSTRAP_SERVERS: kafka:9092
      KAFKA_TOPIC: plant_monitoring_data
      MQTT_BROKER: homeassistant
      MQTT_PORT: 1883
      SENSOR_INTERVAL: 30
    networks:
      - plant-network
    deploy:
      replicas: 1
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M
      restart_policy:
        condition: on-failure
        delay: 10s
    depends_on:
      - kafka

  # Plant Sensor - Plant 002
  plant-sensor-002:
    image: triciabrown/plant-sensor:latest
    environment:
      PLANT_ID: plant-002
      PLANT_NAME: "Snake Plant"
      KAFKA_BOOTSTRAP_SERVERS: kafka:9092
      KAFKA_TOPIC: plant_monitoring_data
      MQTT_BROKER: homeassistant
      MQTT_PORT: 1883
      SENSOR_INTERVAL: 30
    networks:
      - plant-network
    deploy:
      replicas: 1
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M
      restart_policy:
        condition: on-failure
        delay: 10s
    depends_on:
      - kafka

  # Home Assistant - Monitoring Dashboard
  homeassistant:
    image: triciabrown/plant-homeassistant:latest
    ports:
      - "8123:8123"
    environment:
      TZ: America/New_York
    volumes:
      - homeassistant-config:/config
    networks:
      - plant-network
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager  # Expose on manager node
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M
      restart_policy:
        condition: on-failure

networks:
  plant-network:
    driver: overlay
    attachable: true

volumes:
  mongodb-data:
  kafka-data:
  zookeeper-data:
  zookeeper-logs:
  homeassistant-config:
```

### 5.2 Key Changes from Kubernetes

1. **Kafka**: Switched from KRaft to Zookeeper (simpler, more stable)
2. **Networking**: Single overlay network (no service objects needed)
3. **Storage**: Docker volumes (simpler than PVC/PV)
4. **Replication**: `replicas: 1` (same as K8s, but simpler syntax)
5. **Resources**: Same limits, cleaner syntax
6. **Health Checks**: Can add `healthcheck:` blocks if needed

---

## Step 6: Deploy Application Stack (15 minutes)

### 6.1 Copy Docker Compose to Manager
```bash
MANAGER_IP=$(cat outputs.json | jq -r '.manager_public_ip.value')

scp -i ~/.ssh/k8s-cluster-key docker-compose.yml ubuntu@$MANAGER_IP:~/
```

### 6.2 Deploy Stack
```bash
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP << 'EOF'
  docker stack deploy -c docker-compose.yml plant-monitoring
EOF
```

### 6.3 Monitor Deployment
```bash
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP "docker service ls"
```

**Expected Output**:
```
ID             NAME                               MODE         REPLICAS   IMAGE
abc123         plant-monitoring_mongodb           replicated   1/1        mongo:6.0.4
def456         plant-monitoring_kafka             replicated   1/1        confluentinc/cp-kafka:7.4.0
ghi789         plant-monitoring_zookeeper         replicated   1/1        confluentinc/cp-zookeeper:7.4.0
jkl012         plant-monitoring_plant-processor   replicated   1/1        triciabrown/plant-processor:latest
mno345         plant-monitoring_plant-sensor-001  replicated   1/1        triciabrown/plant-sensor:latest
pqr678         plant-monitoring_plant-sensor-002  replicated   1/1        triciabrown/plant-sensor:latest
stu901         plant-monitoring_homeassistant     replicated   1/1        triciabrown/plant-homeassistant:latest
```

---

## Step 7: Validation & Testing (30 minutes)

### 7.1 Check Service Health
```bash
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP << 'EOF'
  # All services should show REPLICAS as X/X
  docker service ls
  
  # Check individual service details
  docker service ps plant-monitoring_mongodb
  docker service ps plant-monitoring_kafka
EOF
```

### 7.2 Test MongoDB
```bash
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP << 'EOF'
  # Find MongoDB container
  MONGO_CONTAINER=$(docker ps --filter "name=plant-monitoring_mongodb" -q | head -1)
  
  # Connect and check database
  docker exec -it $MONGO_CONTAINER mongosh -u admin -p plantmon2024 --eval "
    use plant_monitoring;
    db.sensor_data.find().limit(5).pretty();
  "
EOF
```

### 7.3 Test Kafka
```bash
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP << 'EOF'
  # Find Kafka container
  KAFKA_CONTAINER=$(docker ps --filter "name=plant-monitoring_kafka" -q | head -1)
  
  # List topics
  docker exec $KAFKA_CONTAINER kafka-topics --bootstrap-server localhost:9092 --list
EOF
```

### 7.4 Check Logs
```bash
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP << 'EOF'
  docker service logs plant-monitoring_plant-sensor-001 --tail 50
  docker service logs plant-monitoring_plant-processor --tail 50
EOF
```

### 7.5 Access Home Assistant
```bash
# Get manager IP
MANAGER_IP=$(cat outputs.json | jq -r '.manager_public_ip.value')

echo "Home Assistant available at: http://$MANAGER_IP:8123"
```

Open in browser and verify dashboard loads.

---

## Step 8: Documentation Update (30 minutes)

### 8.1 Update Main README

Add section comparing both implementations:

```markdown
## CA2: Container Orchestration Journey

This assignment explored container orchestration by implementing the plant monitoring system on both **Kubernetes** and **Docker Swarm**.

### Kubernetes Implementation (Archived)
- **Status**: Fully functional but archived due to resource constraints
- **Infrastructure**: 5-node cluster (1 control plane + 4 workers, t2.micro)
- **Challenges**: Worker join issues, memory constraints, operational complexity
- **Learning**: Deep understanding of K8s architecture, StatefulSets, CNI, storage
- **Documentation**: See `KUBERNETES_ARCHIVE.md` for complete journey

### Docker Swarm Implementation (Active)
- **Status**: Production deployment
- **Infrastructure**: 5-node swarm (1 manager + 4 workers, t2.micro)
- **Benefits**: 53% less overhead, simpler operations, better fit for free tier
- **Learning**: Comparative analysis, pragmatic technology selection
- **Documentation**: See below

### Comparison
| Aspect | Kubernetes | Docker Swarm |
|--------|-----------|--------------|
| System Overhead | 1.6GB (32%) | 755MB (15%) |
| Setup Time | 8+ hours | 2 hours |
| Configuration | Complex YAML | Docker Compose |
| Operational Cost | High | Low |
```

### 8.2 Create Swarm Deployment Guide

**File**: `plant-monitor-swarm-IaC/README.md`

```markdown
# Plant Monitoring System - Docker Swarm Deployment

## Quick Start

1. Deploy infrastructure:
   ```bash
   cd terraform
   terraform apply
   ```

2. Initialize swarm:
   ```bash
   cd ../ansible
   ansible-playbook -i inventory.ini swarm-init.yml
   ```

3. Deploy applications:
   ```bash
   MANAGER_IP=$(terraform output -raw manager_public_ip)
   scp docker-compose.yml ubuntu@$MANAGER_IP:~/
   ssh ubuntu@$MANAGER_IP "docker stack deploy -c docker-compose.yml plant-monitoring"
   ```

4. Access Home Assistant: `http://<manager-ip>:8123`

## Architecture

- 1 Manager node (t2.small) - coordinates cluster
- 4 Worker nodes (t2.micro) - run application containers
- Overlay network for service communication
- Docker volumes for persistent storage

## Resource Usage

Total: ~755MB system overhead vs. 1.6GB with Kubernetes
Available for applications: 85% vs. 68% with Kubernetes
```

---

## Step 9: Create Deployment Script (Optional, 15 minutes)

**File**: `plant-monitor-swarm-IaC/deploy.sh`

```bash
#!/bin/bash
set -e

echo "🚀 Deploying Plant Monitoring System on Docker Swarm"

# Step 1: Deploy infrastructure
echo "📦 Step 1: Deploying AWS infrastructure..."
cd terraform
terraform init -upgrade
terraform apply -auto-approve
terraform output -json > ../outputs.json
cd ..

# Step 2: Wait for instances
echo "⏳ Step 2: Waiting for instances to initialize (60s)..."
sleep 60

# Step 3: Generate inventory
echo "📝 Step 3: Generating Ansible inventory..."
MANAGER_IP=$(cat outputs.json | jq -r '.manager_public_ip.value')
cat outputs.json | jq -r '.worker_public_ips.value[]' | awk '{print "worker-"NR" ansible_host="$1" ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/k8s-cluster-key"}' > /tmp/workers.txt

cat > ansible/inventory.ini <<EOF
[manager]
manager ansible_host=$MANAGER_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/k8s-cluster-key

[workers]
$(cat /tmp/workers.txt)

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Step 4: Initialize swarm
echo "🐝 Step 4: Initializing Docker Swarm..."
cd ansible
ansible-playbook -i inventory.ini swarm-init.yml
cd ..

# Step 5: Deploy application stack
echo "🌱 Step 5: Deploying plant monitoring stack..."
scp -i ~/.ssh/k8s-cluster-key docker-compose.yml ubuntu@$MANAGER_IP:~/
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP "docker stack deploy -c docker-compose.yml plant-monitoring"

# Step 6: Monitor deployment
echo "👀 Step 6: Monitoring deployment..."
sleep 10
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP "docker service ls"

# Success!
echo ""
echo "✅ Deployment complete!"
echo "🌐 Home Assistant: http://$MANAGER_IP:8123"
echo "🔑 SSH to manager: ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP"
echo ""
echo "Useful commands:"
echo "  docker node ls                  # Check cluster status"
echo "  docker service ls               # List services"
echo "  docker service logs <service>   # View logs"
echo "  docker stack ps plant-monitoring  # Service details"
```

Make it executable:
```bash
chmod +x deploy.sh
```

---

## Step 10: Create Teardown Script (Optional, 10 minutes)

**File**: `plant-monitor-swarm-IaC/teardown.sh`

```bash
#!/bin/bash
set -e

echo "🧹 Tearing down Plant Monitoring System"

# Get manager IP
MANAGER_IP=$(cat outputs.json | jq -r '.manager_public_ip.value' 2>/dev/null || echo "")

# Step 1: Remove application stack
if [ -n "$MANAGER_IP" ]; then
  echo "📦 Step 1: Removing application stack..."
  ssh -i ~/.ssh/k8s-cluster-key ubuntu@$MANAGER_IP "docker stack rm plant-monitoring" 2>/dev/null || true
  sleep 10
fi

# Step 2: Destroy infrastructure
echo "💥 Step 2: Destroying AWS infrastructure..."
cd terraform
terraform destroy -auto-approve
cd ..

echo "✅ Teardown complete!"
```

Make it executable:
```bash
chmod +x teardown.sh
```

---

## Troubleshooting

### Issue: Workers not joining swarm
```bash
# On manager, get join token
docker swarm join-token worker

# On worker, manually join
docker swarm join --token <token> <manager-ip>:2377
```

### Issue: Service not starting
```bash
# Check service status
docker service ps <service-name> --no-trunc

# View logs
docker service logs <service-name> --tail 100

# Inspect service
docker service inspect <service-name>
```

### Issue: Network connectivity problems
```bash
# Check overlay network
docker network ls
docker network inspect plant-network

# Test from container
docker run --rm --network plant-network alpine ping kafka
```

### Issue: Volume data loss
```bash
# List volumes
docker volume ls

# Inspect volume
docker volume inspect <volume-name>

# Backup volume
docker run --rm -v <volume-name>:/data -v $(pwd):/backup alpine tar czf /backup/backup.tar.gz /data
```

---

## Rollback Plan

If Swarm deployment fails and you need to revert to Kubernetes:

1. All Kubernetes files are preserved in `kubernetes-archive/`
2. Move them back:
   ```bash
   mv kubernetes-archive/plant-monitor-k8s-IaC ./
   mv kubernetes-archive/aws-cluster-setup ./
   ```
3. Follow previous K8s deployment procedures

---

## Success Metrics

- [ ] All 5 nodes joined swarm successfully
- [ ] All 7 services deployed and running (REPLICAS X/X)
- [ ] MongoDB accessible and storing data
- [ ] Kafka topics created and receiving messages
- [ ] Sensors publishing data
- [ ] Processor consuming and transforming data
- [ ] Home Assistant UI accessible on port 8123
- [ ] System stable for 24+ hours
- [ ] Resource utilization <70%

---

## Next Steps After Migration

1. **Monitor Performance**: Check resource usage over 24-48 hours
2. **Test Failures**: Simulate node failures, verify recovery
3. **Add Monitoring**: Consider adding Portainer for UI management
4. **Scale Testing**: Test scaling services up/down
5. **Documentation**: Complete final project report comparing K8s vs. Swarm

---

## Estimated Timeline

| Phase | Task | Time | Cumulative |
|-------|------|------|------------|
| 1 | Archive K8s files | 10 min | 10 min |
| 2 | Tear down K8s | 10 min | 20 min |
| 3 | Create Terraform | 60 min | 80 min |
| 4 | Deploy infrastructure | 15 min | 95 min |
| 5 | Convert docker-compose | 60 min | 155 min |
| 6 | Deploy applications | 15 min | 170 min |
| 7 | Validation & testing | 30 min | 200 min |
| 8 | Documentation | 30 min | 230 min |
| 9 | Deploy script | 15 min | 245 min |
| 10 | Teardown script | 10 min | 255 min |
| **Total** | | **4h 15min** | |

Add 1-2 hours buffer for troubleshooting: **Total ~6 hours**

---

**Ready to begin migration!** 🚀
