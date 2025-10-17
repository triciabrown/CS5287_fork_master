# Kubernetes Implementation - Complete Archive & Lessons Learned

**Date**: October 3-16, 2025  
**Project**: CS5287 CA2 - Plant Monitoring System PaaS  
**Status**: Archived - Migrated to Docker Swarm  
**Author**: Tricia Brown

---

## Executive Summary

This document archives the complete Kubernetes implementation effort, including all troubleshooting, lessons learned, and the rationale for migrating to Docker Swarm. The Kubernetes implementation demonstrated deep learning of container orchestration concepts but proved impractical for t2.micro resource constraints.

### Key Statistics
- **Time Invested**: ~25-30 hours of configuration and troubleshooting (October 3-16)
- **Infrastructure**: 5-node cluster (1 control plane + 4 workers, all t2.micro)
- **Resource Challenge**: 1GB RAM per node vs. K8s requiring 500MB+ for system components
- **Success Rate**: Cluster formed successfully 2-3 times, but unstable
- **Major Issues Resolved**: 
  - EBS CSI driver registration (6-8 hours)
  - MongoDB/Kafka health probes (4-6 hours)
  - Network policies blocking kubelet (2 hours)
  - Kafka KRaft configuration (6-8 hours)
  - Service discovery and DNS (2 hours)
- **Primary Blocker**: Worker nodes repeatedly failing to join cluster despite fixes

---

## Chronological Timeline

### Week 1: October 3-6 (Initial Setup Phase)
- **October 3**: EBS CSI driver issues discovered - PVCs stuck in Pending
- **October 4**: Fixed CSI driver (missing containers, RBAC)
- **October 4**: Researched ingress controllers (postponed due to cost/complexity)
- **October 5**: MongoDB/Kafka health probe failures, bind IP issues
- **October 5**: Network policy blocking kubelet health checks
- **October 6**: Fixed MongoDB security warnings, probe configuration

### Week 2: October 15-16 (Stability Attempts)
- **October 15 Morning**: Worker join failures via bastion (SSH agent issue)
- **October 15 Midday**: Deploy script cleanup (removed duplicates)
- **October 15 Afternoon**: MongoDB connectivity fixed (--bind_ip 0.0.0.0)
- **October 15 Afternoon**: Kafka cluster ID issues (KRaft base64 UUID)
- **October 15 Late Afternoon**: Python kubernetes library installation issues
- **October 15 Evening**: Kafka resource tuning (memory, heap, probes)
- **October 15 Evening**: Kafka service discovery failure (wrong service name)
- **October 15 Late Evening**: Refactored Kafka init script to ConfigMap
- **October 15 Night**: Lost+found directory issue, OutOfMemory errors
- **October 16 Morning**: **Worker join failures resumed** (migration decision)

### Total Sessions: ~8-10 troubleshooting sessions
### Total Time: ~25-30 hours
### Issues Resolved: 15+ distinct problems
### Final Blocker: Intermittent worker join failures despite comprehensive fixes

---

## Complete Troubleshooting History

### Phase 0: Initial EBS CSI Driver Issues (October 3-5)

#### Issue 1: PVCs Stuck in Pending - CSI Node Registration Failure

**Date**: October 3-5, 2025

**Symptoms**:
- MongoDB and Kafka PVCs stuck in `Pending` state
- CSI nodes had no drivers registered
- Storage provisioning completely blocked
- Error: "waiting for first consumer to be created before binding"

**Investigation**:
```bash
kubectl get csinodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.drivers[*].name}{"\n"}{end}'
# OUTPUT: Node names shown but no drivers listed (should show ebs.csi.aws.com)
```

**Root Causes Discovered**:
1. **Missing csi-attacher container** in EBS CSI controller deployment
2. **Insufficient RBAC permissions** - missing `patch` and `update` for PersistentVolumes
3. **Missing node-driver-registrar** container in node DaemonSet
4. **Topology label conflicts** - manual labels conflicting with auto-detection

**Solutions Implemented**:
1. Added csi-attacher container to controller deployment
2. Updated ClusterRole with full PV permissions
3. Added node-driver-registrar sidecar to node pods
4. Removed manual topology labeling from deploy script

