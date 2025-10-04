# Manual Kubernetes Cluster Setup Guide

## **Why Manual Cluster Setup?**

While managed services like EKS are great for production, setting up a cluster manually teaches you:
- **Kubernetes Architecture**: Understanding control plane components (etcd, API server, scheduler, controller manager)
- **Networking**: How pod networking and service discovery work
- **Storage Integration**: Configuring persistent volume drivers
- **Security Configuration**: Certificate management, RBAC setup, and network policies
- **Troubleshooting Skills**: Diagnosing issues at the infrastructure level
- **Cost Optimization**: ~$27/month savings compared to EKS ($110 vs $137)

---

## **Architecture Overview**

### **🆓 AWS Free Tier Optimized Design**

```
┌─────────────────────────────────────────────────────────────┐
│              Free Tier Kubernetes Cluster                   │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │  Control Plane  │  │  Worker Node 1  │  │ Worker Node 2│ │
│  │   (t2.micro)    │  │   (t2.micro)    │  │  (t2.micro)  │ │
│  │  - etcd         │  │  - kubelet      │  │  - kubelet   │ │
│  │  - API Server   │  │  - kube-proxy   │  │  - kube-proxy│ │
│  │  - Controller   │  │  - containerd   │  │  - containerd│ │
│  │  - Scheduler    │  │  - CNI Plugin   │  │  - CNI Plugin│ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│                                                             │
│  💡 Resource Constraints: 1GB RAM, 1 vCPU per instance     │
│  📦 Optimized Components: Lightweight workloads only        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Add-on Components                        │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  • EBS CSI Driver (Persistent Storage)                 │ │
│  │  • Flannel CNI (Pod Networking)                        │ │  
│  │  • Metrics Server (Resource Monitoring)                │ │
│  │  • External Secrets Operator (Secret Management)       │ │
│  │  • Ingress Controller (External Access)                │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## **🆓 Free Tier Resource Constraints & Optimizations**

### **t2.micro Specifications**
- **RAM**: 1GB (vs 4GB in t3.medium)
- **vCPU**: 1 core (vs 2 cores in t3.medium)  
- **Network**: Low to Moderate performance
- **Storage**: 30GB EBS included in free tier

### **Resource Optimization Strategy**

#### **1. Lightweight Component Selection**
```yaml
# Use minimal resource requests/limits
resources:
  requests:
    memory: "64Mi"    # Instead of 256Mi
    cpu: "50m"        # Instead of 100m
  limits:
    memory: "128Mi"   # Instead of 512Mi
    cpu: "100m"       # Instead of 200m
```

#### **2. Reduced Replica Counts**
- **MongoDB**: Single replica (no replication)
- **Kafka**: Single broker (no clustering)
- **Applications**: Single pod per service
- **System components**: Minimal resource allocation

#### **3. Memory Management**
```bash
# Enable swap for extra memory (not recommended for production)
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### **4. Component Limitations**

| Component | t3.medium Capability | t2.micro Limitation | Workaround |
|-----------|---------------------|-------------------|------------|
| **etcd** | 2GB+ recommended | 1GB total RAM | Use smaller keyspace, frequent compaction |
| **Kafka** | Multiple brokers | Single broker only | Accept no high availability |
| **MongoDB** | Replica sets | Single instance | Accept data loss risk |
| **CNI** | Full mesh networking | Limited bandwidth | Use simpler pod network |
| **Monitoring** | Full Prometheus stack | Lightweight metrics only | Use metrics-server only |

#### **5. Free Tier Quotas**
- **EC2 Instances**: 750 hours/month per instance type (t2.micro)
- **EBS Storage**: 30GB General Purpose SSD
- **Data Transfer**: 15GB/month outbound
- **Load Balancer**: NOT included (costs $16/month)

### **Alternative Architecture: Single-Node Cluster**

If 3 instances exceed free tier limits, consider a single-node setup:

```
┌─────────────────────────────────────────────────────────────┐
│                Single-Node Cluster (t2.micro)               │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Combined Control Plane + Worker                        │ │
│  │  - etcd (local)                                         │ │
│  │  - kube-apiserver                                       │ │
│  │  - kube-controller-manager                              │ │
│  │  - kube-scheduler                                       │ │
│  │  - kubelet                                              │ │
│  │  - kube-proxy                                           │ │
│  │  - containerd                                           │ │
│  │  - All application pods                                 │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Pros**: 
- ✅ Completely free (single t2.micro)
- ✅ Still learn all Kubernetes concepts
- ✅ Simpler networking setup

**Cons**:
- ❌ No high availability learning
- ❌ No multi-node networking experience
- ❌ Resource contention between system and apps

---

## **Phase 1: Infrastructure Provisioning**

### **Terraform Configuration**

Create `terraform/kubernetes-cluster.tf`:

```hcl
# Provider Configuration
provider "aws" {
  region = var.aws_region
}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  default     = "plant-monitoring-cluster"
}

# VPC Configuration
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Public Subnet
resource "aws_subnet" "k8s_public" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-subnet"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb" = "1"
  }
}

