# CA2 - Plant Monitoring PaaS Implementation

## 🎯 Project Overview

This is a production-ready Platform-as-a-Service (PaaS) implementation for the Plant Monitoring System using Kubernetes on AWS. The system demonstrates cloud-native principles including declarative configuration, horizontal scaling, security, and complete automation.

## 🏗️ Architecture

### Infrastructure Components
- **AWS EKS-style Cluster**: 3 × t2.micro instances (1 control plane + 2 workers)
- **Container Runtime**: containerd with Kubernetes v1.28.15
- **Network Plugin**: Flannel CNI for pod-to-pod communication
- **Storage**: AWS EBS CSI Driver with gp2 StorageClass
- **Load Balancing**: AWS ALB integration ready

### Application Stack
- **Message Queue**: Apache Kafka (StatefulSet with persistent storage)
- **Database**: MongoDB (StatefulSet with authentication)
- **Data Producer**: Python sensor data generator (Deployment)
- **Data Processor**: Python consumer with MongoDB storage (Deployment)

### Security & Operations
- **Secrets Management**: Kubernetes Secrets for sensitive data
- **Configuration**: ConfigMaps for application settings
- **Network Security**: NetworkPolicies for traffic isolation
- **Auto-scaling**: Horizontal Pod Autoscaler (HPA)
- **Monitoring**: Resource limits, health checks, and logging

## 📁 Project Structure

```
CA2/
├── aws-cluster-setup/           # Infrastructure provisioning
│   ├── main.tf                 # Terraform configuration
│   ├── deploy-cluster.sh       # Infrastructure deployment
│   └── scripts/                # Helper scripts
├── applications/               # Application manifests and code
│   ├── plant-monitoring-manifests.yaml  # Core K8s resources
│   ├── aws-ebs-csi-driver.yaml         # Storage driver
│   ├── security-config.yaml            # Secrets & ConfigMaps
│   ├── network-policy.yaml             # Network isolation
│   ├── hpa-config.yaml                # Auto-scaling config
│   ├── producer/                       # Python sensor app
│   ├── processor/                      # Python processing app
│   ├── deploy-production.sh            # Complete deployment
│   ├── teardown-production.sh          # Complete cleanup
│   └── smoke-test.sh                   # System validation
└── learning-lab/               # Development exercises
    └── 01-04-exercises/        # Progressive learning modules
```

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- kubectl installed
- Terraform >= 1.0
- Docker (for building custom images)

### Complete Deployment

1. **Deploy Infrastructure** (from `aws-cluster-setup/`):
```bash
./deploy-cluster.sh
```

2. **Deploy Applications** (from `applications/`):
```bash
./deploy-production.sh
```

3. **Validate System**:
```bash
./smoke-test.sh
```

### Complete Teardown
```bash
./teardown-production.sh
cd ../aws-cluster-setup
terraform destroy -auto-approve
```

## 🔧 Detailed Deployment

### Phase 1: Infrastructure Provisioning
```bash
cd aws-cluster-setup/
terraform init
terraform plan
terraform apply -auto-approve
```

**Creates:**
- 3 EC2 instances with Kubernetes roles
- Security groups for cluster communication
- IAM roles and policies
- VPC networking configuration

### Phase 2: Application Deployment
```bash
cd ../applications/
kubectl create namespace plant-monitoring

# Deploy storage infrastructure
kubectl apply -f aws-ebs-csi-driver.yaml

# Deploy security configuration
kubectl apply -f security-config.yaml

# Deploy core applications
kubectl apply -f plant-monitoring-manifests.yaml

# Deploy network policies
kubectl apply -f network-policy.yaml

# Deploy auto-scaling
kubectl apply -f hpa-config.yaml
```

### Phase 3: Validation
```bash
./smoke-test.sh
```

## 📊 System Validation

The smoke test validates:
- ✅ Kubernetes cluster connectivity
- ✅ All pods running and healthy
- ✅ MongoDB read/write operations
- ✅ Kafka message production/consumption
- ✅ Network connectivity between components
- ✅ Security configurations applied
- ✅ Auto-scaling configuration active
- ✅ Resource constraints enforced