**Outcome**: ✅ EBS CSI driver fully functional, PVCs binding successfully

**Files Modified**:
- `applications/aws-ebs-csi-driver.yaml` - Added missing containers and RBAC
- `plant-monitor-k8s-IaC/deploy.sh` - Removed manual topology labeling

**Time Investment**: ~6-8 hours over 2 days

---

#### Issue 2: MongoDB and Kafka Not Becoming Ready - Health Probe Failures

**Date**: October 5-6, 2025

**Symptoms**:
- MongoDB: `0/1 Running` with continuous restarts
- Kafka: `0/1 Running` stuck at configuration stage  
- Health check probes timing out
- Deploy script timing out waiting for StatefulSets

**MongoDB Root Causes**:
1. **Bind IP Issue**: MongoDB bound to localhost (127.0.0.1) only
   - Kubernetes probes come from pod network, not localhost
   - Other pods couldn't connect either
2. **Probe Complexity**: exec probe using `mongosh --eval` was unreliable
   - Command timing out
   - No authentication provided for probe
3. **Security Warnings** (production issues):
   - Access control disabled (no authentication)
   - Running as root user
   - vm.max_map_count too low (65530 vs recommended 1677720)

**MongoDB Solutions**:
1. Added `--bind_ip_all` flag to MongoDB command
2. Changed from exec probes to tcpSocket probes (more reliable)
3. Added securityContext to run as non-root (user 999)
4. Enabled authentication with `--auth` flag
5. Increased WiredTiger cache from 0.1GB to 0.25GB (minimum requirement)

**Configuration Changes**:
```yaml
# Before:
command: ["mongod", "--wiredTigerCacheSizeGB", "0.1"]
livenessProbe:
  exec:
    command: ["mongosh", "--eval", "db.adminCommand('ping')"]

# After:
command: ["mongod", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all", "--auth"]
livenessProbe:
  tcpSocket:
    port: 27017
  initialDelaySeconds: 30
securityContext:
  runAsUser: 999
  runAsGroup: 999
  fsGroup: 999
```

**Kafka Root Causes**:
1. Volume permissions issues with KRaft metadata directory
2. Resource constraints during startup
3. Insufficient probe delays for t2.micro

**Kafka Solutions**:
1. Added securityContext with fsGroup: 1000
2. Increased memory limits
3. Extended probe initialDelaySeconds

**Outcome**: ✅ Both MongoDB and Kafka eventually becoming Ready (intermittently)

**Files Modified**:
- `ansible-k8s-deployment/deploy-applications.yml` - MongoDB command, probes, security
- `ansible-k8s-deployment/group_vars/all.yml` - Resource limits

**Time Investment**: ~4-6 hours

---

#### Issue 3: Network Policy Blocking Health Checks

**Date**: October 5, 2025

**Symptoms**:
- Pods passing health checks initially
- After applying network policies, health checks failed
- Pods showing as NotReady despite being functional

**Root Cause**: Network policies were too restrictive, blocking kubelet health check traffic

**Solution**: Added exceptions for health check ports
```yaml
ingress:
- from: []  # Allow from anywhere for health checks
  ports:
  - protocol: TCP
    port: 27017  # MongoDB
  - protocol: TCP
    port: 9092   # Kafka
```

**Outcome**: ✅ Health checks working with network policies applied

**Files Modified**:
- `applications/network-policy.yaml` - Added kubelet exceptions

---

#### Issue 4: Deprecated MongoDB Options

**Date**: October 4, 2025

**Symptoms**:
```
Error: unrecognized option: --smallfiles
Error: unrecognized option: --nojournal
```

**Root Cause**: MongoDB 6.0+ removed these legacy options

**Solution**: Removed deprecated flags from command

**Files Modified**:
- `ansible-k8s-deployment/deploy-applications.yml`

---

#### Issue 5: Kafka Resource Validation Errors

**Date**: October 4, 2025

**Symptoms**:
```
Error: resources.requests.memory is greater than resources.limits.memory
```

**Root Cause**: Configuration had memory request = 200Mi but limit = 100Mi

