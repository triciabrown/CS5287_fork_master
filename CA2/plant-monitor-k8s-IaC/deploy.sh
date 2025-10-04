#!/bin/bash
# CA2 Plant Monitoring System - Complete Deployment
# Single command deployment following assignment requirements
# Builds upon CA1 with Kubernetes orchestration

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🌱 CA2 Plant Monitoring System - Kubernetes Deployment${NC}"
echo "=================================================================="
echo "Building upon CA1 implementation with container orchestration"
echo ""

# Configuration
TERRAFORM_DIR="../aws-cluster-setup"
ANSIBLE_DIR="./ansible-k8s-deployment"
NAMESPACE="plant-monitoring"

# Step 1: Infrastructure Provisioning
echo -e "${YELLOW}🏗️  Step 1: Infrastructure Provisioning${NC}"
echo "=================================================================="

# Check if cluster already exists (only if kubectl is configured)
CLUSTER_EXISTS=false
if [[ -f ~/.kube/config ]] && command -v kubectl >/dev/null 2>&1; then
    # Use a quick timeout to avoid hanging on non-existent clusters
    if timeout 10 kubectl get nodes >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Kubernetes cluster already accessible${NC}"
        kubectl get nodes
        CLUSTER_EXISTS=true
    else
        echo -e "${YELLOW}⚠️  kubectl config found but cluster not accessible${NC}"
    fi
fi

if [[ "$CLUSTER_EXISTS" != "true" ]]; then
    echo -e "${YELLOW}🚀 Provisioning 3-node Kubernetes cluster on AWS...${NC}"
    
    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        echo -e "${RED}❌ Terraform directory not found: $TERRAFORM_DIR${NC}"
        exit 1
    fi
    
    cd "$TERRAFORM_DIR"
    echo "Initializing Terraform..."
    terraform init -upgrade
    
    echo "Deploying infrastructure..."
    terraform apply -auto-approve
    
    # Get control plane IP
    CONTROL_PLANE_IP=$(terraform output -raw control_plane_ip 2>/dev/null || echo "")
    if [[ -z "$CONTROL_PLANE_IP" ]]; then
        echo -e "${RED}❌ Failed to get control plane IP${NC}"
        exit 1
    fi
    
    echo "Control plane IP: $CONTROL_PLANE_IP"
    cd - > /dev/null
    
    # Wait for cluster initialization
    echo -e "${YELLOW}⏳ Waiting for cluster initialization (this may take several minutes)...${NC}"
    
    retry_count=0
    max_retries=60  # 10 minutes
    
    while [ $retry_count -lt $max_retries ]; do
        if ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$CONTROL_PLANE_IP "kubectl get nodes" &>/dev/null; then
            echo -e "${GREEN}✅ Cluster is ready!${NC}"
            break
        fi
        retry_count=$((retry_count + 1))
        echo "Waiting for cluster... ($retry_count/$max_retries)"
        sleep 10
    done
    
    if [ $retry_count -eq $max_retries ]; then
        echo -e "${RED}❌ Cluster initialization timed out${NC}"
        exit 1
    fi
    
    # Setup kubectl access
    echo "Setting up kubectl access..."
    mkdir -p ~/.kube
    scp -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$CONTROL_PLANE_IP:/home/ubuntu/.kube/config ~/.kube/config
    
    # Fix kubeconfig to use public IP instead of private IP
    PRIVATE_IP=$(ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$CONTROL_PLANE_IP "curl -s http://169.254.169.254/latest/meta-data/local-ipv4")
    echo "Updating kubeconfig to use public IP ($CONTROL_PLANE_IP) instead of private IP ($PRIVATE_IP)..."
    sed -i "s|https://$PRIVATE_IP:6443|https://$CONTROL_PLANE_IP:6443|" ~/.kube/config
    
    # Join worker nodes
    echo -e "${YELLOW}🔧 Joining worker nodes to cluster...${NC}"
    cd "$TERRAFORM_DIR"
    WORKER_IPS=($(terraform output -json worker_ips | jq -r '.[]' 2>/dev/null || echo ""))
    cd - > /dev/null
    
    for i in "${!WORKER_IPS[@]}"; do
        worker_ip=${WORKER_IPS[$i]}
        worker_num=$((i + 1))
        echo "Joining worker-$worker_num ($worker_ip)..."
        
        # Wait for worker to be ready
        retry_count=0
        while ! ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$worker_ip "echo 'ready'" &>/dev/null; do
            retry_count=$((retry_count + 1))
            if [[ $retry_count -gt 20 ]]; then
                echo -e "${RED}❌ Worker-$worker_num not accessible${NC}"
                break
            fi
            echo "Waiting for worker-$worker_num... ($retry_count/20)"
            sleep 10
        done
        
        if [[ $retry_count -le 20 ]]; then
            # Get join command and execute on worker
            JOIN_CMD=$(ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$CONTROL_PLANE_IP "cat /home/ubuntu/join-command.sh")
            ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$worker_ip "sudo $JOIN_CMD" && \
                echo -e "${GREEN}✅ Worker-$worker_num joined successfully${NC}" || \
                echo -e "${RED}❌ Failed to join worker-$worker_num${NC}"
        fi
    done
    
    # Wait for all nodes to be ready
    echo "Waiting for all nodes to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s || echo "Some nodes may still be initializing"
