# CA1 to CA2 Reuse Strategy

**Goal**: Maximize reuse of working CA1 components while meeting CA2 Docker Swarm requirements

---

## CA2 Requirements Analysis

### What CA2 Needs (Docker Swarm):
1. ✅ **Platform**: Docker Swarm (3+ nodes) - NEW infrastructure needed
2. ✅ **Container Images**: Already have from CA1 (sensors, processor)
3. ✅ **Declarative Config**: Docker Compose v3 format - adapt from CA1
4. ✅ **Kafka**: With ZooKeeper (simpler than KRaft for Swarm)
5. ✅ **MongoDB**: Service with volume - reuse CA1 config
6. ✅ **Processor**: Already containerized in CA1
7. ✅ **Producers (Sensors)**: Already containerized in CA1
8. ✅ **Network Isolation**: Overlay networks - NEW
9. ✅ **Scaling Demo**: `docker service scale` - NEW
10. ✅ **Secrets Management**: Docker secrets - adapt from CA1
11. ✅ **Security**: Minimal ports, proper access - reuse CA1 approach
12. ✅ **Validation**: Smoke test - adapt from CA1 health checks
13. ✅ **Single Deploy/Destroy**: Similar to CA1 scripts

---

## What We Can Reuse from CA1

### ✅ **DIRECT REUSE (Copy as-is)**

#### 1. Application Code & Dockerfiles
- ✅ `CA1/applications/vm-3-processor/plant-care-processor/` 
  - `app.js`, `package.json`, `Dockerfile`
  - **Action**: Copy to `CA2/applications/processor/`

- ✅ `CA1/applications/vm-4-homeassistant/plant-sensors/`
  - `sensor.js`, `package.json`, `Dockerfile`
  - **Action**: Copy to `CA2/applications/sensor/`

#### 2. Home Assistant Configuration
- ✅ `CA1/applications/vm-4-homeassistant/config/`
  - All YAML files (automations, configuration, sensors, etc.)
  - **Action**: Copy to `CA2/homeassistant-config/`

- ✅ `CA1/applications/vm-4-homeassistant/mosquitto/config/`
  - `mosquitto.conf`
  - **Action**: Copy to `CA2/mosquitto-config/`

#### 3. Documentation Patterns
- ✅ CA1's excellent README structure
- ✅ Quick start format
- ✅ Troubleshooting sections
- ✅ Architecture diagrams

---

### 🔄 **ADAPT & MERGE**

#### 1. Terraform Infrastructure
**From CA1**: `CA1/plant-monitor-IaC/terraform/`
- ✅ VPC module structure
- ✅ Security group patterns
- ✅ Variables/outputs organization

**Adapt for CA2**:
- Remove Kubernetes-specific items
- Simplify for Docker Swarm (no kubeadm, CNI, etc.)
- Keep: VPC, subnets, security groups, EC2 instances
- **Action**: Use CA1's `modules/networking/` and `modules/security/` as templates

#### 2. Ansible Automation
**From CA1**: `CA1/plant-monitor-IaC/application-deployment/`
- ✅ `setup_docker.yml` - DIRECT REUSE
- ✅ `group_vars/all.yml` structure - adapt variables
- ✅ Role patterns for services

**Adapt for CA2**:
- Instead of individual service playbooks, use Docker Swarm stack deploy
- Keep health check patterns
- **Action**: Reuse Docker setup, create new `swarm-init.yml` and `deploy-stack.yml`

#### 3. Docker Compose Files
**From CA1**: `CA1/applications/vm-*/docker-compose.yml`
- ✅ MongoDB service definition
- ✅ Kafka + ZooKeeper setup (already have this!)
- ✅ Processor configuration
- ✅ Sensor environment variables

**Adapt for CA2**:
- Merge all individual compose files into ONE stack file
- Add `deploy:` sections for replicas and constraints
- Add Docker secrets instead of environment variables
- Create overlay network
- **Action**: Create master `docker-compose.yml` from CA1's individual files

---

### 🔧 **CA1 → CA2 Conversion Plan**

#### Phase 1: Infrastructure (Reuse 70% from CA1)
```
CA1/plant-monitor-IaC/terraform/
├── modules/networking/      → REUSE AS-IS
├── modules/security/        → ADAPT (simpler SG rules for Swarm)
├── modules/compute/         → ADAPT (no Kubernetes, add Docker Swarm init)
├── variables.tf             → ADAPT (remove K8s variables)
└── outputs.tf               → ADAPT (Swarm-specific outputs)
```

#### Phase 2: Application Stack (Reuse 90% from CA1)
```
CA1 Individual Compose Files → CA2 Unified Stack

CA1/applications/vm-1-kafka/docker-compose.yml        ┐
CA1/applications/vm-2-mongodb/docker-compose.yml      ├─→ CA2/docker-compose.yml
CA1/applications/vm-3-processor/docker-compose.yml    │   (unified stack)
CA1/applications/vm-4-homeassistant/docker-compose.yml┘
```

#### Phase 3: Automation Scripts (Reuse 80% from CA1)
```
CA1/plant-monitor-IaC/
├── deploy.sh           → ADAPT (change deployment logic)
├── teardown.sh         → ADAPT (change teardown logic)
└── check-permissions.sh → REUSE AS-IS
```

---

## Specific Files to Copy

### Step 1: Copy Application Code
```bash
# Processor
cp -r CA1/applications/vm-3-processor/plant-care-processor/* CA2/applications/processor/

# Sensors
cp -r CA1/applications/vm-4-homeassistant/plant-sensors/* CA2/applications/sensor/

# Home Assistant config
cp -r CA1/applications/vm-4-homeassistant/config CA2/homeassistant-config/
cp -r CA1/applications/vm-4-homeassistant/mosquitto CA2/mosquitto-config/
```