**Solution**: Fixed memory limits to be >= requests

**Files Modified**:
- `ansible-k8s-deployment/group_vars/all.yml`

---

### Phase 0.5: Ingress Controller Exploration (October 3-4)

**Goal**: Replace NodePort with production-ready ingress setup for Home Assistant

**Investigation**:
- Researched nginx-ingress vs AWS Load Balancer Controller
- Considered AWS Application Load Balancer (ALB) integration
- Evaluated SSL/TLS termination options

**Challenges Discovered**:
1. **Cost Concerns**: AWS ALB costs ~$16-23/month (outside free tier)
2. **Resource Overhead**: Ingress controllers add 100-200MB memory overhead
3. **Complexity**: Additional components to troubleshoot with limited resources
4. **Free Tier Priority**: Decided to focus on core functionality first

**Decision**: Postponed ingress implementation to focus on getting core StatefulSets working

**Status**: Kept NodePort for development, documented ingress as future enhancement

**Files Created (Deprecated)**:
- `applications/deprecated-ingress/ingress-controller-lite.yaml`
- `applications/deprecated-ingress/ingress.yaml`
- `applications/deprecated-ingress/setup-ingress-lite.sh`

---

### Phase 1: Initial Cluster Setup (October 15, Morning)
**Issue**: Worker nodes failing to join Kubernetes cluster via bastion host

**Symptoms**:
- Control plane initialized successfully
- `kubeadm join` commands timing out on workers
- SSH agent not persisting between deploy script executions

**Root Cause**: SSH agent not running when Ansible tried to connect through bastion

**Solution Implemented**:
```bash
# Added to deploy.sh (lines 27-48)
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/k8s-cluster-key
ssh-add -l  # Verify key loaded
```

**Outcome**: ✅ All 5 nodes joined cluster successfully

**Files Modified**:
- `plant-monitor-k8s-IaC/deploy.sh` - Automatic SSH agent setup

---

### Phase 2: Deploy Script Cleanup (October 15, Midday)
**Issue**: Duplicate worker joining logic in deploy script

**Symptoms**:
- Deploy script had two separate worker joining sections
- Redundant SSH commands and error handling
- Confusion about which section was actually working

**Solution**: Consolidated worker joining logic into single cohesive block

**Outcome**: ✅ Cleaner, more maintainable deployment code

**Files Modified**:
- `plant-monitor-k8s-IaC/deploy.sh` - Removed duplicate worker joining code

---

### Phase 3: MongoDB Connectivity Issues (October 15, Afternoon)
**Issue**: MongoDB StatefulSet stuck in CrashLoopBackOff

**Symptoms**:
```
MongoDB logs: "waiting for connections on port 27017"
Processor logs: "connection refused to mongodb-0:27017"
MongoDB binding to 127.0.0.1 only
```

**Root Cause**: MongoDB default configuration binds to localhost only

**Solution**: Added `--bind_ip 0.0.0.0` flag to MongoDB command

**Configuration**:
```yaml
# deploy-applications.yml (lines 88-92)
command: ["mongod", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip", "0.0.0.0"]
```

**Outcome**: ✅ MongoDB accepted connections from other pods

**Files Modified**:
- `ansible-k8s-deployment/deploy-applications.yml` - MongoDB command args

---

### Phase 4: Kafka Cluster ID Problems (October 15, Afternoon)
**Issue**: Kafka rejecting cluster ID "kafka-cluster-1"

**Symptoms**:
```
Error: Cluster ID kafka-cluster-1 is not a valid base64 encoded UUID
Kafka crash loop at startup
```

**Root Cause**: KRaft mode requires base64-encoded UUID, not arbitrary string

**Solution**: Generated proper UUID and encoded it
```bash
# Generated UUID: 11c860cc-2bf9-4fb3-a363-4c083f21555f
# Base64 encoded: EchgzCv5T7OjY0wIPyFVXw
```

**Outcome**: ✅ Kafka accepted cluster ID

**Files Modified**:
- `ansible-k8s-deployment/deploy-applications.yml` - CLUSTER_ID value
- `ansible-k8s-deployment/group_vars/all.yml` - Kafka cluster ID variable

