# CA2 StatefulSet Issues - TODO for October 6, 2025

## 🚨 **CRITICAL ISSUES - Both MongoDB and Kafka pods failing to become Ready**

### **Current Status:**
- **MongoDB**: `Running` but 0/1 Ready, multiple restarts due to probe failures
- **Kafka**: `Running` but 0/1 Ready, stuck at configuration stage
- **Root Issue**: Health check probes are failing, causing continuous restarts
- **Impact**: Deploy script times out waiting for StatefulSets to become Ready

---

## 📋 **IMMEDIATE FIXES NEEDED**

### **1. MongoDB Probe Configuration Issues**
**Problem**: `mongosh --eval db.adminCommand('ping')` command timing out in health checks

**Root Causes:**
- MongoDB bound to localhost only (127.0.0.1) but Kubernetes probes come from pod network
- `mongosh` command may require authentication that probes don't provide
- Complex exec probe more prone to timing issues than simple TCP checks

**Solution Required:**
```yaml
# Change from exec probe to TCP socket probe
livenessProbe:
  tcpSocket:
    port: 27017
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  tcpSocket:
    port: 27017
  initialDelaySeconds: 10
  periodSeconds: 5

# Add --bind_ip_all to MongoDB command
command:
- mongod
- --wiredTigerCacheSizeGB
- "0.25"
- --bind_ip_all  # <-- ADD THIS
```

### **2. MongoDB Security Warnings (Production Issues)**
From logs analysis - these are production-critical security issues:

#### **Warning 1: Access Control Disabled**
```
"Access control is not enabled for the database. Read and write access to data and configuration is unrestricted"
```
**Fix Required**: Enable authentication
```yaml
command:
- mongod
- --auth  # Enable authentication
- --wiredTigerCacheSizeGB
- "0.25"
- --bind_ip_all
```

#### **Warning 2: Running as Root User**
```
"You are running this process as the root user, which is not recommended"
```
**Fix Required**: Add security context to run as non-root user
```yaml
securityContext:
  runAsUser: 999
  runAsGroup: 999
  fsGroup: 999
```

#### **Warning 3: Bind IP Issue**
```
"This server is bound to localhost. Remote systems will be unable to connect to this server"
```
**Fix Required**: Already identified above - add `--bind_ip_all`

#### **Warning 4: VM Memory Map Count Too Low**
```
"vm.max_map_count is too low","currentValue":65530,"recommendedMinimum":1677720
```
**Fix Required**: This is a host-level kernel parameter that affects MongoDB performance
```bash
# On each Kubernetes node, need to set:
echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
sysctl -p
```
**Alternative**: Add init container to set this parameter

### **3. Kafka Configuration Issues**
**Problem**: Kafka stuck at "Running in KRaft mode..." configuration stage

**Potential Causes:**
- Volume permissions (partially fixed with securityContext but may need refinement)
- Missing or incorrect KRaft configuration parameters
- Insufficient resources for startup

**Investigation Needed:**
- Check if Kafka logs show more details after longer wait time
- Verify all KRaft environment variables are correct
- Confirm volume mount permissions are working

### **4. Network Policy Issues (PARTIALLY FIXED)**
**Status**: ✅ Identified and partially resolved
- **Problem**: Network policies were blocking kubelet health checks
- **Solution Applied**: Added `from: []` exceptions for health check ports
- **Files Updated**: `network-policy.yaml` with kubelet exceptions
- **Verification Needed**: Reapply network policies and test

---

## 🔧 **FIXES ALREADY IMPLEMENTED**

### **✅ EBS CSI Driver Issues (RESOLVED)**
1. **Missing csi-attacher container** - Added to controller deployment
2. **RBAC permissions** - Added `patch` and `update` permissions for PersistentVolumes
3. **Missing node-driver-registrar** - Added to node daemonset
4. **Topology label conflicts** - Removed manual labeling in deploy script

### **✅ Resource Configuration Issues (RESOLVED)**
1. **Kafka memory limits** - Fixed request > limit validation error
2. **MongoDB cache size** - Increased from 0.1GB to 0.25GB (minimum requirement)
3. **Deprecated MongoDB options** - Removed `--smallfiles` and `--nojournal`
4. **Kafka CLUSTER_ID** - Added required environment variable for KRaft mode

