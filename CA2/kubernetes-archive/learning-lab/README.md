# CA2 Learning Lab - PaaS Step by Step

This directory contains simple, progressive exercises to learn Kubernetes/PaaS concepts before implementing the full CA2 architecture.

## Learning Path Overview

### Phase 0: Local Kubernetes Basics
1. **Environment Setup** - Get Kubernetes running locally
2. **First Pod** - Deploy a simple container
3. **Secrets Management** - Handle credentials securely
4. **Persistent Storage** - Add data persistence
5. **Service Networking** - Connect multiple services

### Phase 1: Cloud Migration
6. **EKS Basics** - Deploy to AWS Kubernetes
7. **Production Features** - Add monitoring, scaling, security

## Prerequisites

Choose ONE of these local Kubernetes options:

### Option A: Docker Desktop (Recommended for beginners)
```bash
# 1. Install Docker Desktop
# 2. Go to Settings → Kubernetes → Enable Kubernetes
# 3. Verify installation
kubectl version --client
kubectl cluster-info
```

### Option B: Minikube (More configurable)
```bash
# Install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Start cluster
minikube start
minikube status
kubectl cluster-info
```

### Option C: Kind (Kubernetes in Docker)
```bash
# Install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Create cluster
kind create cluster --name ca2-learning
kubectl cluster-info --context kind-ca2-learning
```

## Verification Commands

Once you have Kubernetes running locally:

```bash
# Check cluster status
kubectl cluster-info

# List nodes
kubectl get nodes

# List namespaces
kubectl get namespaces

# Create test namespace
kubectl create namespace ca2-learning
kubectl config set-context --current --namespace=ca2-learning
```

## Next Steps

Once your local environment is ready, proceed to:
1. `01-simple-mongodb/` - Deploy your first database
2. `02-secrets-management/` - Add authentication
3. `03-persistent-storage/` - Make data survive restarts
4. `04-kafka-networking/` - Connect multiple services
5. `05-full-stack/` - Complete plant monitoring system

Each directory contains:
- `README.md` - Step-by-step instructions
- `manifests/` - Kubernetes YAML files
- `scripts/` - Helper commands
- `troubleshooting.md` - Common issues and solutions