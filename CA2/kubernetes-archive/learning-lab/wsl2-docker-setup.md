# Docker Desktop Setup for WSL2 (Your Setup)

I notice you're using WSL2 (Windows Subsystem for Linux). For WSL2, we need to install Docker Desktop on your Windows host machine, not inside the WSL2 Linux distro.

## Step 1: Install Docker Desktop on Windows

### Download Docker Desktop for Windows
1. Go to https://www.docker.com/products/docker-desktop/
2. Click "Download for Windows"
3. Run the installer `Docker Desktop Installer.exe`

### During Installation:
- ✅ **Enable "Use WSL 2 instead of Hyper-V"**
- ✅ **Enable "Install required Windows components for WSL 2"**

## Step 2: Configure WSL2 Integration

After Docker Desktop is installed on Windows:

1. **Open Docker Desktop on Windows**
2. **Go to Settings** (gear icon)
3. **Navigate to Resources → WSL Integration**
4. **Enable integration with your WSL2 distros:**
   - ✅ Enable integration with my default WSL distro
   - ✅ Enable integration with additional distros (select your Ubuntu distro)
5. **Click "Apply & Restart"**

## Step 3: Enable Kubernetes

In Docker Desktop settings:
1. **Go to Kubernetes tab**
2. **✅ Check "Enable Kubernetes"**
3. **✅ Check "Show system containers (advanced)"**
4. **Click "Apply & Restart"**
5. **Wait 2-5 minutes for Kubernetes to start**

## Step 4: Test from WSL2

Once Docker Desktop is running on Windows with WSL2 integration enabled, come back to your WSL2 terminal:

```bash
# Test Docker
docker --version
docker ps

# Install kubectl in WSL2
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Test Kubernetes
kubectl version --client
kubectl cluster-info
```

## Step 5: Set Up Learning Environment

```bash
# Navigate to learning lab
cd /home/tricia/dev/CS5287_fork_master/CA2/learning-lab

# Create namespace
kubectl create namespace ca2-learning
kubectl config set-context --current --namespace=ca2-learning

# Test with first exercise
cd 01-simple-mongodb
kubectl apply -f mongodb-deployment.yaml
kubectl get pods
```

## Alternative: Use Remote Development

If you prefer not to install Docker Desktop on Windows, you can:

1. **Use GitHub Codespaces** with Kubernetes pre-installed
2. **Use a cloud VM** with Docker and kubectl
3. **Use the AWS CloudShell** for later EKS work

## Next Steps

1. **Install Docker Desktop for Windows** using the steps above
2. **Enable WSL2 integration** 
3. **Enable Kubernetes**
4. **Come back here and test** the commands in Step 4
5. **Start with Exercise 1** once everything works

Let me know when you've installed Docker Desktop on Windows and I'll help you test the setup!