---

### Phase 5: Python Kubernetes Library Missing (October 15, Late Afternoon)
**Issue**: Ansible kubernetes.core module failing

**Symptoms**:
```
fatal: [localhost]: FAILED! => {"msg": "Failed to import the required Python library (kubernetes)"}
```

**Root Cause**: Ansible installed in pipx isolated environment, couldn't access system Python libraries

**Solution**: Multi-method installation approach
1. Try installing in pipx environment
2. Fallback to apt-get install python3-kubernetes
3. Final fallback to pip install

**Implementation**:
```bash
# deploy.sh (lines 311-343)
if pipx runpip ansible install kubernetes; then
    echo "✅ Installed via pipx"
elif sudo apt-get install -y python3-kubernetes; then
    echo "✅ Installed via apt-get"
else
    pip install kubernetes
fi
```

**Outcome**: ✅ Ansible could manage Kubernetes resources

**Files Modified**:
- `plant-monitor-k8s-IaC/deploy.sh` - Enhanced Python library installation

---

### Phase 6: Kafka Resource Constraints (October 15, Evening)
**Issue**: Kafka crash looping with connection timeouts

**Symptoms**:
```
Kafka logs: "Connection refused" to localhost:9093
Liveness probe failing at 30 seconds
Kafka pod restarting repeatedly
```

**Root Cause**: t2.micro startup time exceeded probe delays, insufficient memory allocation

**First Attempt**: Reduced memory from 250Mi to 180Mi, JVM heap from 128M to 96M
- **Result**: Started faster but still crashed

**Second Attempt**: Increased probe delays
- Liveness: 30s → 90s
- Readiness: 10s → 60s
- **Result**: ✅ Kafka briefly reached READY state (1/1)

**Outcome**: Partial success - proved startup was possible but unstable

**Files Modified**:
- `ansible-k8s-deployment/group_vars/all.yml` - Reduced memory limits
- `ansible-k8s-deployment/deploy-applications.yml` - Increased probe delays

---

### Phase 7: Kafka Service Discovery Failure (October 15, Evening)
**Issue**: Kafka crashing after brief success with metadata sync error

**Symptoms**:
```
Error: RuntimeException: Received a fatal error while waiting for broker to catch up with cluster metadata
CancellationException in metadata synchronization
Kafka reached READY then immediately crashed
```

**Investigation**:
```bash
kubectl get svc | grep kafka
# OUTPUT: kafka-service (wrong name!)

kubectl exec kafka-0 -- nslookup kafka-0.kafka-headless
# OUTPUT: DNS lookup failed
```

**Root Cause**: Service named "kafka-service" but Kafka configuration expected "kafka-headless"

**Solution**: Renamed service and added controller port
```yaml
# Changed from:
name: kafka-service

# Changed to:
name: kafka-headless
ports:
  - port: 9092
    name: broker
  - port: 9093  # ADDED
    name: controller
```

**Outcome**: ✅ DNS resolution working, metadata sync possible

**Files Modified**:
- `ansible-k8s-deployment/deploy-applications.yml` - Service name and ports

---

### Phase 8: Kafka Init Container Refactoring (October 15, Late Evening)
**Issue**: Inline bash script in YAML was becoming unwieldy

**User Request**: "Can we have a separate script instead of executing so much code in the yml file?"

**Solution**: Created dedicated init script with ConfigMap
1. Created `kafka-init-storage.sh` with proper error handling
2. Added ConfigMap to mount script into pod
3. Simplified init container to call script

**Implementation**:
```yaml
# ConfigMap
kind: ConfigMap
metadata:
  name: kafka-init-storage
data:
  init-storage.sh: |
    {{ lookup('file', 'kafka-init-storage.sh') }}

# Init Container
initContainers:
- name: kafka-format-storage
  command: ["/bin/bash", "/scripts/init-storage.sh"]
  volumeMounts:
  - name: kafka-init-script
    mountPath: /scripts
```

**Benefits**:
- Cleaner YAML structure
- Easier to debug and modify
- Better separation of concerns
- Script reusability

