# Storage Hierarchy & Volume Claim Templates Explained

## **The Storage Hierarchy**

```
StorageClass (Template) 
    ↓ (creates)
PersistentVolume (PV) - Actual Storage Resource
    ↓ (bound to)
PersistentVolumeClaim (PVC) - Request for Storage
    ↓ (mounted by)
Pod - Uses the storage via volumeMounts
```

## **1. StorageClass (The Template)**

```yaml
# This is usually pre-created by your cluster
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hostpath
provisioner: docker.io/hostpath
parameters:
  # Storage-specific configuration
reclaimPolicy: Delete
allowVolumeExpansion: true
```

**What it means:**
- **provisioner**: Who/what creates the actual storage (Docker Desktop uses hostpath)
- **reclaimPolicy**: What happens when PVC is deleted
  - `Delete` = Delete the PV too (data lost)
  - `Retain` = Keep PV (data preserved)
- **allowVolumeExpansion**: Can you make volumes bigger later?

## **2. PersistentVolume (PV) - The Actual Storage**

```yaml
# Auto-created when you request storage via PVC
apiVersion: v1
kind: PersistentVolume  
metadata:
  name: pvc-1f918c6e-c22e-4c92-9d96-4546dc2f15cd
spec:
  capacity:
    storage: 1Gi                    # How much space
  accessModes:
    - ReadWriteOnce                 # Access pattern
  persistentVolumeReclaimPolicy: Delete
  storageClassName: hostpath
  hostPath:                         # Docker Desktop specific
    path: /var/lib/k8s-pvs/...     # Where files actually live
    type: DirectoryOrCreate
```

**Key Attributes:**
- **capacity.storage**: Size of the volume (1Gi = 1 gigabyte)
- **accessModes**: How pods can access it
  - `ReadWriteOnce` (RWO): One pod can read/write
  - `ReadOnlyMany` (ROX): Many pods can read
  - `ReadWriteMany` (RWX): Many pods can read/write
- **hostPath**: Docker Desktop stores files on your local machine

## **3. PersistentVolumeClaim (PVC) - The Request**

```yaml
# This is created by volumeClaimTemplates in StatefulSet
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-data-mongodb-stateful-0  # Auto-generated name
  namespace: ca2-learning
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: hostpath
  resources:
    requests:
      storage: 1Gi
status:
  phase: Bound                           # Connected to a PV
  capacity:
    storage: 1Gi
```

**Key Attributes:**
- **resources.requests.storage**: How much storage you want
- **accessModes**: Must match what PV supports
- **storageClassName**: Which StorageClass to use
- **status.phase**: 
  - `Pending`: Looking for available PV
  - `Bound`: Successfully connected to PV

## **4. Volume Claim Templates (StatefulSet Magic)**

Here's the key part from our StatefulSet:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb-stateful
spec:
  # ... other StatefulSet configuration ...
  
  template:
    spec:
      containers:
      - name: mongodb
        # ... container config ...
        volumeMounts:                    # WHERE to mount in container
        - name: mongodb-data             # Must match volumeClaimTemplate name
          mountPath: /data/db            # MongoDB's data directory
          
  volumeClaimTemplates:                  # WHAT storage to create
  - metadata:
      name: mongodb-data                 # Name referenced in volumeMounts
    spec:
      accessModes: ["ReadWriteOnce"]     # How to access the storage
      storageClassName: hostpath         # Which StorageClass to use
      resources:
        requests:
          storage: 1Gi                   # How much storage to request
```

## **Volume Claim Templates Explained**

### **Why Templates vs Direct PVC?**

**Option 1: Manual PVC (Bad for StatefulSets)**
```yaml
# You'd have to manually create this for each pod
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-data-0
  # What about mongodb-data-1, mongodb-data-2, etc.?
```

**Option 2: Volume Claim Templates (StatefulSet Way)**
```yaml
volumeClaimTemplates:
- metadata:
    name: mongodb-data
  spec:
    # Template configuration
```

### **How Templates Work**

1. **StatefulSet sees template** → "I need to create storage for each pod"
2. **For pod mongodb-stateful-0** → Create PVC named `mongodb-data-mongodb-stateful-0`  
3. **For pod mongodb-stateful-1** → Create PVC named `mongodb-data-mongodb-stateful-1`
4. **Etc.**

The naming pattern: `{template-name}-{statefulset-name}-{pod-index}`

### **Template Attributes Breakdown**

```yaml
volumeClaimTemplates:
- metadata:
    name: mongodb-data              # Base name for PVCs
    labels:                         # Optional: Labels for the PVCs
      app: mongodb
      component: database
  spec:
    accessModes: ["ReadWriteOnce"]  # REQUIRED: How pods access storage
    storageClassName: hostpath      # OPTIONAL: Which StorageClass (uses cluster default if omitted)
    resources:                      # REQUIRED: Storage requirements
      requests:
        storage: 1Gi               # REQUIRED: How much storage
      limits:                       # OPTIONAL: Maximum storage (if supported)
        storage: 5Gi
    selector:                       # OPTIONAL: Select specific PVs
      matchLabels:
        environment: production
```

## **Access Modes Deep Dive**

| Mode | Abbreviation | Description | Use Case |
|------|--------------|-------------|----------|
| **ReadWriteOnce** | RWO | One pod can read/write | Databases (MongoDB, PostgreSQL) |
| **ReadOnlyMany** | ROX | Multiple pods read-only | Static content, shared configs |
| **ReadWriteMany** | RWX | Multiple pods read/write | Shared file systems |

**Important:** Most storage systems only support RWO!

## **Storage Classes in Different Environments**

### **Docker Desktop**
```yaml
storageClassName: hostpath   # Files stored on your local machine
```

### **AWS EKS**
```yaml
storageClassName: gp3        # Amazon EBS GP3 SSD
# or
storageClassName: efs        # Amazon EFS (supports RWX)
```

### **Google GKE**
```yaml
storageClassName: standard-ssd
# or  
storageClassName: filestore  # Google Filestore (supports RWX)
```

## **Putting It All Together**

When you deployed the StatefulSet:

1. **Kubernetes sees** `volumeClaimTemplates`
2. **Creates PVC** named `mongodb-data-mongodb-stateful-0`
3. **StorageClass `hostpath`** automatically creates a PV
4. **PVC binds** to the PV
5. **Pod mounts** the PVC at `/data/db`
6. **MongoDB stores** data in `/data/db` (which is persistent storage)
7. **Pod restarts** → Same PVC remounted → Data survives!

## **Advanced: Multiple Volume Templates**

```yaml
volumeClaimTemplates:
- metadata:
    name: mongodb-data           # For database files
  spec:
    accessModes: ["ReadWriteOnce"]
    storageClassName: fast-ssd
    resources:
      requests:
        storage: 10Gi
        
- metadata:
    name: mongodb-logs           # For log files  
  spec:
    accessModes: ["ReadWriteOnce"]
    storageClassName: standard-hdd
    resources:
      requests:
        storage: 1Gi
```

This creates TWO PVCs per pod:
- `mongodb-data-mongodb-stateful-0` (10Gi SSD for data)
- `mongodb-logs-mongodb-stateful-0` (1Gi HDD for logs)