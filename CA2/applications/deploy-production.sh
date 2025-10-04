#!/bin/bash
# Plant Monitoring System - Complete Production Deployment
# CS5287 CA2 - PaaS Implementation
# 
# Single command deployment script that:
# 0. Provisions AWS infrastructure with Terraform
# 1. Initializes Kubernetes cluster and sets up kubectl
# 2. Sets up infrastructure (EBS CSI, storage)
# 3. Deploys security (secrets, configmaps, network policies)
# 4. Deploys applications (MongoDB, Kafka, processors, producers)
# 5. Configures scaling (HPA)
# 6. Runs smoke tests

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="plant-monitoring"
EBS_CSI_FILE="aws-ebs-csi-driver.yaml"
SECURITY_FILE="security-config.yaml"
NETWORK_POLICY_FILE="network-policy.yaml"
MANIFEST_FILE="plant-monitoring-manifests.yaml"
HPA_FILE="hpa-config.yaml"
TIMEOUT="300s"
HOME_ASSISTANT_PORT="8123"
MQTT_PORT="1883"
TERRAFORM_DIR="../aws-cluster-setup"
MAX_CLUSTER_WAIT=300  # 5 minutes max wait for cluster

echo -e "${BLUE}🌱 Plant Monitoring System - Complete Production Deployment${NC}"
echo "============================================================================"

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

# Note: Cluster connectivity will be checked after infrastructure provisioning

