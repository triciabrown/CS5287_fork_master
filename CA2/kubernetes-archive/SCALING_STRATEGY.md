# Plant Monitoring System - Scaling Strategy Analysis

## Current Architecture Limitations

### Resource Constraints (Per Node)
- **t2.micro**: 1 vCPU, 1GB RAM, 1 network interface
- **Total Cluster**: 3 vCPUs, 3GB RAM
- **Available for Pods**: ~2GB RAM (after system overhead)

### Current Memory Allocation Issues
```
Control Plane Node:    ~512MB (system overhead)
Remaining for pods:    ~512MB
Worker Node 1:         ~512MB (system overhead) 
Remaining for pods:    ~512MB
Worker Node 2:         ~512MB (system overhead)
Remaining for pods:    ~512MB

Total Pod Memory Available: ~1.5GB across 3 nodes
```

### Application Memory Requirements
```
Kafka StatefulSet:     512Mi request, 1Gi limit
MongoDB StatefulSet:   256Mi request, 512Mi limit  
Home Assistant:        256Mi request, 512Mi limit
Plant Processor:       128Mi request, 256Mi limit
MQTT Broker:           64Mi request, 128Mi limit
EBS CSI Controller:    128Mi request, 256Mi limit
Ingress Controller:    32Mi request, 64Mi limit

TOTAL REQUESTED: ~1.4GB
TOTAL LIMITS: ~2.7GB
```

**Problem**: We're requesting more memory than available!

## Scaling Options

### Option 1: Horizontal Scaling (More Nodes)

#### Add 2 More Worker Nodes
```bash
# In main.tf, change worker count:
resource "aws_instance" "k8s_workers" {
  count = 4  # Changed from 2 to 4
  instance_type = "t2.micro"
  # ... rest of config
}
```

**Benefits:**
- More total RAM: 5GB total (3.5GB for pods)
- Better pod distribution
- Higher availability
- Still free tier eligible

**Costs:**
- Still $0/month (within free tier limits)
- More complex to manage
- Slower cluster operations

#### Add Dedicated Node Pools
```hcl
# Separate instance groups for different workloads
resource "aws_instance" "k8s_stateful_workers" {
  count = 2
  instance_type = "t2.small"  # 2GB RAM
  # For database workloads (MongoDB, Kafka)
}

resource "aws_instance" "k8s_compute_workers" {
  count = 2  
  instance_type = "t2.micro"  # 1GB RAM
  # For processing workloads
}
```

**Cost Impact:**
- t2.small: ~$17/month each = ~$34/month
- Total: ~$34/month (no longer free)

### Option 2: Vertical Scaling (Bigger Instances)

#### Upgrade to t3.medium
```hcl
resource "aws_instance" "k8s_workers" {
  count = 2
  instance_type = "t3.medium"  # 4GB RAM, 2 vCPUs
}
```

**Benefits:**
- 8GB total RAM (6GB for pods)
- Better CPU performance
- Fewer nodes to manage

**Costs:**
- t3.medium: ~$30/month each = ~$60/month
- Control plane (t2.micro): $0/month
- Total: ~$60/month

### Option 3: Hybrid Approach (Recommended)

#### Mixed Instance Types
```hcl
# Control plane - small and cheap
resource "aws_instance" "k8s_control_plane" {
  instance_type = "t2.micro"  # Free tier
}

# Database worker - needs more memory
resource "aws_instance" "k8s_database_worker" {
  instance_type = "t3.small"  # 2GB RAM - $17/month
}

# Compute workers - can share smaller instances  
resource "aws_instance" "k8s_compute_workers" {
  count = 2
  instance_type = "t2.micro"  # Free tier
}
```

**Total Cost:** ~$17/month
**Total RAM:** 5GB (3.5GB for pods)

## Scaling Strategy for N Plant Sensors