**Outcome**: ✅ Improved maintainability

**Files Created**:
- `ansible-k8s-deployment/kafka-init-storage.sh`

**Files Modified**:
- `ansible-k8s-deployment/deploy-applications.yml` - ConfigMap and init container

---

### Phase 9: Lost+Found Directory Issue (October 15, Night)
**Issue**: Kafka crashing with filesystem error

**Symptoms**:
```
Error: Found directory /var/lib/kafka/data/lost+found
'lost+found' is not in the form of topic-partition
KafkaException during log directory loading
```

**Root Cause**: EBS volumes formatted as ext4 automatically create `lost+found` directory

**Solution**: Modified init script to remove it
```bash
if [ -d /var/lib/kafka/data/lost+found ]; then
  echo "Removing lost+found directory..."
  rm -rf /var/lib/kafka/data/lost+found
fi
```

**Outcome**: ✅ Kafka no longer crashed on filesystem issues

**Files Modified**:
- `ansible-k8s-deployment/kafka-init-storage.sh` - Added lost+found cleanup

---

### Phase 10: Kafka OutOfMemory Errors (October 15, Night)
**Issue**: Kafka crashing with Java heap space errors

**Symptoms**:
```
Error: java.lang.OutOfMemoryError: Java heap space
Crash during LogCleaner startup
Memory: 180Mi limit, 96M JVM heap
```

**Root Cause**: 96M heap insufficient for Kafka's internal structures

**Solution**: Increased allocation
- Memory limit: 180Mi → 256Mi
- JVM heap: 96M → 160M

**Rationale**: Kafka needs ~160M minimum for:
- Log cleaner offset maps
- Metadata caching
- Controller operations
- Network buffers

**Outcome**: ⚠️ Deployment updated but not verified (ran out of time)

**Files Modified**:
- `ansible-k8s-deployment/group_vars/all.yml` - Increased kafka_memory_limit
- `ansible-k8s-deployment/deploy-applications.yml` - Increased KAFKA_HEAP_OPTS

---

### Phase 11: Worker Join Failures Resume (October 16, Morning)
**Issue**: After full teardown and redeploy, workers failing to join again

**Symptoms**:
- Control plane initializes successfully
- Worker kubeadm join commands timing out
- Same pattern as Phase 1, despite SSH agent fixes still in place

**Attempted Solution**: Re-ran deploy.sh

**Outcome**: ❌ Workers still not joining

**Analysis**: 
- SSH agent setup is in the code
- Same configuration that worked before
- Intermittent success suggests environmental instability
- Possible race conditions in cluster initialization
- Network timing issues with bastion pattern

**Decision Point**: This recurring failure, combined with resource constraints, triggered migration decision

---

## Resource Analysis: Kubernetes vs. Application Workload

### Kubernetes System Overhead

#### Control Plane (t2.micro - 1GB RAM)
| Component | Memory Usage |
|-----------|--------------|
| etcd | ~100-150MB |
| kube-apiserver | ~80-120MB |
| kube-controller-manager | ~60-80MB |
| kube-scheduler | ~40-60MB |
| kubelet | ~50-80MB |
| Container runtime | ~50-100MB |
| **Total System** | **~400-600MB** |
| **Remaining for Apps** | **~400-600MB** |

#### Worker Nodes (t2.micro - 1GB RAM each)
| Component | Memory Usage |
|-----------|--------------|
| kubelet | ~50-80MB |
| kube-proxy | ~30-50MB |
| Container runtime | ~50-100MB |
| Flannel CNI | ~30-50MB |
| **Total System** | **~160-280MB** |
| **Remaining for Apps** | **~720-840MB** |

### Application Requirements
| Application | Memory Request | Memory Limit | Notes |
|------------|----------------|--------------|-------|
| MongoDB | 128Mi | 256Mi | WiredTiger cache 0.25GB |
| Kafka | 200Mi | 256Mi | JVM heap 160M |
| Processor | 32Mi | 64Mi | Python app |
| Sensor (x2) | 32Mi each | 64Mi each | Lightweight |
| HomeAssistant | 128Mi | 200Mi | Web interface |
| **Total** | **552Mi** | **904Mi** | For single replica of each |

