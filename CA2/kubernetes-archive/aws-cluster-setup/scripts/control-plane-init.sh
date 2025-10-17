#!/bin/bash
# Control Plane Initialization Script - Free Tier Optimized
set -e

echo "=== Starting Control Plane Initialization ==="
echo "Cluster: ${cluster_name}"
echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "=============================="

# Update system
echo "Updating system packages..."
apt-get update -q
apt-get upgrade -y -q

# Install Docker and containerd
echo "Installing Docker and containerd..."
apt-get install -y -q apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io

# Configure containerd for systemd cgroup driver (required for Kubernetes)
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Apply optimizations in one step to avoid duplicate sections
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's/max_container_log_line_size = 16384/max_container_log_line_size = 1024/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# Install kubeadm, kubelet, kubectl
echo "Installing Kubernetes components..."
# Use the new Kubernetes repository
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -q
apt-get install -y -q kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Configure kubelet for AWS (removed deprecated --cloud-provider=aws flag)
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
EOF

systemctl daemon-reload
systemctl restart kubelet

# Disable swap (required by Kubernetes)
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable IP forwarding and configure iptables
modprobe br_netfilter
modprobe overlay

cat > /etc/modules-load.d/k8s.conf << EOF
br_netfilter
overlay
EOF

cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# Configure memory and CPU optimizations for t2.micro
echo "Configuring system optimizations for t2.micro..."

# Reduce systemd journal size
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size-limit.conf << EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=50M
EOF

systemctl restart systemd-journald

# Set kernel parameters for low memory
cat >> /etc/sysctl.d/k8s.conf << EOF
# Memory optimizations for t2.micro
vm.swappiness=1
vm.dirty_ratio=3
vm.dirty_background_ratio=1
EOF

sysctl --system

# Create kubeadm configuration optimized for t2.micro
cat > /tmp/kubeadm-config.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  bindPort: 6443
nodeRegistration:
  kubeletExtraArgs:
    node-ip: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.2
clusterName: ${cluster_name}
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
apiServer:
  certSANs:
    - $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    - $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  extraArgs:
    # Reduce resource usage
    audit-log-maxage: "7"
    audit-log-maxbackup: "2"
    audit-log-maxsize: "10"
controllerManager:
  extraArgs:
    # Reduce memory usage
    kube-api-qps: "20"
    kube-api-burst: "30"
scheduler:
  extraArgs:
    # Reduce resource usage
    kube-api-qps: "20"
    kube-api-burst: "30"
etcd:
  local:
    extraArgs:
      # Optimize etcd for low resources
      quota-backend-bytes: "2147483648"  # 2GB max
      max-snapshots: "3"
      max-wals: "3"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
# t2.micro optimizations
maxPods: 20  # Reduce from default 110
podPidsLimit: 1024
systemReserved:
  memory: "300Mi"
  cpu: "100m"
kubeReserved:
  memory: "200Mi"
  cpu: "100m"
evictionHard:
  memory.available: "100Mi"
  nodefs.available: "10%"
  nodefs.inodesFree: "5%"
EOF

# Wait for instance to be fully ready
sleep 30

echo "=== Initializing Kubernetes Control Plane ==="
echo "Hostname: $(hostname)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
echo ""

# Initialize cluster with memory and CPU checks ignored for t2.micro
echo "Running kubeadm init with free tier optimizations..."
kubeadm init --config=/tmp/kubeadm-config.yaml --ignore-preflight-errors=Mem,NumCPU --v=2

# Set up kubectl for ubuntu user
echo "Setting up kubectl access..."
mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Set up kubectl for root (for system scripts)
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

# Install Flannel CNI
echo "Installing Flannel CNI..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for control plane to be ready
echo "Waiting for control plane to be ready..."
timeout 300 bash -c 'until kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes | grep -q Ready; do sleep 10; done'

# Add topology labels for EBS CSI driver
echo "Adding topology labels for EBS CSI driver..."
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
NODE_NAME=$(hostname)

# Wait for node to be registered
timeout 120 bash -c 'until kubectl --kubeconfig=/etc/kubernetes/admin.conf get node '"$NODE_NAME"' > /dev/null 2>&1; do sleep 5; done'

# Apply topology labels
kubectl --kubeconfig=/etc/kubernetes/admin.conf label node "$NODE_NAME" topology.kubernetes.io/region="$REGION" --overwrite
kubectl --kubeconfig=/etc/kubernetes/admin.conf label node "$NODE_NAME" topology.kubernetes.io/zone="$AZ" --overwrite

echo "✅ Topology labels applied: region=$REGION, zone=$AZ"

# Generate join command for worker nodes
echo "Generating join command for worker nodes..."
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo "$JOIN_COMMAND --ignore-preflight-errors=Mem,NumCPU" > /home/ubuntu/join-command.sh
chmod +x /home/ubuntu/join-command.sh
chown ubuntu:ubuntu /home/ubuntu/join-command.sh

echo "=== Control Plane Initialization Complete ==="
echo "✅ Cluster initialized successfully"
echo "✅ kubectl configured for ubuntu user"  
echo "✅ Flannel CNI installed"
echo "✅ Join command saved to /home/ubuntu/join-command.sh"
echo ""
echo "Cluster is ready for worker nodes to join!"
echo "Use the deployment script to complete worker node setup."
echo "=================================================="

# Save instance info for later reference
cat > /home/ubuntu/instance-info.txt << EOF
Cluster: ${cluster_name}
Role: control-plane
Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)
Initialized: $(date)
EOF

chown ubuntu:ubuntu /home/ubuntu/instance-info.txt

echo "Control plane initialization script completed successfully!"