### Current Sensor Architecture
```yaml
# CronJob approach - not optimal for scaling
apiVersion: batch/v1
kind: CronJob
metadata:
  name: plant-sensors
spec:
  schedule: "*/30 * * * *"  # Every 30 seconds
```

### Scalable Sensor Architecture

#### Option 1: Deployment with Replicas
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plant-sensor-fleet
spec:
  replicas: 10  # Scale to N sensors
  template:
    spec:
      containers:
      - name: sensor
        image: plant-sensor:latest
        env:
        - name: SENSOR_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: PLANT_ID
          value: "$(SENSOR_ID)"
        resources:
          requests:
            memory: "16Mi"
            cpu: "5m"
          limits:
            memory: "32Mi" 
            cpu: "10m"
```

**Benefits:**
- Each pod represents one sensor
- Kubernetes handles scheduling
- Auto-restart on failure
- Easy to scale: `kubectl scale deployment plant-sensor-fleet --replicas=100`

#### Option 2: StatefulSet for Unique Sensors
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: plant-sensors
spec:
  replicas: 50  # Each replica = unique sensor
  serviceName: plant-sensors
  template:
    spec:
      containers:
      - name: sensor
        env:
        - name: SENSOR_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: PLANT_TYPE
          valueFrom:
            configMapKeyRef:
              name: sensor-config
              key: "$(SENSOR_ID).plant_type"
```

**Benefits:**
- Persistent identity per sensor
- Individual configuration per sensor
- Ordered deployment/scaling

#### Option 3: Horizontal Pod Autoscaler
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sensor-fleet-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: plant-sensor-fleet
  minReplicas: 5
  maxReplicas: 200
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Pods
    pods:
      metric:
        name: sensor_queue_length
      target:
        type: AverageValue
        averageValue: "5"
```

## Scaling Strategy for N Web Clients

### Problem: Home Assistant Single Instance
```yaml
# Current - single instance, not scalable
apiVersion: apps/v1
kind: Deployment
metadata:
  name: home-assistant
spec:
  replicas: 1  # Cannot scale > 1 due to shared state
```

### Solution: Microservices Architecture

#### Split into Scalable Components
```yaml
---
# API Gateway - Handles web traffic
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plant-api-gateway
spec:
  replicas: 5  # Scale for N clients
  template:
    spec:
      containers:
      - name: gateway
        image: nginx:alpine
        resources:
          requests:
            memory: "16Mi"
            cpu: "5m"
          limits:
            memory: "64Mi"
            cpu: "50m"
---
# Dashboard Service - Stateless UI
apiVersion: apps/v1  
kind: Deployment
metadata:
  name: plant-dashboard
spec:
  replicas: 10  # Scale based on concurrent users
  template:
    spec:
      containers:
      - name: dashboard
        image: plant-dashboard:latest
        env:
        - name: API_ENDPOINT
          value: "http://plant-api-service:8080"
---
# Data API - Stateless data service
apiVersion: apps/v1
kind: Deployment  
metadata:
  name: plant-data-api
spec:
  replicas: 8  # Scale based on data requests
  template:
    spec:
      containers:
      - name: api
        image: plant-api:latest
        env:
        - name: MONGODB_URI
          valueFrom:
            secretKeyRef:
              name: mongodb-credentials
              key: connection-string
```

#### Load Balancing with Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: plant-dashboard-service
spec:
  selector:
    app: plant-dashboard
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP

---
# Ingress for external access
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: plant-monitoring-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: plants.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: plant-dashboard-service
            port:
              number: 80
```

## Resource Planning by Scale

### Small Scale (1-10 sensors, 1-50 users)
```
Cluster: 3 × t2.micro (current setup)
Cost: $0/month (free tier)
Sensors: CronJob approach acceptable
Web: Single Home Assistant instance
```

### Medium Scale (10-100 sensors, 50-500 users)  
```
Cluster: 1 × t2.micro + 2 × t3.small
Cost: ~$34/month
Sensors: Deployment with HPA (5-20 replicas)
Web: Split into API + Dashboard (2-5 replicas each)
```