# Route Table
resource "aws_route_table" "k8s_public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "k8s_public_rta" {
  subnet_id      = aws_subnet.k8s_public.id
  route_table_id = aws_route_table.k8s_public_rt.id
}

# Security Group for Control Plane
resource "aws_security_group" "k8s_control_plane" {
  name        = "${var.cluster_name}-control-plane"
  description = "Security group for Kubernetes control plane"
  vpc_id      = aws_vpc.k8s_vpc.id

  # API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # etcd
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Scheduler & Controller Manager
  ingress {
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # SSH (restricted to your IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-control-plane-sg"
  }
}

# Security Group for Worker Nodes
resource "aws_security_group" "k8s_workers" {
  name        = "${var.cluster_name}-workers"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = aws_vpc.k8s_vpc.id

  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # NodePort Services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Pod-to-Pod communication (Flannel VXLAN)
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-workers-sg"
  }
}

# Get your current IP
data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

# IAM Role for EC2 instances
resource "aws_iam_role" "k8s_node_role" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "k8s_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.k8s_node_role.name
}

resource "aws_iam_role_policy_attachment" "k8s_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.k8s_node_role.name
}

resource "aws_iam_role_policy_attachment" "k8s_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.k8s_node_role.name
}

# Additional policy for EBS CSI driver
resource "aws_iam_role_policy" "k8s_ebs_csi_policy" {
  name = "${var.cluster_name}-ebs-csi-policy"
  role = aws_iam_role.k8s_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteSnapshot",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:DetachVolume",
          "ec2:ModifyVolume"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "k8s_node_profile" {
  name = "${var.cluster_name}-node-profile"
  role = aws_iam_role.k8s_node_role.name
}

# Key Pair
resource "aws_key_pair" "k8s_key" {
  key_name   = "${var.cluster_name}-key"
  public_key = file("~/.ssh/id_rsa.pub") # Make sure this exists
}

# Control Plane Instance
resource "aws_instance" "k8s_control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_control_plane.id]
  subnet_id              = aws_subnet.k8s_public.id
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/control-plane-init.sh", {
    cluster_name = var.cluster_name
  }))

  tags = {
    Name = "${var.cluster_name}-control-plane"
    Role = "control-plane"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Worker Node Instances  
resource "aws_instance" "k8s_workers" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_workers.id]
  subnet_id              = aws_subnet.k8s_public.id
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/worker-init.sh", {
    cluster_name = var.cluster_name
  }))

  tags = {
    Name = "${var.cluster_name}-worker-${count.index + 1}"
    Role = "worker"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Outputs
output "control_plane_ip" {
  value = aws_instance.k8s_control_plane.public_ip
}

output "control_plane_private_ip" {
  value = aws_instance.k8s_control_plane.private_ip
}

output "worker_ips" {
  value = aws_instance.k8s_workers[*].public_ip
}

output "worker_private_ips" {
  value = aws_instance.k8s_workers[*].private_ip
}
```

---

## **Phase 2: Node Initialization Scripts**

### **Control Plane Initialization**

Create `terraform/control-plane-init.sh`:

```bash
#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Docker and containerd
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Install kubeadm, kubelet, kubectl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet=1.28.2-00 kubeadm=1.28.2-00 kubectl=1.28.2-00
apt-mark hold kubelet kubeadm kubectl

# Configure kubelet
echo "KUBELET_EXTRA_ARGS=--cloud-provider=aws" > /etc/default/kubelet
systemctl daemon-reload
systemctl restart kubelet

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable kernel modules
modprobe br_netfilter
echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# Wait for instance to be fully ready
sleep 30

# Initialize cluster (this will be completed manually)
echo "Control plane node initialized. Run kubeadm init manually after connecting."
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
```

### **Worker Node Initialization**

Create `terraform/worker-init.sh`:

```bash
#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Docker and containerd
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Install kubeadm, kubelet, kubectl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet=1.28.2-00 kubeadm=1.28.2-00 kubectl=1.28.2-00
apt-mark hold kubelet kubeadm kubectl

# Configure kubelet
echo "KUBELET_EXTRA_ARGS=--cloud-provider=aws" > /etc/default/kubelet
systemctl daemon-reload
systemctl restart kubelet

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable kernel modules
modprobe br_netfilter
echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

echo "Worker node initialized. Ready to join cluster."
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
```

---

## **Phase 3: Manual Cluster Setup**

### **Step 1: Deploy Infrastructure**

```bash
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Deploy infrastructure
cd terraform/
terraform init
terraform apply -auto-approve

# Note the output IPs for later use
```

### **Step 2: Initialize Control Plane**

```bash
# SSH to control plane
ssh -i ~/.ssh/id_rsa ubuntu@<CONTROL_PLANE_PUBLIC_IP>

# Initialize Kubernetes cluster
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<CONTROL_PLANE_PRIVATE_IP> \
  --kubernetes-version=v1.28.2 \
  --node-name=$(hostname -s)

# Set up kubectl for ubuntu user
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Also set up for root user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### **Step 3: Install CNI Plugin (Flannel)**

```bash
# Install Flannel for pod networking
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Wait for flannel pods to be ready
kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s
```

### **Step 4: Join Worker Nodes**

```bash
# On control plane, get join command
kubeadm token create --print-join-command

# SSH to each worker node and run the join command
ssh -i ~/.ssh/id_rsa ubuntu@<WORKER_1_PUBLIC_IP>
sudo kubeadm join <CONTROL_PLANE_PRIVATE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>

ssh -i ~/.ssh/id_rsa ubuntu@<WORKER_2_PUBLIC_IP>
sudo kubeadm join <CONTROL_PLANE_PRIVATE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

### **Step 5: Verify Cluster**

```bash
# Back on control plane, verify all nodes
kubectl get nodes
kubectl get pods -A

# Should see something like:
# NAME                          STATUS   ROLES           AGE   VERSION
# ip-10-0-1-100                 Ready    control-plane   10m   v1.28.2
# ip-10-0-1-101                 Ready    <none>          5m    v1.28.2
# ip-10-0-1-102                 Ready    <none>          5m    v1.28.2
```

---

## **Phase 4: Install Essential Add-ons**

### **EBS CSI Driver for Persistent Storage**

```bash
# Install EBS CSI driver
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.24"

# Create StorageClass for EBS volumes
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-csi-gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
allowVolumeExpansion: true
EOF
```

### **Metrics Server for HPA**

```bash
# Install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics server for self-signed kubelet certificates
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  }
]'
```

### **Ingress Controller (Optional)**

```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/aws/deploy.yaml

