# Exercise 1: Deploy Simple MongoDB

## Goal
Deploy a basic MongoDB container to understand Kubernetes pods, deployments, and services.

## What You'll Learn
- How to write Kubernetes YAML manifests
- Difference between Pods and Deployments  
- How Kubernetes Services work for networking
- Basic kubectl commands

## Step 1: Create the MongoDB Deployment

This is a **simplified version** of the production MongoDB from your architecture plan. We're skipping:
- Authentication (will add in Exercise 2)
- Persistent storage (will add in Exercise 3)  
- StatefulSets (will add in Exercise 3)

```bash
# Apply the deployment
kubectl apply -f mongodb-deployment.yaml

# Check if it's running
kubectl get pods
kubectl get deployments
kubectl get services
```

## Step 2: Test the Database Connection

```bash
# Get the pod name
POD_NAME=$(kubectl get pods -l app=mongodb -o jsonpath='{.items[0].metadata.name}')

# Connect to MongoDB shell inside the pod
kubectl exec -it $POD_NAME -- mongosh

# Inside MongoDB shell, try these commands:
show dbs
use test_database
db.test_collection.insertOne({message: "Hello from Kubernetes!", timestamp: new Date()})
db.test_collection.find()
exit
```

## Step 3: Understand What Happened

```bash
# View deployment details
kubectl describe deployment mongodb

# View service details  
kubectl describe service mongodb

# View pod logs
kubectl logs $POD_NAME

# View pod details
kubectl describe pod $POD_NAME
```

## Step 4: Test Service Networking

```bash
# Create a temporary pod to test connection
kubectl run test-client --image=mongo:6.0.4 --rm -it --restart=Never -- mongosh mongodb:27017

# Inside the client shell:
show dbs
use test_database  
db.test_collection.find()
exit
```

## Step 5: Clean Up

```bash
# Delete everything
kubectl delete -f mongodb-deployment.yaml

# Verify it's gone
kubectl get all
```

## Key Concepts Learned

1. **Deployment**: Manages replicas and rolling updates
2. **Pod**: The actual running container(s)
3. **Service**: Provides stable networking to pods
4. **Labels/Selectors**: How services find pods

## Troubleshooting

### Pod Won't Start
```bash
kubectl get pods
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Can't Connect to Service
```bash
kubectl get services
kubectl describe service mongodb
# Check if service selector matches pod labels
```

### Permission Denied
```bash
# Make sure you're in the right namespace
kubectl config get-contexts
kubectl config set-context --current --namespace=ca2-learning
```

## Next Exercise

Once this works, proceed to `../02-secrets-management/` to add authentication.