### Resource Constraint Analysis

**Problem**: With 4 worker nodes (t2.micro):
- **Total worker memory**: 4 × 1GB = 4GB
- **K8s system overhead**: 4 × ~200MB = ~800MB
- **Available for apps**: ~3.2GB
- **Required for apps**: ~900MB (single replica) or ~1.8GB (with some HA)

**Looks fine on paper, but...**

**Reality**:
1. Memory limits are not hard guarantees - pods can burst
2. JVM garbage collection causes spikes
3. Init containers add temporary memory pressure
4. Image pulls consume memory temporarily
5. System processes (kernel, SSH, monitoring) not accounted for
6. No headroom for troubleshooting tools (debug pods, etc.)

**The Real Issue**: Running too close to limits causes:
- Pods getting OOMKilled randomly
- Scheduling failures
- Node NotReady states
- Unpredictable behavior

---

## Technical Lessons Learned

### Kubernetes Concepts Mastered
1. ✅ **Cluster Architecture**: Control plane vs. worker node roles
2. ✅ **Networking**: CNI plugins (Flannel), service types, DNS
3. ✅ **Storage**: PersistentVolumes, PVCs, StorageClasses, StatefulSets
4. ✅ **Workload Types**: Deployments, StatefulSets, DaemonSets
5. ✅ **Configuration**: ConfigMaps, Secrets, environment variables
6. ✅ **Health Checks**: Liveness and readiness probes
7. ✅ **Resource Management**: Requests, limits, QoS classes
8. ✅ **Security**: RBAC, NetworkPolicies, security contexts
9. ✅ **Init Containers**: Storage formatting, dependency checks
10. ✅ **Troubleshooting**: kubectl logs, describe, exec, events

### Infrastructure as Code Skills
1. ✅ **Terraform**: AWS resource provisioning, EC2, VPC, security groups
2. ✅ **Ansible**: Configuration management, playbooks, roles, variables
3. ✅ **Bash Scripting**: Complex deployment automation, error handling
4. ✅ **SSH Management**: Bastion hosts, agent forwarding, key management

### Application-Specific Learnings
1. ✅ **Kafka in KRaft Mode**: Controller-only deployment, metadata management
2. ✅ **MongoDB Clustering**: Bind addresses, authentication, storage
3. ✅ **JVM Tuning**: Heap sizing, GC configuration for constrained environments
4. ✅ **Container Networking**: Service discovery, DNS, port exposure

### What Didn't Work Well
1. ❌ **t2.micro for K8s**: Barely sufficient, no room for growth
2. ❌ **Bastion Pattern**: Added complexity, intermittent connectivity
3. ❌ **Inline Scripts**: Messy YAML, hard to debug (fixed late)
4. ❌ **Trial-and-Error Tuning**: Memory/heap settings took many iterations
5. ❌ **No Monitoring Stack**: Couldn't see actual resource usage patterns

---

## Why Docker Swarm is Better for This Project

### 1. Resource Efficiency
| Metric | Kubernetes | Docker Swarm | Savings |
|--------|-----------|--------------|---------|
| Manager Node Overhead | ~500MB | ~150MB | 350MB |
| Worker Node Overhead | ~200MB | ~75MB | 125MB per node |
| Total System (5 nodes) | ~1.3GB | ~450MB | ~850MB |
| **Memory for Apps** | **~2.7GB** | **~3.5GB** | **+30%** |

### 2. Operational Simplicity
| Task | Kubernetes | Docker Swarm |
|------|-----------|--------------|
| Cluster Init | `kubeadm init` + CNI + join tokens | `docker swarm init` |
| Node Join | `kubeadm join` with discovery | `docker swarm join --token` |
| Deploy App | YAML manifest + kubectl apply | Docker Compose file + stack deploy |
| Check Status | `kubectl get all -A` | `docker service ls` |
| View Logs | `kubectl logs <pod>` | `docker service logs <service>` |
| Troubleshoot | Pods, Events, Describe | Container logs, inspect |