# Check all required files exist
REQUIRED_FILES=("$EBS_CSI_FILE" "$SECURITY_FILE" "$NETWORK_POLICY_FILE" "$MANIFEST_FILE" "$HPA_FILE")
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}❌ Required file '$file' not found.${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✅ All required files found${NC}"

# Step 0: Provision Infrastructure if needed
echo ""
echo -e "${BLUE}🏗️  Infrastructure Provisioning${NC}"
echo "============================================================================"

# Check if cluster already exists and is accessible
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✅ Kubernetes cluster already accessible${NC}"
else
    echo -e "${YELLOW}🚀 No accessible cluster found. Provisioning AWS infrastructure...${NC}"
    
    # Check terraform prerequisites
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}❌ terraform not found. Please install terraform.${NC}"
        exit 1
    fi
    
    # Navigate to terraform directory
    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        echo -e "${RED}❌ Terraform directory '$TERRAFORM_DIR' not found.${NC}"
        exit 1
    fi
    
    echo "Deploying 3-node Kubernetes cluster on AWS..."
    cd "$TERRAFORM_DIR"
    terraform init -upgrade
    terraform apply -auto-approve
    
    # Get control plane IP
    CONTROL_PLANE_IP=$(terraform output -raw control_plane_ip 2>/dev/null)
    if [[ -z "$CONTROL_PLANE_IP" ]]; then
        echo -e "${RED}❌ Failed to get control plane IP from terraform output${NC}"
        exit 1
    fi
    
    echo "Control plane IP: $CONTROL_PLANE_IP"
    
    # Return to applications directory
    cd - > /dev/null
    
    # Wait for cluster initialization and setup kubectl
    echo -e "${YELLOW}⏳ Waiting for cluster initialization...${NC}"
    
    # Wait for SSH to be available
    echo "Waiting for SSH access to control plane..."
    retry_count=0
    while ! ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$CONTROL_PLANE_IP "echo 'SSH ready'" &>/dev/null; do
        retry_count=$((retry_count + 1))
        if [[ $retry_count -gt 30 ]]; then
            echo -e "${RED}❌ SSH access to control plane timed out${NC}"
            exit 1
        fi
        echo "SSH attempt $retry_count/30..."
        sleep 10
    done
    
    echo "✅ SSH access established"
    
    # Wait for cluster to be ready
    echo "Waiting for Kubernetes cluster to be ready..."
    retry_count=0
    while ! ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$CONTROL_PLANE_IP "kubectl get nodes" &>/dev/null; do
        retry_count=$((retry_count + 1))
        if [[ $retry_count -gt 60 ]]; then
            echo -e "${RED}❌ Kubernetes cluster initialization timed out${NC}"
            exit 1
        fi
        echo "Cluster check attempt $retry_count/60..."
        sleep 10
    done
    
    echo "✅ Kubernetes cluster is ready"
    
    # Copy kubectl config
    echo "Setting up kubectl access..."
    mkdir -p ~/.kube
    scp -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$CONTROL_PLANE_IP:/home/ubuntu/.kube/config ~/.kube/config
    
    # Verify kubectl access
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Failed to configure kubectl access${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Infrastructure provisioned and kubectl configured${NC}"
    
    # Join worker nodes to the cluster
    echo ""
    echo -e "${YELLOW}🔧 Joining worker nodes to cluster...${NC}"
    cd "$TERRAFORM_DIR"
    WORKER_IPS=($(terraform output -json worker_ips | jq -r '.[]'))
    cd - > /dev/null
    
    for i in "${!WORKER_IPS[@]}"; do
        worker_ip=${WORKER_IPS[$i]}
        worker_num=$((i + 1))
        echo "Joining worker-$worker_num ($worker_ip)..."
        
        # Wait for worker to be ready
        retry_count=0
        while ! ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$worker_ip "echo 'ready'" &>/dev/null; do
            retry_count=$((retry_count + 1))
            if [[ $retry_count -gt 30 ]]; then
                echo -e "${RED}❌ Worker-$worker_num not accessible${NC}"
                break
            fi
            echo "Waiting for worker-$worker_num... ($retry_count/30)"
            sleep 10
        done
        
        if [[ $retry_count -le 30 ]]; then
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

# Final cluster connectivity check
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster after setup. Check configuration.${NC}"
    exit 1
fi

# Show cluster information
echo ""
echo -e "${YELLOW}🔍 Cluster Information:${NC}"
echo "Cluster: $(kubectl config current-context)"
echo "Server: $(kubectl cluster-info | grep 'Kubernetes control plane' | awk '{print $7}')"
echo "Nodes: $(kubectl get nodes --no-headers | wc -l)"

# Display resource availability
echo -e "${YELLOW}📊 Available Resources:${NC}"
kubectl top nodes 2>/dev/null || echo "Metrics not available (metrics-server not installed)"

# Deploy the complete system
echo ""
echo -e "${BLUE}🚀 Deploying Complete Plant Monitoring System...${NC}"

# Step 1: Create namespace and install infrastructure
echo "Step 1: Installing infrastructure components..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$EBS_CSI_FILE"

echo "Waiting for EBS CSI components..."
sleep 30

# Step 2: Deploy security components
echo "Step 2: Deploying security configuration..."
kubectl apply -f "$SECURITY_FILE"

# Step 3: Deploy application manifests
echo "Step 3: Deploying application components..."
kubectl apply -f "$MANIFEST_FILE"

# Step 4: Apply network policies
echo "Step 4: Applying network security policies..."
kubectl apply -f "$NETWORK_POLICY_FILE"

# Step 5: Configure autoscaling
echo "Step 5: Configuring horizontal pod autoscaling..."
# Check if metrics server is available first
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    kubectl apply -f "$HPA_FILE"
    echo "✅ HPA configured"
else
    echo "⚠️  Metrics server not found, skipping HPA configuration"
fi

# Wait for namespace
echo "Waiting for namespace to be ready..."
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/$NAMESPACE --timeout=30s

# Wait for StatefulSets
echo "Waiting for StatefulSets to be ready..."
kubectl wait --for=condition=Ready statefulset/mongodb -n $NAMESPACE --timeout=$TIMEOUT
kubectl wait --for=condition=Ready statefulset/kafka -n $NAMESPACE --timeout=$TIMEOUT

# Wait for Deployments  
echo "Waiting for Deployments to be ready..."
kubectl wait --for=condition=Available deployment/plant-processor -n $NAMESPACE --timeout=$TIMEOUT

# Wait for Pods
echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n $NAMESPACE --timeout=$TIMEOUT

echo -e "${GREEN}✅ Deployment completed successfully!${NC}"

# Get access information for Home Assistant
echo ""
echo -e "${YELLOW}🏠 Setting up Home Assistant access...${NC}"

# Wait specifically for Home Assistant to be ready
echo "Waiting for Home Assistant to be available..."
kubectl wait --for=condition=ready pod -l app=homeassistant -n $NAMESPACE --timeout=300s

# Enhanced DNS and Service Discovery Setup
echo "Setting up DNS and service discovery..."

# Get node IP for external access
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
if [[ -z "$NODE_IP" ]]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi

# Create NodePort services for external access
echo "Creating external access services..."
kubectl patch svc homeassistant-service -n $NAMESPACE -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":8123,"targetPort":8123,"nodePort":30123},{"name":"mqtt","port":1883,"targetPort":1883,"nodePort":31883}]}}' 2>/dev/null || echo "Service already configured"

# Set up local DNS resolution (for development)
HOST_ENTRY="$NODE_IP plant-monitor.local mqtt.plant-monitor.local"
if ! grep -q "plant-monitor.local" /etc/hosts 2>/dev/null; then
    echo "$HOST_ENTRY" | sudo tee -a /etc/hosts > /dev/null 2>&1 || echo "Note: Add '$HOST_ENTRY' to /etc/hosts for local DNS"
fi

# Display deployment status
echo ""
echo -e "${BLUE}📋 Deployment Status:${NC}"
echo "Namespace: $NAMESPACE"
kubectl get all -n $NAMESPACE

# Display persistent volumes
echo ""
echo -e "${BLUE}💾 Storage Status:${NC}"
kubectl get pv,pvc -n $NAMESPACE

# Display resource usage
echo ""
echo -e "${BLUE}📈 Resource Usage:${NC}"
kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Pod metrics not available"

# Provide useful commands
echo ""
echo -e "${GREEN}🎉 Plant Monitoring System with Home Assistant is now running!${NC}"
echo ""
echo -e "${BLUE}🌍 Access Information:${NC}"
echo "============================================================================"
echo "🏠 Home Assistant Dashboard:"
echo "  🌐 DNS (Recommended): http://plant-monitor.local:30123"
echo "  📍 Direct IP: http://$NODE_IP:30123"
echo "  🔗 Port Forward: kubectl port-forward svc/homeassistant-service 8123:8123 -n $NAMESPACE"
echo "      Then browse: http://localhost:8123"
echo ""
echo "📨 MQTT Broker (for Home Assistant setup):"
echo "  🌐 DNS Broker: mqtt.plant-monitor.local"
echo "  📍 IP Broker: $NODE_IP"
echo "  🔌 Port: 31883 (external) or 1883 (internal)"
echo "  🔐 Authentication: None (allow anonymous)"
echo ""
echo "🔧 Service Discovery:"
echo "  Internal DNS: homeassistant-service.plant-monitoring.svc.cluster.local:8123"
echo "  MQTT Internal: homeassistant-service.plant-monitoring.svc.cluster.local:1883"
echo ""
echo "🔧 Initial Home Assistant Setup:"
echo "1. Browse to: http://plant-monitor.local:30123 (or IP version above)"
echo "2. Create your admin user account"
echo "3. Go to Settings → Devices & services → Add Integration"
echo "4. Search for 'MQTT' and configure:"
echo "     Broker: mqtt.plant-monitor.local (or $NODE_IP)"
echo "     Port: 31883"
echo "     Enable Discovery: Yes"
echo "5. Wait for plant sensors to auto-discover and appear"
echo ""
echo "💡 Pro Tip: For external access, run DNS update script:"
echo "   ./update-dns.sh"
echo ""
echo -e "${YELLOW}📝 Useful Commands:${NC}"
echo "Monitor system health:"
echo "  kubectl logs -f system-monitor -n $NAMESPACE"
echo ""
echo "Check MongoDB (updated credentials):"
echo "  kubectl exec -it mongodb-0 -n $NAMESPACE -- mongosh -u plantuser -p PlantUserPass123!"
echo ""
echo "Test Kafka:"
echo "  kubectl exec -it kafka-0 -n $NAMESPACE -- kafka-topics --bootstrap-server localhost:9092 --list"
echo ""
echo "View processor logs:"
echo "  kubectl logs -f deployment/plant-processor -n $NAMESPACE"
echo ""
echo "View Home Assistant logs:"
echo "  kubectl logs -f deployment/homeassistant -c homeassistant -n $NAMESPACE"
echo ""
echo "View MQTT broker logs:"
echo "  kubectl logs -f deployment/homeassistant -c mosquitto -n $NAMESPACE"
echo ""
echo "View plant sensor logs:"
echo "  kubectl logs -f deployment/plant-sensor-001 -n $NAMESPACE"
echo "  kubectl logs -f deployment/plant-sensor-002 -n $NAMESPACE"
echo ""
echo "Get all resources:"
echo "  kubectl get all -n $NAMESPACE"
echo ""
echo "Scale processor (if needed):"
echo "  kubectl scale deployment/plant-processor --replicas=2 -n $NAMESPACE"
echo ""
echo "Run smoke test:"
echo "  ./smoke-test.sh"
echo ""
echo "Clean up deployment:"
echo "  ./teardown-production.sh"

# Run smoke test automatically
echo ""
echo -e "${BLUE}🧪 Running Smoke Test...${NC}"
if [[ -f "smoke-test.sh" ]]; then
    chmod +x smoke-test.sh
    ./smoke-test.sh
else
    echo -e "${YELLOW}⚠️  smoke-test.sh not found, skipping automated test${NC}"
fi

# Wait for user to see status
echo ""
echo -e "${YELLOW}Press any key to show live system monitor...${NC}"
read -n 1 -s

# Show live monitoring
echo -e "${BLUE}📊 Live System Monitor (Ctrl+C to exit):${NC}"
kubectl logs -f system-monitor -n $NAMESPACE