fi

# Verify cluster connectivity after setup
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${YELLOW}⚠️  TLS certificate verification failed, trying with --insecure-skip-tls-verify${NC}"
    if kubectl cluster-info --insecure-skip-tls-verify &> /dev/null; then
        echo -e "${YELLOW}⚠️  Cluster accessible but TLS certificate needs public IP. Continuing with insecure access for deployment.${NC}"
        # Add insecure flag to kubeconfig for this session
        kubectl config set-cluster $(kubectl config current-context) --insecure-skip-tls-verify=true
    else
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster after setup${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}✅ Infrastructure Ready${NC}"
kubectl get nodes

# Step 2: Application Deployment with Ansible
echo ""
echo -e "${YELLOW}🚀 Step 2: Application Deployment${NC}"
echo "=================================================================="

# Check Ansible prerequisites
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}❌ ansible-playbook not found. Please install Ansible.${NC}"
    exit 1
fi

# Check for Kubernetes Ansible collection
if ! ansible-galaxy collection list | grep -q kubernetes.core; then
    echo "Installing Kubernetes Ansible collection..."
    ansible-galaxy collection install kubernetes.core
fi

# Check for Python kubernetes library (required by ansible kubernetes.core collection)
if ! python3 -c "import kubernetes" &>/dev/null; then
    echo "Installing Python kubernetes library (required for Ansible K8s modules)..."
    # Try different installation methods based on system setup
    if command -v pipx &>/dev/null; then
        pipx inject ansible-core kubernetes
    elif dpkg -l python3-kubernetes &>/dev/null 2>&1; then
        echo "System python3-kubernetes package already available"
    else
        echo "Please install the kubernetes library manually:"
        echo "  Option 1: sudo apt install python3-kubernetes"
        echo "  Option 2: pipx inject ansible-core kubernetes"
        echo "  Option 3: pip install kubernetes --break-system-packages"
        echo ""
        echo "Attempting with --break-system-packages flag..."
        pip install kubernetes --break-system-packages
    fi
fi

cd "$ANSIBLE_DIR"

# Create secrets (with random passwords)
echo -e "${YELLOW}🔐 Creating secure secrets...${NC}"
ansible-playbook create-secrets.yml -v

# Deploy infrastructure components
echo -e "${YELLOW}📦 Deploying applications...${NC}"
ansible-playbook deploy-applications.yml -v

# Install EBS CSI driver for persistent storage
echo -e "${YELLOW}💾 Setting up persistent storage...${NC}"
kubectl apply -f "../../applications/aws-ebs-csi-driver.yaml"

cd - > /dev/null

# Step 3: Deploy Home Assistant (modular configuration)
echo ""
echo -e "${YELLOW}🏠 Step 3: Home Assistant Deployment${NC}"
echo "=================================================================="
echo -e "${YELLOW}📱 Deploying Home Assistant dashboard...${NC}"

# Deploy clean Home Assistant configuration
kubectl apply -f "../applications/homeassistant.yaml"

# Setup lightweight secure ingress controller for t2.micro
echo -e "${YELLOW}🔒 Setting up lightweight secure external access...${NC}"
../applications/setup-ingress-lite.sh

# Install and configure metrics server for HPA support
echo -e "${YELLOW}📊 Installing metrics server for autoscaling...${NC}"
if ! kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Wait for metrics server to be created
    echo "Waiting for metrics server deployment to be created..."
    sleep 10
    
    # Patch metrics server for self-signed certificates (common in self-hosted clusters)
    kubectl patch deployment metrics-server -n kube-system --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
    
    echo -e "${GREEN}✅ Metrics server installed and configured${NC}"
else
    echo -e "${GREEN}✅ Metrics server already exists${NC}"