### 3. Networking
- **Kubernetes**: Requires CNI plugin (Flannel, Calico), separate service objects
- **Docker Swarm**: Built-in overlay networking, routing mesh included

### 4. Storage
- **Kubernetes**: StorageClass, PVC, PV abstractions, CSI drivers
- **Docker Swarm**: Docker volumes, simpler but adequate for this use case

### 5. Learning Curve
- **Kubernetes**: Steep, many concepts (Pods, Deployments, Services, Ingress, etc.)
- **Docker Swarm**: Gentle, extends Docker Compose knowledge

### 6. Development Workflow
- **Kubernetes**: Different from local Docker development
- **Docker Swarm**: Nearly identical to `docker-compose` workflow

---

## Configuration Files Archive

All Kubernetes configuration files preserved in `/kubernetes-archive/` directory:

### Infrastructure (Terraform)
- `aws-cluster-setup/main.tf` - Complete AWS infrastructure
- `aws-cluster-setup/TERRAFORM_EXPLAINED.md` - Detailed explanations

### Ansible Deployment
- `ansible-k8s-deployment/deploy-applications.yml` - Main playbook
- `ansible-k8s-deployment/group_vars/all.yml` - Configuration variables
- `ansible-k8s-deployment/kafka-init-storage.sh` - Init container script
- `ansible-k8s-deployment/deploy.sh` - Wrapper script with SSH agent setup

### Kubernetes Manifests
- `applications/homeassistant.yaml` - Home Assistant deployment
- `applications/security-rbac.yaml` - RBAC configuration
- `applications/security-contexts.yaml` - Pod security contexts
- `applications/network-policy.yaml` - Network policies
- `applications/hpa-config.yaml` - Horizontal Pod Autoscaler

### Documentation
- `TODO-Kafka-Testing.md` - Comprehensive testing checklist
- `PRODUCTION_OPTIMIZATIONS.md` - Performance tuning guide
- `SECURITY_IMPLEMENTATION_COMPLETE.md` - Security hardening
- `SCALING_STRATEGY.md` - Autoscaling configuration

---

## Preserved Knowledge Base

### Successful Configurations

#### MongoDB StatefulSet
```yaml
command: ["mongod", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip", "0.0.0.0"]
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```
**Lesson**: WiredTiger cache tuning essential for low-memory environments

#### Kafka in KRaft Mode
```yaml
env:
- name: KAFKA_PROCESS_ROLES
  value: "broker,controller"
- name: KAFKA_CONTROLLER_QUORUM_VOTERS
  value: "1@kafka-0.kafka-headless:9093"
- name: CLUSTER_ID
  value: "EchgzCv5T7OjY0wIPyFVXw"  # Base64-encoded UUID
- name: KAFKA_HEAP_OPTS
  value: "-Xmx160M -Xms160M"
```
**Lesson**: KRaft requires specific cluster ID format and proper DNS resolution

#### Kafka Init Container Pattern
```yaml
initContainers:
- name: kafka-format-storage
  command: ["/bin/bash", "/scripts/init-storage.sh"]
  volumeMounts:
  - name: kafka-init-script
    mountPath: /scripts
volumes:
- name: kafka-init-script
  configMap:
    name: kafka-init-storage
    defaultMode: 0755
```
**Lesson**: ConfigMaps for scripts cleaner than inline bash

### SSH Agent for Bastion
```bash
# Auto-start SSH agent if not running
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/k8s-cluster-key
fi
```
**Lesson**: Essential for Ansible to traverse bastion hosts

### Python Library Management
```bash
# Try pipx environment first
if pipx runpip ansible install kubernetes; then
    echo "Installed via pipx"
# Fallback to system package
elif sudo apt-get install -y python3-kubernetes; then
    echo "Installed via apt-get"
# Final fallback
else
    pip install kubernetes
fi
```
**Lesson**: Multiple installation methods increase reliability

---

## What Would Be Needed to Make Kubernetes Work

If someone wanted to continue with Kubernetes for this project:

### Option 1: Upgrade Instance Types
- **Control Plane**: t2.small (2GB RAM) - $0.023/hr = ~$17/month
- **Workers**: t2.small (2GB RAM) × 2-3 nodes
- **Cost**: ~$50-75/month (outside free tier)
- **Benefit**: Comfortable resource headroom

