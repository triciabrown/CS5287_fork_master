# Docker Desktop Setup Guide for Linux

## Step 1: Install Docker Desktop

### Download and Install
```bash
# Update your system
sudo apt update

# Install required dependencies
sudo apt install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index
sudo apt update

# Install Docker Desktop (download the .deb package)
wget https://desktop.docker.com/linux/main/amd64/docker-desktop-4.24.0-amd64.deb
sudo dpkg -i docker-desktop-4.24.0-amd64.deb

# If you get dependency errors, fix them with:
sudo apt-get install -f
```

### Alternative: Using Snap (Easier)
```bash
sudo snap install docker
```

### Start Docker Desktop
```bash
# Launch Docker Desktop
systemctl --user start docker-desktop

# Or launch from applications menu
# Look for "Docker Desktop" in your applications
```

## Step 2: Enable Kubernetes in Docker Desktop

1. **Open Docker Desktop**
   - Click on Docker Desktop icon in your system tray or applications menu

2. **Go to Settings**
   - Click the gear/settings icon in Docker Desktop

3. **Enable Kubernetes**
   - Navigate to "Kubernetes" tab in settings
   - Check "Enable Kubernetes"
   - Check "Show system containers (advanced)"
   - Click "Apply & Restart"

4. **Wait for Kubernetes to Start**
   - This may take 2-5 minutes
   - You'll see "Kubernetes is running" when ready

## Step 3: Verify Installation

Open a terminal and run these commands:

```bash
# Check Docker is running
docker --version
docker ps

# Check Kubernetes is running
kubectl version --client
kubectl cluster-info

# Should see something like:
# Kubernetes control plane is running at https://kubernetes.docker.internal:6443
# CoreDNS is running at https://kubernetes.docker.internal:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

## Step 4: Set Up Learning Environment

```bash
# Navigate to your CA2 learning directory
cd /home/tricia/dev/CS5287_fork_master/CA2/learning-lab

# Create namespace for our exercises
kubectl create namespace ca2-learning

# Set this as your default namespace
kubectl config set-context --current --namespace=ca2-learning

# Verify namespace is set
kubectl config get-contexts
```

## Step 5: Test with First Exercise

```bash
# Navigate to the first exercise
cd 01-simple-mongodb

# Deploy MongoDB
kubectl apply -f mongodb-deployment.yaml

# Check if it's working
kubectl get pods
kubectl get services

# You should see:
# NAME                      READY   STATUS    RESTARTS   AGE
# mongodb-xxxxxxxxx-xxxxx   1/1     Running   0          30s
```

## Troubleshooting

### Docker Desktop Won't Start
```bash
# Check if Docker daemon is running
systemctl --user status docker-desktop

# Restart Docker Desktop
systemctl --user restart docker-desktop

# Check Docker Desktop logs
journalctl --user -u docker-desktop
```

### Kubernetes Won't Enable
1. **Insufficient Resources**: Kubernetes needs at least 2GB RAM
   - Go to Docker Desktop Settings → Resources
   - Increase Memory to at least 4GB
   - Increase CPUs to at least 2

2. **Reset Kubernetes**
   - Go to Settings → Kubernetes
   - Click "Reset Kubernetes Cluster"
   - Wait for it to reinstall

### kubectl Command Not Found
```bash
# Install kubectl separately if needed
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client
```

### Permission Issues
```bash
# Add your user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or run:
newgrp docker

# Test Docker without sudo
docker ps
```

## Next Steps

Once you see Docker and Kubernetes running:

1. **Complete the verification tests above**
2. **Run Exercise 1** in `/01-simple-mongodb/`
3. **Follow the README.md** in that directory
4. **Ask questions** if you get stuck!

## Quick Status Check Commands

```bash
# Docker status
docker version
docker system info

# Kubernetes status  
kubectl version
kubectl get nodes
kubectl get namespaces
kubectl config current-context

# Resource usage
docker system df
kubectl top nodes  # (if metrics-server is installed)
```

## Common Docker Desktop Features

- **Dashboard**: Visual interface to see containers, images, volumes
- **Resource Usage**: Monitor CPU/memory usage
- **Container Logs**: Easy log viewing
- **Volume Management**: Manage persistent data
- **Registry Access**: Pull from Docker Hub, private registries

Ready to start? Let's deploy your first MongoDB container!