## 🔐 Security Implementation

### Network Security
- **Default Deny**: All ingress traffic blocked by default
- **Service-Specific Rules**: Only required ports open between services
- **Namespace Isolation**: Traffic scoped to plant-monitoring namespace

### Data Security
- **MongoDB Authentication**: Username/password via Kubernetes Secrets
- **Kafka SASL**: Ready for production authentication
- **ConfigMap Separation**: Non-sensitive config separated from secrets

### Resource Security
- **Resource Limits**: CPU/memory limits prevent resource exhaustion
- **Security Contexts**: Non-root containers where possible
- **Network Policies**: Micro-segmentation for defense in depth

## 📈 Scaling Configuration

### Horizontal Pod Autoscaler (HPA)
```yaml
Producer: 1-5 replicas based on CPU (target: 70%)
Processor: 1-3 replicas based on CPU (target: 80%)
```

### Manual Scaling
```bash
# Scale producers
kubectl scale deployment plant-producer -n plant-monitoring --replicas=3

# Scale processors  
kubectl scale deployment plant-processor -n plant-monitoring --replicas=2
```

### Monitoring Scaling
```bash
kubectl get hpa -n plant-monitoring
kubectl top pods -n plant-monitoring
```

## 🗂️ Key Deliverables

### 1. Custom Container Images
- **plant-producer**: Python sensor data generator with realistic IoT patterns
- **plant-processor**: Python data consumer with MongoDB integration
- Both include health checks, proper logging, and graceful shutdown

### 2. Declarative Configuration
- All infrastructure defined in Terraform
- All applications defined in Kubernetes YAML
- No manual configuration steps required

### 3. Security Implementation
- Secrets management for sensitive data
- Network policies for traffic isolation
- Resource limits for stability

### 4. Automation Scripts
- `deploy-production.sh`: Complete system deployment
- `teardown-production.sh`: Complete system cleanup
- `smoke-test.sh`: Comprehensive system validation

### 5. Operational Readiness
- Health checks and monitoring endpoints
- Horizontal auto-scaling configuration
- Persistent storage for data durability
- Complete logging for troubleshooting

## 🎓 Learning Outcomes Demonstrated

### Cloud-Native Principles
- **Declarative Configuration**: Infrastructure and applications as code
- **Immutable Infrastructure**: Containers with versioned images
- **Service-Oriented Architecture**: Loosely coupled microservices
- **Horizontal Scaling**: Auto-scaling based on metrics

### Platform Engineering
- **Automation**: Single-command deployment and teardown
- **Security**: Defense in depth with multiple security layers
- **Operations**: Monitoring, logging, and health checking
- **Reliability**: Persistent storage and graceful failure handling

### AWS Integration
- **Compute**: EC2 instances with optimized networking
- **Storage**: EBS integration with Kubernetes CSI
- **Networking**: VPC configuration and security groups
- **IAM**: Least privilege access controls

## 🔍 Troubleshooting

### Common Issues

**Pods Pending/Not Starting:**
```bash
kubectl describe pod <pod-name> -n plant-monitoring
kubectl get events -n plant-monitoring --sort-by='.lastTimestamp'
```

**Storage Issues:**
```bash
kubectl get pvc -n plant-monitoring
kubectl describe pvc -n plant-monitoring
```

**Network Connectivity:**
```bash
kubectl exec -it <pod-name> -n plant-monitoring -- ping <target-service>
```

### Debug Commands
```bash
# Cluster status
kubectl get nodes
kubectl cluster-info

# Application status
kubectl get all -n plant-monitoring
kubectl logs -f deployment/plant-processor -n plant-monitoring

# Resource usage
kubectl top nodes
kubectl top pods -n plant-monitoring
```

## 📚 References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Container Security](https://kubernetes.io/docs/concepts/security/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

---

**CS5287 Cloud Computing - CA2 Assignment**  
*Production Platform-as-a-Service Implementation*