### Option 2: Managed Kubernetes (EKS)
- **EKS Control Plane**: $0.10/hr = $73/month
- **Worker Nodes**: t3.small × 2-3
- **Total Cost**: ~$100-150/month
- **Benefit**: AWS manages control plane, better stability

### Option 3: K3s (Lightweight Kubernetes)
- **Alternative**: Use K3s instead of full Kubernetes
- **Savings**: ~50% memory overhead reduction
- **Tradeoff**: Fewer features, but adequate for this project
- **Still**: Would need SSH/bastion issues resolved

### Option 4: Simpler Networking
- **Change**: Use public IPs for all nodes (development mode)
- **Remove**: Bastion host pattern
- **Benefit**: Eliminate SSH forwarding complexity
- **Tradeoff**: Less secure (fine for learning)

### Recommendations for K8s Success
1. Use t2.small or larger instances
2. Start with 3-node cluster (1 control + 2 workers)
3. Use public IPs initially, add bastion later
4. Deploy monitoring stack (Prometheus) early
5. Use K3s or k0s for lower overhead
6. Have 50% memory headroom for stability

---

## Migration Decision Rationale

### Primary Factors
1. **Recurring Worker Join Issues**: Same problem reappeared after full rebuild
2. **Resource Constraints**: t2.micro genuinely too small for comfortable K8s operation
3. **Time Investment**: Diminishing returns on troubleshooting
4. **Project Goals**: Plant monitoring system, not K8s showcase
5. **Learning Value**: Already gained significant K8s knowledge

### Decision Matrix
| Criterion | Continue K8s | Switch to Swarm | Winner |
|-----------|--------------|-----------------|---------|
| Resource Fit | ❌ Tight | ✅ Comfortable | Swarm |
| Complexity | ❌ High | ✅ Low | Swarm |
| Time to Success | ⚠️ Unknown | ✅ ~2-4 hours | Swarm |
| Learning Value | ⚠️ Diminishing | ✅ Compare orchestrators | Swarm |
| Industry Relevance | ✅ High | ⚠️ Lower | K8s |
| Free Tier Fit | ⚠️ Marginal | ✅ Excellent | Swarm |
| **Overall** | **3/6** | **5/6** | **Swarm** |

### What We Accomplish by Switching
1. ✅ Actually complete the project
2. ✅ Compare two orchestration technologies
3. ✅ Demonstrate adaptability and pragmatism
4. ✅ Better utilize free tier resources
5. ✅ Preserve all K8s learning and documentation

---

## References & Resources

### Official Documentation Used
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm Installation Guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Flannel CNI](https://github.com/flannel-io/flannel)
- [Kafka on Kubernetes](https://strimzi.io/documentation/)
- [MongoDB on Kubernetes](https://www.mongodb.com/docs/kubernetes-operator/)

### Troubleshooting Resources
- [Kubernetes Debugging Guide](https://kubernetes.io/docs/tasks/debug/)
- [SSH Agent Forwarding](https://developer.github.com/v3/guides/using-ssh-agent-forwarding/)
- [Ansible Bastion Hosts](https://docs.ansible.com/ansible/latest/user_guide/connection_details.html)

### Community Help
- Stack Overflow: Kafka KRaft cluster ID format
- GitHub Issues: Flannel CNI troubleshooting
- Reddit r/kubernetes: t2.micro resource constraints discussions

---

## Acknowledgments

This Kubernetes implementation, while ultimately not deployed to production, provided invaluable learning experiences:

- **Deep understanding** of container orchestration concepts
- **Hands-on experience** with production-grade infrastructure as code
- **Problem-solving skills** in complex distributed systems
- **Realistic appreciation** for resource requirements and constraints
- **Pragmatic decision-making** about technology tradeoffs

The decision to migrate to Docker Swarm is not a failure of Kubernetes, but rather a demonstration of **choosing the right tool for the job** given specific constraints.

---

**End of Archive** - Continued in Docker Swarm implementation