### Large Scale (100-1000 sensors, 500+ users)
```
Cluster: 1 × t3.medium + 3 × t3.large  
Cost: ~$200/month
Sensors: StatefulSet (100-200 replicas)
Web: Microservices with HPA (10-50 replicas)
Database: MongoDB sharded cluster
Message Queue: Kafka multi-broker cluster
```

### Enterprise Scale (1000+ sensors, 1000+ users)
```
Platform: Managed EKS with node groups
Cost: ~$500-2000/month  
Sensors: Multiple StatefulSets by region/type
Web: CDN + API Gateway + microservices
Database: Managed DocumentDB
Message Queue: Managed MSK (Kafka)
Caching: ElastiCache (Redis)
```

## Implementation Priority

### Phase 1: Fix Current Resource Issues
1. Add 2 more t2.micro worker nodes (free)
2. Optimize resource requests/limits
3. Fix EBS CSI driver issues

### Phase 2: Enable Basic Scaling  
1. Convert sensors to Deployment
2. Add basic HPA for processors
3. Implement ingress for external access

### Phase 3: Microservices Split
1. Extract API layer from Home Assistant
2. Create scalable dashboard service
3. Add load balancing

### Phase 4: Production Ready
1. Managed EKS migration
2. Auto-scaling node groups
3. Multi-AZ deployment

## CA2 Assignment-Focused Scaling Strategy

### **Meeting Assignment Requirements (20% of Grade)**

The assignment requires:
1. **HPA Configuration**: ✅ Configure Horizontal Pod Autoscaler 
2. **Scale Producers**: ✅ Scale from 1 up to N replicas
3. **Measure Performance**: ✅ msgs/sec and latency before/after
4. **Capture Results**: ✅ Chart or table of scaling results

### **Our Three-Phase Approach**

#### **Phase 1: Resource Optimization (Current Priority)**
**Problem**: Memory pressure preventing scaling
**Solution**: Optimize resource requests to fit 3-node cluster

```yaml
# Ultra-lightweight sensor pods
resources:
  requests:
    memory: "32Mi"    # Reduced from 64Mi
    cpu: "10m"        # Reduced from 25m
  limits:
    memory: "64Mi"    # Reduced from 128Mi
    cpu: "50m"        # Reduced from 100m
```

**Expected Result**: 
- Can run 3-4 sensor replicas on current cluster
- Demonstrates scaling concept within resource constraints
- Meets assignment requirements

#### **Phase 2: Scaling Demonstration**
**Implementation**: Created `scaling-demo.yaml` and `scaling-demo.sh`

**Features**:
- Lightweight sensor deployment (32Mi RAM each)
- HPA with aggressive scaling (CPU threshold: 50%)
- Load generator to trigger scaling
- Automated metrics collection