### **✅ Volume Mounting Issues (RESOLVED)**
1. **EBS volume attachment** - Working after CSI driver fixes
2. **PVC provisioning** - Both MongoDB and Kafka PVCs are `Bound`
3. **Volume permissions** - Added securityContext with fsGroup: 1000 for Kafka

---

## 📝 **FILES THAT NEED UPDATES**

### **Primary File to Update:**
- `CA2/plant-monitor-k8s-IaC/ansible-k8s-deployment/deploy-applications.yml`
  - MongoDB command: Add `--bind_ip_all` and `--auth`
  - MongoDB probes: Change from exec to tcpSocket
  - MongoDB security: Add runAsUser/runAsGroup
  - Kafka investigation: Check if additional config needed

### **Network Policy File:**
- `CA2/applications/network-policy.yaml` (UPDATED - needs reapplication)
  - Kubelet health check exceptions added
  - Ready to reapply: `kubectl apply -f network-policy.yaml`

---

## 🔍 **DEBUGGING STRATEGY FOR TOMORROW**

### **Step 1: Fix MongoDB Binding and Probes**
1. Update ansible configuration with `--bind_ip_all`
2. Change probes from exec to tcpSocket
3. Delete and recreate MongoDB StatefulSet
4. Monitor logs for bind IP warnings resolution

### **Step 2: Add MongoDB Security Hardening**
1. Add securityContext for non-root execution
2. Enable authentication with `--auth`
3. Test connection from other pods

### **Step 3: Deep Dive Kafka Issues**
1. Let Kafka run longer and capture full startup logs
2. Verify all KRaft environment variables
3. Check if volume permissions need additional fixes
4. Compare with working Kafka configurations

### **Step 4: Reapply Network Policies**
1. Apply updated network-policy.yaml with kubelet exceptions
2. Verify pods can still pass health checks
3. Test application-to-application connectivity

### **Step 5: Host-Level Optimizations**
1. Investigate vm.max_map_count setting on Kubernetes nodes
2. Consider adding init containers for system parameter tuning

---

## 🎯 **SUCCESS CRITERIA**

### **Immediate Goals:**
- [ ] MongoDB pod: `1/1 Running` and `Ready`
- [ ] Kafka pod: `1/1 Running` and `Ready` 
- [ ] StatefulSets: `kubectl wait` commands succeed without timeout
- [ ] Deploy script: Completes Step 6 successfully

### **Production Readiness Goals:**
- [ ] MongoDB: No security warnings in logs
- [ ] MongoDB: Authentication enabled and working
- [ ] MongoDB: Running as non-root user
- [ ] Network policies: Applied and allowing necessary traffic
- [ ] Performance: No vm.max_map_count warnings

---

## 📊 **CURRENT DEPLOYMENT STATE**

### **Infrastructure Status:**
- ✅ **AWS Cluster**: 1 control plane + 4 workers running
- ✅ **EBS CSI Driver**: Fully functional with all containers
- ✅ **Storage Classes**: gp2 and gp3 available
- ✅ **Volume Provisioning**: Working (PVCs bound successfully)

### **Application Status:**
- ❌ **MongoDB**: Running but not Ready (probe failures)
- ❌ **Kafka**: Running but not Ready (configuration issues)
- ❌ **Other Apps**: Dependent on MongoDB/Kafka, likely failing
- ⚠️ **Network Policies**: Updated but not yet reapplied

### **Security Status:**
- ⚠️ **MongoDB**: Multiple production security warnings
- ✅ **RBAC**: Service accounts configured
- ⚠️ **Pod Security**: Some containers running as root
- ✅ **Network Segmentation**: Policies defined but need reapplication

---

## 🚀 **ESTIMATED TIME TO RESOLUTION**

- **MongoDB fixes**: 30-45 minutes (binding, probes, security)
- **Kafka investigation**: 15-30 minutes (logs analysis, config verification)  
- **Network policy reapplication**: 10-15 minutes
- **Testing and validation**: 20-30 minutes
- **Documentation updates**: 15 minutes

**Total estimated time**: 1.5-2 hours to full resolution

---

*Last updated: October 5, 2025, 11:30 PM*
*Current status: Both StatefulSets running but not ready due to probe failures*
*Next session focus: MongoDB binding and probe configuration fixes*