fi

# Step 4: Apply Network Policies and Security
echo ""
echo -e "${YELLOW}🔒 Step 4: Security Configuration${NC}"
echo "=================================================================="

kubectl apply -f ../applications/network-policy.yaml

# Step 5: Configure Scaling
echo ""
echo -e "${YELLOW}📈 Step 5: Scaling Configuration${NC}"
echo "=================================================================="

# Configure HPA (Horizontal Pod Autoscaler)
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    echo "Waiting for metrics server to be ready..."
    kubectl wait --for=condition=Available deployment/metrics-server -n kube-system --timeout=120s || echo "Metrics server taking longer than expected"
    
    echo "Applying HPA configuration..."
    kubectl apply -f ../applications/hpa-config.yaml
    echo -e "${GREEN}✅ HPA configured for automatic scaling${NC}"
else
    echo -e "${YELLOW}⚠️  Metrics server not found, HPA will not work${NC}"
fi

# Step 6: Wait for everything to be ready
echo ""
echo -e "${YELLOW}⏳ Step 6: Waiting for deployment completion...${NC}"
echo "=================================================================="

kubectl wait --for=condition=Ready statefulset/mongodb -n "$NAMESPACE" --timeout=300s
kubectl wait --for=condition=Ready statefulset/kafka -n "$NAMESPACE" --timeout=300s
kubectl wait --for=condition=Available deployment/plant-processor -n "$NAMESPACE" --timeout=300s
kubectl wait --for=condition=Available deployment/homeassistant -n "$NAMESPACE" --timeout=300s

echo ""
echo -e "${GREEN}🎉 Deployment Complete!${NC}"
echo "=================================================================="

# Display deployment status
echo ""
echo -e "${BLUE}📋 Deployment Status:${NC}"
kubectl get all -n "$NAMESPACE"

echo ""
echo -e "${BLUE}💾 Storage Status:${NC}"
kubectl get pv,pvc -n "$NAMESPACE"

echo ""
echo -e "${GREEN}🌍 Access Information:${NC}"
echo "=================================================================="
echo "🏠 Home Assistant Dashboard:"
echo "  � Secure Access: Via ingress controller (check ingress setup output above)"
echo "  🔗 Port Forward: kubectl port-forward svc/homeassistant-service 8123:8123 -n $NAMESPACE"
echo "  📍 Local Access: http://localhost:8123 (after port-forward)"
echo ""
echo "📨 MQTT Broker:"
echo "  🔌 Internal: homeassistant-service.plant-monitoring.svc.cluster.local:1883"
echo "  🔒 Security: ClusterIP only, no external exposure"
echo ""
echo "🔐 Credentials:"
echo "  📁 Temporary file: /tmp/plant-monitoring-credentials.txt"
echo "  🛡️  Stored securely in Kubernetes secrets"
echo ""
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo "1. Access Home Assistant via secure ingress (URL shown above)"
echo "2. Or use port-forward for development: kubectl port-forward svc/homeassistant-service 8123:8123 -n $NAMESPACE"
echo "3. Configure MQTT integration using internal broker address"
echo "4. Monitor plant sensors auto-discovery"
echo "5. Run scaling tests: kubectl scale deployment/plant-processor --replicas=3 -n $NAMESPACE"
echo "6. Run smoke tests: ./smoke-test.sh"
echo ""
echo -e "${BLUE}🧪 Testing Commands:${NC}"
echo "View logs: kubectl logs -f deployment/plant-processor -n $NAMESPACE"
echo "Scale system: kubectl scale deployment/plant-processor --replicas=2 -n $NAMESPACE"
echo "Monitor pods: kubectl get pods -n $NAMESPACE -w"
echo "Check secrets: kubectl get secrets -n $NAMESPACE"
echo ""
echo -e "${YELLOW}🗑️  Cleanup:${NC}"
echo "Teardown: ./teardown.sh"

# Clean up temporary files
rm -rf /tmp/ha-config

echo ""
echo -e "${GREEN}🛡️  Security Features Deployed:${NC}"
echo "✅ ClusterIP services (no direct external port exposure)"
echo "✅ NGINX Ingress with rate limiting and security headers"
echo "✅ Network policies restricting pod communication"
echo "✅ Kubernetes secrets for credential management"
echo "✅ Request size limits and timeout configurations"
echo ""
echo -e "${GREEN}✅ CA2 Plant Monitoring System successfully deployed!${NC}"
echo "Building upon CA1 with Kubernetes orchestration, proper secrets management, and security-first networking."