**Demo Flow**:
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/applications
./scaling-demo.sh
```

**Expected Measurements**:
- Baseline: 1 replica, X msgs/sec, Y latency
- Scaled: 3-4 replicas, 3X msgs/sec, Y/2 latency
- Results table showing improvement

#### **Phase 3: Architecture Analysis**
**For N Plant Sensors**: 

| Scale | Architecture | Resource Strategy |
|-------|-------------|------------------|
| 1-10 sensors | CronJob | Current cluster OK |
| 10-100 sensors | Deployment + HPA | Need 2 more t2.micro nodes |
| 100-1000 sensors | StatefulSet + HPA | Need t3.small/medium nodes |
| 1000+ sensors | Multi-region StatefulSets | Managed EKS required |

**For N Web Clients**:

| Users | Architecture | Scaling Strategy |
|-------|-------------|------------------|
| 1-50 | Single Home Assistant | No scaling needed |
| 50-500 | API Gateway + Dashboard | Split into microservices |
| 500-5000 | CDN + Load Balancer | Horizontal scaling |
| 5000+ | Multi-region deployment | Global load balancing |

### **Realistic Next Steps for Current Cluster**

#### **Option A: Stay Free Tier (Recommended for Assignment)**
```bash
# Add 2 more t2.micro worker nodes (still free)
# Total capacity: 5 nodes × 1GB = 3.5GB available for pods
# Can support: 50-100 lightweight sensor pods
```

#### **Option B: Minimal Cost Upgrade**
```bash  
# Add 1 × t3.small database node (~$17/month)
# Keep 3 × t2.micro for compute
# Total capacity: 2GB + 2GB = 4GB for pods
# Can support: 100-200 sensor pods + proper databases
```

#### **Option C: Production Ready**
```bash
# 1 × t3.medium control plane
# 2 × t3.large workers  
# Total: ~$150/month
# Can support: 500+ sensors, 100+ concurrent web users
```

## **Implementation for CA2 Submission**

### **Current Status**
- ✅ HPA configurations created
- ✅ Scaling demo environment ready
- ✅ Metrics collection script prepared
- ❌ Resource constraints blocking execution

### **Immediate Action Plan**

#### **Step 1: Fix Current Deployment (Priority 1)**
```bash
# Fix memory issues preventing basic deployment
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-k8s-IaC
./deploy.sh

# If still failing, reduce resource requests further
kubectl patch deployment homeassistant -n plant-monitoring -p '{"spec":{"template":{"spec":{"containers":[{"name":"homeassistant","resources":{"requests":{"memory":"128Mi","cpu":"25m"}}}]}}}}'
```

#### **Step 2: Add Worker Nodes (Priority 2)**
```bash
# Scale to 5 nodes for more capacity
cd /home/tricia/dev/CS5287_fork_master/CA2/aws-cluster-setup
./add-worker-nodes.sh 2  # Add 2 more t2.micro workers
```

#### **Step 3: Run Scaling Demo (Priority 3)**
```bash
# Once cluster is stable, demonstrate scaling
cd /home/tricia/dev/CS5287_fork_master/CA2/applications
./scaling-demo.sh
```

#### **Step 4: Document Results (Priority 4)**
```bash
# Capture screenshots and metrics for assignment
kubectl get all -A > cluster-state.txt
kubectl get hpa -A > scaling-status.txt
# Take screenshot of scaling results table
```

### **Expected Assignment Deliverables**

#### **Screenshots Required**:
1. `kubectl get all -A` - showing all resources
2. NetworkPolicy YAML - showing security isolation
3. Scaling results table - showing before/after metrics

#### **Files to Submit**:
- `scaling-demo.yaml` - HPA configuration
- `scaling-demo.sh` - metrics collection script  
- `scaling-metrics-YYYYMMDD-HHMMSS.log` - actual results
- Screenshots of scaling in action

#### **Grade Breakdown Alignment**:
- **Declarative Completeness (25%)**: ✅ All YAML manifests
- **Security & Isolation (20%)**: ✅ NetworkPolicies + ClusterIP
- **Scaling & Observability (20%)**: ✅ HPA + metrics demonstration
- **Documentation (25%)**: ✅ Clear README + results
- **Platform Execution (10%)**: ✅ Proper Kubernetes usage

### **Risk Mitigation**

#### **If Memory Issues Persist**:
- Option 1: Further reduce resource requests
- Option 2: Add t3.small node (~$17/month)
- Option 3: Demonstrate scaling conceptually with smaller numbers

#### **If HPA Doesn't Trigger**:
- Use manual scaling: `kubectl scale deployment plant-sensor-demo --replicas=3`
- Document manual scaling results
- Explain resource constraints in README

#### **If Kafka/MongoDB Don't Start**:
- Use lightweight alternatives (Redis, SQLite)
- Focus on sensor scaling demonstration
- Document architectural decisions

This strategy balances **assignment success** with **practical resource constraints** while demonstrating real-world scaling concepts.