# Wait for LoadBalancer to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

---

## **Phase 5: Set Up Local kubectl Access**

### **Copy kubeconfig to Local Machine**

```bash
# From your local machine, copy kubeconfig
scp -i ~/.ssh/id_rsa ubuntu@<CONTROL_PLANE_PUBLIC_IP>:/home/ubuntu/.kube/config ~/.kube/config-plant-monitoring

# Update context to use public IP (for access from local machine)
sed -i 's/<CONTROL_PLANE_PRIVATE_IP>/<CONTROL_PLANE_PUBLIC_IP>/g' ~/.kube/config-plant-monitoring

# Merge with existing config or set as default
export KUBECONFIG=~/.kube/config-plant-monitoring
kubectl config get-contexts

# Test access
kubectl get nodes
kubectl get pods -A
```

---

## **Verification Checklist**

### **Cluster Health**
- [ ] All nodes in `Ready` state
- [ ] All system pods running in `kube-system` namespace
- [ ] Flannel pods running in `kube-flannel` namespace
- [ ] EBS CSI driver pods running
- [ ] Metrics server responding

### **Storage Verification**
```bash
# Test persistent volume creation
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-csi-gp3
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-pvc
kubectl delete pvc test-pvc
```

### **Networking Verification**
```bash
# Test pod-to-pod communication
kubectl run test-pod --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default
```

---

## **What You've Learned**

### **Kubernetes Architecture**
- **Control Plane Components**: etcd, API server, scheduler, controller manager
- **Node Components**: kubelet, kube-proxy, container runtime
- **Add-on Components**: CNI, CSI, DNS, metrics server

### **Networking**
- **Pod Network CIDR**: How pods get IP addresses (10.244.0.0/16)
- **Service Network**: How services provide stable endpoints
- **CNI Plugin**: How Flannel enables pod-to-pod communication across nodes

### **Storage**
- **CSI Driver**: Container Storage Interface for AWS EBS integration
- **Storage Classes**: Templates for dynamic volume provisioning
- **Volume Binding**: How PVCs get bound to actual EBS volumes

### **Security**
- **RBAC**: Role-based access control configuration
- **Network Policies**: Pod-to-pod communication rules
- **Security Groups**: EC2-level firewall rules

---

## **Cost Comparison**

| Component | Free Tier Cluster | EKS Equivalent |
|-----------|------------------|----------------|
| Control Plane | **$0/month** (t2.micro free) | $73/month (managed) |
| Worker Nodes | **$0/month** (2×t2.micro free) | $68/month (2×t3.medium) |
| Load Balancer | $16/month (NLB) | $16/month (NLB) |
| Storage | **$0/month** (30GB EBS free) | $4/month (EBS) |
| **Total** | **$16/month** | **$161/month** |

**🎉 MASSIVE SAVINGS**: $145/month (90% cost reduction!)

---

## **Production Considerations**

### **High Availability**
- Deploy control plane across multiple AZs
- Use external etcd cluster
- Implement proper backup strategies

### **Security Hardening**
- Enable admission controllers
- Configure Pod Security Standards
- Implement network policies
- Regular security updates

### **Monitoring & Logging**
- Deploy Prometheus + Grafana
- Set up centralized logging (ELK stack)
- Configure alerting rules

### **Maintenance**
- Plan for Kubernetes version upgrades
- Automate certificate rotation
- Regular cluster health checks

This manual setup gives you deep understanding of Kubernetes internals while saving money and providing complete control over your cluster configuration!