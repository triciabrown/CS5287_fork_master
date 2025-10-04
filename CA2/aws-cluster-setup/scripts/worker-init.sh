#!/bin/bash
# Worker Node Initialization Script - Free Tier Optimized
set -e

echo "=== Starting Worker Node Initialization ==="
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

# Configure containerd for systemd cgroup driver
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

# Create kubelet configuration optimized for t2.micro
mkdir -p /var/lib/kubelet
cat > /var/lib/kubelet/config.yaml << EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
# t2.micro optimizations
maxPods: 20  # Reduce from default 110
podPidsLimit: 1024
systemReserved:
  memory: "200Mi"
  cpu: "100m"
kubeReserved:
  memory: "100Mi"
  cpu: "50m"
evictionHard:
  memory.available: "100Mi"
  nodefs.available: "10%"
  nodefs.inodesFree: "5%"
# Reduce resource monitoring frequency
nodeStatusUpdateFrequency: "30s"
imageMinimumGCAge: "5m"
imageGCHighThresholdPercent: 80
imageGCLowThresholdPercent: 60
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

# Configure system optimizations for t2.micro
echo "Configuring system optimizations for t2.micro..."

# Reduce systemd journal size
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size-limit.conf << EOF
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=25M
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

# Pre-pull essential container images to save time during join
echo "Pre-pulling essential container images..."
kubeadm config images pull --kubernetes-version=v1.28.2 &

# Wait for instance to be fully ready
sleep 60

# Output readiness status
echo "=== Worker Node Ready for kubeadm join ==="
echo "Hostname: $(hostname)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
echo "Control Plane IP: ${control_plane_ip}"
echo ""
echo "Worker node is ready. Control plane will automatically join workers when ready."
echo "=================================================="

# Save instance info for later reference
cat > /home/ubuntu/instance-info.txt << EOF
Cluster: ${cluster_name}
Role: worker
Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)
Initialized: $(date)
EOF

chown ubuntu:ubuntu /home/ubuntu/instance-info.txt

# Create helpful scripts for the user
cat > /home/ubuntu/join-cluster.sh << 'EOF'
#!/bin/bash
echo "To join this worker to the cluster:"
echo "1. Get the join command from control plane:"
echo "   ssh to control plane and run: kubeadm token create --print-join-command"
echo "2. Run the join command with sudo on this node"
echo "3. Verify on control plane: kubectl get nodes"
EOF

chmod +x /home/ubuntu/join-cluster.sh
chown ubuntu:ubuntu /home/ubuntu/join-cluster.sh

# Create topology info file for control plane to use
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
NODE_NAME=$(hostname)

cat > /home/ubuntu/topology-info.txt << EOF
NODE_NAME=$NODE_NAME
REGION=$REGION
AZ=$AZ
EOF

chown ubuntu:ubuntu /home/ubuntu/topology-info.txt

wait  # Wait for background image pull to complete

echo "Worker node initialization script completed successfully!"