### Step 2: Extract Docker Compose Services
From CA1, we already have working compose files for:
- ✅ Kafka + ZooKeeper (vm-1)
- ✅ MongoDB (vm-2)
- ✅ Processor (vm-3)
- ✅ Home Assistant + MQTT + Sensors (vm-4)

**These just need to be merged into one stack file with `deploy:` sections!**

---

## CA1 Grading Feedback - Improvements for CA2

### From Grading Feedback:

#### 1. **Security Groups** (12/15 → Target: 15/15)
**Issue**: Broad IAM policies, world-open ports (22, 8123, 1883)

**Fix for CA2**:
- ✅ Use least-privilege IAM policies (no FullAccess policies)
- ✅ Restrict SSH to specific CIDR or use bastion pattern
- ✅ Only expose Home Assistant UI publicly
- ✅ Internal services on overlay network only

#### 2. **MQTT Authentication** 
**Issue**: MQTT broker has no authentication

**Fix for CA2**:
- ✅ Use Docker secrets for MQTT credentials
- ✅ Configure mosquitto with username/password
- ✅ Store in Secrets Manager or Docker secrets

#### 3. **Home Assistant MQTT Setup**
**Issue**: Still requires manual configuration step

**Fix for CA2**:
- ✅ Pre-configure MQTT integration in Home Assistant config
- ✅ Automate entire setup with no manual steps

#### 4. **Automation Completeness** (4/5 → Target: 5/5)
**Add**:
- ✅ Linting integration (shellcheck, yamllint)
- ✅ Validation in deploy script
- ✅ Pre-flight checks

---

## Docker Compose Merge Strategy

### CA1's Working Kafka Setup (vm-1):
```yaml
version: '3.8'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.4.0
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
    volumes:
      - zookeeper-data:/var/lib/zookeeper/data
      - zookeeper-logs:/var/lib/zookeeper/log

  kafka:
    image: confluentinc/cp-kafka:7.4.0
    depends_on:
      - zookeeper
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      # ... more config
```

**This works! Just add `deploy:` sections for Swarm**

### CA1's Working MongoDB (vm-2):
```yaml
version: '3.8'
services:
  mongodb:
    image: mongo:6.0.4
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
    volumes:
      - mongodb-data:/data/db
      - ./init-db.js:/docker-entrypoint-initdb.d/init-db.js
```

**This works! Just convert env vars to Docker secrets**

---

## What's Actually NEW for CA2

### Truly New Components:
1. **Docker Swarm initialization** (2 commands)
   ```bash
   docker swarm init
   docker swarm join --token <token>
   ```

2. **Deploy section in compose file**
   ```yaml
   deploy:
     replicas: 2
     resources:
       limits:
         memory: 256M
   ```

3. **Docker secrets** (instead of env vars)
   ```yaml
   secrets:
     - mongo_password
   ```

4. **Overlay network** (built-in, one line)
   ```yaml
   networks:
     plant-network:
       driver: overlay
   ```

5. **Scaling demo script**
   ```bash
   docker service scale plant-monitoring_sensor=5
   ```

---

## Time Savings Estimate

### Without CA1 Reuse: ~10-12 hours
- Write Dockerfiles from scratch: 2-3 hours
- Debug application code: 2-3 hours
- Configure Kafka/MongoDB: 2-3 hours
- Set up Home Assistant: 2-3 hours
- Write automation: 2 hours

### With CA1 Reuse: ~4-5 hours
- ✅ Copy working code: 15 minutes
- ✅ Merge compose files: 1 hour
- ✅ Adapt Terraform: 1 hour
- ✅ Create Swarm init: 30 minutes
- ✅ Scaling demo: 30 minutes
- ✅ Documentation: 1.5 hours

**Time Saved: 6-7 hours (60% reduction!)**

---

## Action Plan

### Phase 1: Copy Working Components (30 min)
1. Copy processor code
2. Copy sensor code
3. Copy Home Assistant configs
4. Copy Mosquitto config

### Phase 2: Create Unified Docker Compose (1-2 hours)
1. Start with CA1's Kafka compose
2. Merge in MongoDB
3. Add processor
4. Add sensors
5. Add Home Assistant + MQTT
6. Add `deploy:` sections
7. Convert to Docker secrets

### Phase 3: Infrastructure (1-2 hours)
1. Adapt CA1's Terraform modules
2. Simplify for Swarm (no K8s complexity)
3. Add Swarm init to user_data

### Phase 4: Automation (1 hour)
1. Adapt CA1's deploy.sh
2. Adapt CA1's teardown.sh
3. Add scaling demo script
4. Add validation script

### Phase 5: Documentation (1.5 hours)
1. Copy CA1's README structure
2. Update for Swarm specifics
3. Add scaling results
4. Add network diagram

**Total: 4-6 hours to working system**

---

## Summary

✅ **Reuse ~70-80% of CA1 work**
✅ **Working application code** (processor, sensors)
✅ **Working service configs** (Kafka, MongoDB, HA)
✅ **Proven automation patterns** (deploy/teardown scripts)
✅ **Excellent documentation structure** (README template)

🆕 **Add for CA2**:
- Docker Swarm orchestration (simple!)
- Unified compose file
- Scaling demonstration
- Docker secrets
- Overlay networking

**This approach is much faster and lower risk than starting from scratch!**
