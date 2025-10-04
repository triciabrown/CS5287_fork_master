# Exercise 2: Kubernetes Secrets Management

## Goal
Learn how to securely manage credentials and sensitive data in Kubernetes using Secrets.

## What You'll Learn
- Creating Kubernetes Secrets manually
- Different ways to store secrets (literals, files, YAML)
- Using secrets as environment variables in pods
- MongoDB authentication setup
- Security best practices for secrets

## Background
In Exercise 1, we deployed MongoDB without authentication (you saw the warning "Access control is not enabled"). In production, this is a major security risk. Let's add proper authentication using Kubernetes Secrets.

## Step 1: Create MongoDB Credentials Secret

First, let's create a secret with MongoDB root credentials:

```bash
# Create secret using kubectl (easiest method)
kubectl create secret generic mongodb-credentials \
  --from-literal=root-username=admin \
  --from-literal=root-password=supersecret123 \
  --from-literal=database=plant_monitoring

# View the secret (encoded in base64)
kubectl get secret mongodb-credentials -o yaml

# Decode a secret value to verify
kubectl get secret mongodb-credentials -o jsonpath='{.data.root-username}' | base64 -d
echo # Add newline
```

## Step 2: Update MongoDB Deployment to Use Secrets

Apply the updated MongoDB deployment that includes authentication:

```bash
# Apply the new deployment with authentication
kubectl apply -f mongodb-with-auth-deployment.yaml

# Wait for pod to be ready
kubectl get pods -w
# Press Ctrl+C when pod shows 1/1 Running
```

## Step 3: Test Authentication

```bash
# Get the new pod name
POD_NAME=$(kubectl get pods -l app=mongodb-auth -o jsonpath='{.items[0].metadata.name}')

# Test connection with authentication
kubectl exec -it $POD_NAME -- mongosh -u admin -p supersecret123 --authenticationDatabase admin

# Inside MongoDB shell:
use plant_monitoring
db.createUser({
  user: "app_user",
  pwd: "app_password",
  roles: [
    { role: "readWrite", db: "plant_monitoring" }
  ]
})

# Test the new user
use plant_monitoring
db.sensors.insertOne({
  plant_id: "plant-001",
  temperature: 22.5,
  humidity: 65,
  timestamp: new Date()
})

db.sensors.find().pretty()
exit
```

## Step 4: Create Application-Level Secret

Create a separate secret for your application to use:

```bash
# Create application credentials
kubectl create secret generic app-mongodb-credentials \
  --from-literal=username=app_user \
  --from-literal=password=app_password \
  --from-literal=database=plant_monitoring \
  --from-literal=connection-string="mongodb://app_user:app_password@mongodb-auth:27017/plant_monitoring"
```

## Step 5: Test Service Connectivity with Authentication

```bash
# Test connection using the service name and app credentials
kubectl run test-auth-client --image=mongo:6.0.4 --rm -it --restart=Never -- \
  mongosh "mongodb://app_user:app_password@mongodb-auth:27017/plant_monitoring" \
  --eval "
    db.sensors.find().forEach(printjson);
    db.sensors.insertOne({
      plant_id: 'plant-002',
      temperature: 24.1,
      humidity: 70,
      timestamp: new Date(),
      source: 'service_test'
    });
    print('Successfully connected via service with authentication!');
  "
```

## Step 6: Understanding Different Secret Creation Methods

### Method 1: kubectl create (what we used)
```bash
kubectl create secret generic my-secret --from-literal=key=value
```

### Method 2: From file
```bash
echo -n 'admin' > username.txt
echo -n 'supersecret123' > password.txt
kubectl create secret generic my-secret --from-file=username.txt --from-file=password.txt
rm username.txt password.txt  # Clean up
```

### Method 3: YAML manifest (like our other resources)
```bash
# Look at the mongodb-secret.yaml file
kubectl apply -f mongodb-secret.yaml
```

## Step 7: View and Manage Secrets

```bash
# List all secrets
kubectl get secrets

# View secret details (base64 encoded)
kubectl describe secret mongodb-credentials

# View secret data (decoded)
kubectl get secret mongodb-credentials -o json | jq -r '.data | map_values(@base64d)'

# Delete a secret
kubectl delete secret app-mongodb-credentials
# Recreate it
kubectl create secret generic app-mongodb-credentials \
  --from-literal=username=app_user \
  --from-literal=password=app_password
```

## Key Concepts Learned

1. **Secrets vs ConfigMaps**: Secrets for sensitive data, ConfigMaps for configuration
2. **Base64 Encoding**: Kubernetes automatically encodes secret values
3. **Environment Variables**: How to inject secrets into containers
4. **Service Connectivity**: Using service names with authentication
5. **Least Privilege**: Creating application-specific database users

## Security Best Practices

✅ **DO:**
- Use separate secrets for different purposes (admin vs app)
- Create database users with minimal required permissions
- Use service names instead of IP addresses
- Rotate credentials regularly

❌ **DON'T:**
- Store secrets in container images
- Use default/empty passwords
- Give applications admin-level database access
- Log or print secret values

## Troubleshooting

### Pod Won't Start
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
# Check if secret exists and has correct keys
kubectl get secret mongodb-credentials -o yaml
```

### Authentication Fails
```bash
# Verify secret values
kubectl get secret mongodb-credentials -o jsonpath='{.data.root-username}' | base64 -d
kubectl get secret mongodb-credentials -o jsonpath='{.data.root-password}' | base64 -d

# Check environment variables in pod
kubectl exec <pod-name> -- env | grep MONGO
```

### Service Connection Issues
```bash
kubectl get endpoints mongodb-auth
kubectl describe service mongodb-auth
```

## Clean Up

```bash
# Delete the authenticated deployment
kubectl delete -f mongodb-with-auth-deployment.yaml

# Keep secrets for next exercise
# kubectl delete secret mongodb-credentials app-mongodb-credentials
```

## Next Exercise

Once this works, proceed to `../03-persistent-storage/` to add data persistence with StatefulSets and PVCs.

This exercise teaches you the foundation of secure secret management that you'll use throughout your CA2 implementation!