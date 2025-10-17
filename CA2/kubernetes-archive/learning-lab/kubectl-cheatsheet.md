# Kubernetes Quick Reference for CA2

## Essential kubectl Commands

### Cluster Management
```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes

# Check current context/namespace
kubectl config current-context
kubectl config get-contexts
kubectl config set-context --current --namespace=<namespace>
```

### Working with Resources
```bash
# Apply manifests
kubectl apply -f <file.yaml>
kubectl apply -f <directory>/
kubectl apply -k <kustomization-dir>/

# Get resources
kubectl get pods
kubectl get deployments
kubectl get services
kubectl get all
kubectl get pods -o wide           # More details
kubectl get pods -w                # Watch mode

# Describe resources (detailed info)
kubectl describe pod <pod-name>
kubectl describe deployment <deployment-name>
kubectl describe service <service-name>

# Delete resources
kubectl delete -f <file.yaml>
kubectl delete pod <pod-name>
kubectl delete deployment <deployment-name>
```

### Debugging
```bash
# View logs
kubectl logs <pod-name>
kubectl logs <pod-name> -f         # Follow logs
kubectl logs <pod-name> --previous # Previous container logs

# Execute commands in pods
kubectl exec -it <pod-name> -- /bin/bash
kubectl exec -it <pod-name> -- mongosh
kubectl exec <pod-name> -- <command>

# Port forwarding (access services locally)
kubectl port-forward service/<service-name> 8080:80
kubectl port-forward pod/<pod-name> 8080:80
```

### Secrets and ConfigMaps
```bash
# Create secrets
kubectl create secret generic <name> --from-literal=key=value
kubectl create secret generic <name> --from-file=<file>

# Create configmaps
kubectl create configmap <name> --from-literal=key=value
kubectl create configmap <name> --from-file=<file>

# View secrets/configmaps
kubectl get secrets
kubectl get configmaps
kubectl describe secret <name>
kubectl get secret <name> -o yaml
```

### Namespaces
```bash
# List namespaces
kubectl get namespaces

# Create namespace
kubectl create namespace <name>

# Set default namespace
kubectl config set-context --current --namespace=<name>

# Run command in specific namespace
kubectl get pods -n <namespace>
```

## Common Troubleshooting Scenarios

### Pod Won't Start
```bash
kubectl get pods
kubectl describe pod <pod-name>
kubectl logs <pod-name>

# Common issues:
# - Image pull errors
# - Resource constraints  
# - Missing secrets/configmaps
# - Invalid manifest syntax
```

### Service Connection Issues
```bash
kubectl get services
kubectl describe service <service-name>
kubectl get endpoints <service-name>

# Test connectivity from another pod:
kubectl run test --image=busybox --rm -it -- nslookup <service-name>
kubectl run test --image=busybox --rm -it -- wget -qO- <service-name>:<port>
```

### Resource Constraints
```bash
kubectl top nodes
kubectl top pods
kubectl describe node <node-name>

# Check resource requests vs limits in manifests
```

## Manifest Structure Cheat Sheet

### Basic Pod
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  labels:
    app: my-app
spec:
  containers:
  - name: my-container
    image: nginx
    ports:
    - containerPort: 80
```

### Basic Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-container
        image: nginx
        ports:
        - containerPort: 80
```

### Basic Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

### Basic Secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
data:
  username: <base64-encoded>
  password: <base64-encoded>
```