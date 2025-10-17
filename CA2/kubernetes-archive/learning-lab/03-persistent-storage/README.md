# Exercise 3: Persistent Storage with StatefulSets

## Goal
Learn the difference between Deployments and StatefulSets, and how to add persistent storage that survives pod restarts.

## What You'll Learn
- StatefulSet vs Deployment differences
- PersistentVolumeClaim (PVC) concepts
- Storage Classes in Kubernetes
- Data persistence across pod restarts
- Stable network identities for stateful services

## Background
In Exercise 2, we used a **Deployment** for MongoDB. But there's a problem:

❌ **Problem with Deployments for Databases:**
- Pod restarts = **data loss**
- No stable network identity
- No persistent storage
- Pods are "cattle, not pets"

✅ **StatefulSet Solution:**
- Persistent storage attached to specific pods
- Stable, predictable pod names (mongodb-0, mongodb-1, etc.)
- Ordered deployment and scaling
- Data survives pod restarts

## Step 1: Observe Current Data Loss Problem

Let's first prove that our current MongoDB loses data when pods restart:

```bash
# Check current data in authenticated MongoDB
POD_NAME=$(kubectl get pods -l app=mongodb-auth -o jsonpath='{.items[0].metadata.name}')
echo "Current pod: $POD_NAME"

# Add some test data
kubectl exec -it $POD_NAME -- mongosh -u app_user -p app_password --authenticationDatabase plant_monitoring --eval "
use plant_monitoring;
db.test_persistence.insertOne({
  message: 'This data should survive pod restart',
  timestamp: new Date(),
  test: 'persistence_check'
});
db.test_persistence.find().pretty();
"

# Delete the pod to simulate restart
kubectl delete pod $POD_NAME

# Wait for new pod to come up
kubectl get pods -l app=mongodb-auth -w
# Press Ctrl+C when new pod is Running

# Check if data survived (spoiler: it won't!)
NEW_POD=$(kubectl get pods -l app=mongodb-auth -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $NEW_POD -- mongosh -u app_user -p app_password --authenticationDatabase plant_monitoring --eval "
use plant_monitoring;
db.test_persistence.find().pretty();
"
```

## Step 2: Deploy MongoDB as StatefulSet with Persistent Storage

```bash
# Apply the StatefulSet with PVC
kubectl apply -f mongodb-statefulset.yaml

# Wait for it to be ready
kubectl get pods -l app=mongodb-stateful -w
# Press Ctrl+C when mongodb-stateful-0 shows 1/1 Running
```

## Step 3: Examine Storage Resources

```bash
# Check the StatefulSet
kubectl get statefulsets

# Check PersistentVolumeClaims (PVCs)
kubectl get pvc

# Check PersistentVolumes (PVs) - created automatically
kubectl get pv

# Describe the PVC to understand the storage
kubectl describe pvc mongodb-data-mongodb-stateful-0
```

## Step 4: Test Data Persistence

```bash
# Connect to the StatefulSet pod
kubectl exec -it mongodb-stateful-0 -- mongosh -u admin -p supersecret123 --authenticationDatabase admin --eval "
use plant_monitoring;
db.createUser({
  user: 'app_user',
  pwd: 'app_password',  
  roles: [{ role: 'readWrite', db: 'plant_monitoring' }]
});
"

# Add test data
kubectl exec -it mongodb-stateful-0 -- mongosh -u app_user -p app_password --authenticationDatabase plant_monitoring --eval "
use plant_monitoring;
db.persistent_test.insertMany([
  { message: 'Data 1 - Should survive restart', timestamp: new Date() },
  { message: 'Data 2 - Should survive restart', timestamp: new Date() },
  { message: 'Data 3 - Should survive restart', timestamp: new Date() }
]);
db.persistent_test.find().pretty();
"

# Delete the pod to test persistence
kubectl delete pod mongodb-stateful-0

# Wait for pod to restart (StatefulSet automatically recreates it)
kubectl get pods -l app=mongodb-stateful -w
# Press Ctrl+C when mongodb-stateful-0 is Running again

# Verify data survived!
kubectl exec -it mongodb-stateful-0 -- mongosh -u app_user -p app_password --authenticationDatabase plant_monitoring --eval "
use plant_monitoring;
print('=== DATA AFTER POD RESTART ===');
db.persistent_test.find().pretty();
print('Data count:', db.persistent_test.countDocuments());
"
```

## Step 5: Understanding the Architecture

```bash
# Compare Deployment vs StatefulSet
echo "=== DEPLOYMENT (Exercise 2) ==="
kubectl get deployment mongodb-auth
kubectl get pods -l app=mongodb-auth

echo -e "\n=== STATEFULSET (Exercise 3) ==="
kubectl get statefulset mongodb-stateful  
kubectl get pods -l app=mongodb-stateful

# Look at pod names - notice the difference!
# Deployment: mongodb-auth-c579575b5-tc2bt (random suffix)
# StatefulSet: mongodb-stateful-0 (predictable name)
```

## Step 6: Storage Deep Dive

```bash
# Examine the PVC in detail
kubectl get pvc mongodb-data-mongodb-stateful-0 -o yaml

# See what storage class is being used
kubectl get storageclass

# Check the actual volume mount in the pod
kubectl describe pod mongodb-stateful-0 | grep -A 10 -B 5 "Mounts:"
```

## Key Concepts Learned

### **Deployment vs StatefulSet**

| Aspect | Deployment | StatefulSet |
|--------|------------|-------------|
| **Pod Names** | Random suffix | Ordered (app-0, app-1) |
| **Storage** | Ephemeral | Persistent via PVC |
| **Network Identity** | Changes on restart | Stable |
| **Use Cases** | Stateless apps | Databases, queues |
| **Scaling** | Any order | Ordered (0, 1, 2...) |

### **Storage Hierarchy**
```
StorageClass → PersistentVolume (PV) → PersistentVolumeClaim (PVC) → Pod
```

1. **StorageClass**: Template for creating storage (SSD, HDD, etc.)
2. **PersistentVolume (PV)**: Actual storage resource
3. **PersistentVolumeClaim (PVC)**: Request for storage
4. **Pod**: Mounts the PVC as a volume

## Troubleshooting

### Pod Stuck in Pending
```bash
kubectl describe pod mongodb-stateful-0
# Look for storage-related errors
kubectl get events --sort-by='.metadata.creationTimestamp'
```

### PVC Not Bound
```bash
kubectl describe pvc mongodb-data-mongodb-stateful-0
kubectl get pv  # Check if PV was created
```

### Data Still Missing
```bash
# Check if volume is properly mounted
kubectl exec mongodb-stateful-0 -- df -h
kubectl exec mongodb-stateful-0 -- ls -la /data/db
```

## Clean Up (Optional)

```bash
# Delete StatefulSet
kubectl delete -f mongodb-statefulset.yaml

# PVCs won't be automatically deleted - this is intentional!
kubectl get pvc
# To delete PVC and lose data:
# kubectl delete pvc mongodb-data-mongodb-stateful-0
```

## Security Note

Notice we're reusing the same `mongodb-credentials` secret from Exercise 2. This shows how secrets can be shared across different deployments!

## Next Exercise

Once this works, proceed to `../04-kafka-networking/` to add a second service (Kafka) and learn about service-to-service communication.

This exercise teaches you the foundation of **stateful applications** that you'll use for both MongoDB and Kafka in your CA2 implementation!