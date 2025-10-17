# Plant Monitoring System - Production Deployment

This directory contains the **production-ready** Kubernetes manifests for the Plant Monitoring System PaaS implementation (CS5287 CA2).

## 🏗️ Architecture Overview

The Plant Monitoring System is deployed as a **Platform-as-a-Service (PaaS)** solution on AWS Kubernetes, consisting of:

- **Data Layer**: MongoDB StatefulSet with persistent storage
- **Messaging Layer**: Apache Kafka with KRaft mode (no Zookeeper)  
- **Processing Layer**: Plant Data Processor for sensor data handling
- **Monitoring Layer**: System health monitoring and alerting

## 📦 Production Components

### Core Services
- `mongodb` - StatefulSet with 5GB persistent storage (gp2)
- `kafka` - StatefulSet with KRaft configuration and 5GB storage
- `plant-processor` - Deployment for sensor data processing
- `system-monitor` - Pod for health monitoring and system status

### Networking
- All services use ClusterIP for internal communication
- Services are isolated within the `plant-monitoring` namespace
- No external LoadBalancer to optimize for AWS free tier costs

### Resource Optimization
- **Memory limits**: Containers limited to 64-300Mi per t2.micro constraints
- **CPU limits**: Conservative CPU allocation (25-200m) for stable performance
- **Storage**: 5GB persistent volumes using AWS gp2 storage class
- **JVM tuning**: Kafka optimized with 128MB heap for minimal resource usage

## 🚀 Deployment Instructions

### Prerequisites
- Kubernetes cluster running on AWS (see `/aws-cluster-setup/`)
- kubectl configured for cluster access
- StorageClass `gp2` available (default on AWS EKS/kubeadm)

### Quick Deploy
```bash
# Deploy all components
# Use modular approach with Ansible + Home Assistant
# Core services deployed via Ansible, Home Assistant via manifest
kubectl apply -f homeassistant.yaml

# Verify deployment
kubectl get all -n plant-monitoring

# Check persistent volumes
kubectl get pv,pvc -n plant-monitoring

# Monitor system health
kubectl logs -f system-monitor -n plant-monitoring
```

### Validation
```bash
# Check MongoDB connectivity
kubectl exec -it mongodb-0 -n plant-monitoring -- mongosh -u admin -p plantmon2024

# Test Kafka topics
kubectl exec -it kafka-0 -n plant-monitoring -- kafka-topics --bootstrap-server localhost:9092 --list

# View processor logs
kubectl logs -f deployment/plant-processor -n plant-monitoring

# System resource usage
kubectl top nodes
kubectl top pods -n plant-monitoring
```

## 🔍 Production Features

### High Availability
- **StatefulSets** for data persistence (MongoDB, Kafka)
- **Persistent Volumes** with AWS EBS gp2 storage
- **Health checks** with liveness and readiness probes
- **Resource limits** to prevent resource exhaustion

### Monitoring & Observability
- **System Monitor** pod for continuous health reporting
- **Resource tracking** with memory, CPU, and disk monitoring
- **Service discovery** validation for internal networking
- **Log aggregation** via kubectl logs for troubleshooting

### Security
- **Namespace isolation** with dedicated `plant-monitoring` namespace
- **Internal networking** with ClusterIP services only
- **Resource quotas** to prevent resource abuse
- **MongoDB authentication** with username/password credentials

### Free Tier Optimization
- **Minimal replicas** (1 per service) to conserve resources  
- **Conservative resource requests** fitting within t2.micro limits
- **Storage limits** (5GB each) within free tier allowances
- **No external LoadBalancers** to avoid additional AWS charges

## 📊 Resource Allocation

| Component | Memory Request | Memory Limit | CPU Request | CPU Limit | Storage |
|-----------|----------------|--------------|-------------|-----------|---------|
| MongoDB   | 128Mi          | 256Mi        | 100m        | 200m      | 5Gi     |
| Kafka     | 200Mi          | 300Mi        | 100m        | 200m      | 5Gi     |
| Processor | 32Mi           | 64Mi         | 25m         | 50m       | -       |
| Monitor   | 16Mi           | 32Mi         | 10m         | 20m       | -       |
| **Total** | **376Mi**      | **652Mi**    | **235m**    | **470m**  | **10Gi**|

*Resource allocation designed for 3 × t2.micro instances (1GB RAM, 1 vCPU each)*

## 🛠️ Troubleshooting

### Common Issues
```bash
# Pod stuck in Pending
kubectl describe pod <pod-name> -n plant-monitoring

# Storage issues
kubectl get events -n plant-monitoring --sort-by='.lastTimestamp'

# Resource exhaustion
kubectl top nodes
kubectl describe nodes

# Network connectivity
kubectl run debug --image=alpine --rm -it -- /bin/sh
# Inside pod: nslookup mongodb-service.plant-monitoring.svc.cluster.local
```

### Performance Tuning
- **MongoDB**: Increase `wiredTigerCacheSizeGB` if more memory available
- **Kafka**: Adjust `KAFKA_HEAP_OPTS` based on actual memory usage
- **Processor**: Scale replicas if processing load increases
- **Storage**: Upgrade to gp3 for better IOPS if needed

## 📈 Production Readiness Checklist

- ✅ **Persistent Storage**: StatefulSets with PVC templates
- ✅ **Health Checks**: Liveness and readiness probes configured
- ✅ **Resource Limits**: Memory and CPU limits set
- ✅ **Namespace Isolation**: Dedicated namespace with labels
- ✅ **Service Discovery**: Internal ClusterIP services
- ✅ **Monitoring**: System health monitoring pod
- ✅ **Documentation**: Complete deployment and troubleshooting guide
- ✅ **Free Tier Optimized**: Resource usage within AWS free tier limits

---
**Note**: This production deployment is optimized for educational purposes within AWS free tier constraints. For true production workloads, consider multi-zone deployment, backup strategies, and enhanced monitoring solutions.