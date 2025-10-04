#!/bin/bash
# Plant Monitoring System - Complete Teardown Script
# CS5287 CA2 - PaaS Implementation
# 
# This script completely removes the Plant Monitoring System from Kubernetes

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="plant-monitoring"

echo -e "${RED}🗑️  Plant Monitoring System - Complete Teardown${NC}"
echo "=================================================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster. Check your kubeconfig.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"

# Show what will be deleted
echo ""
echo -e "${YELLOW}📋 Resources to be deleted:${NC}"
echo "Namespace: $NAMESPACE"
kubectl get all -n $NAMESPACE 2>/dev/null | head -10 || echo "No resources found"

# Confirm deletion
echo ""
read -p "Are you sure you want to delete the entire Plant Monitoring System? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Teardown cancelled"
    exit 0
fi

echo ""
echo -e "${BLUE}🚀 Starting teardown process...${NC}"

# Step 1: Delete HPA first to stop scaling
echo "Step 1: Removing autoscaling configuration..."
kubectl delete hpa --all -n $NAMESPACE --ignore-not-found=true

# Step 2: Delete application components
echo "Step 2: Removing application components..."
kubectl delete deployment --all -n $NAMESPACE --ignore-not-found=true
kubectl delete statefulset --all -n $NAMESPACE --ignore-not-found=true
kubectl delete pod --all -n $NAMESPACE --ignore-not-found=true

# Step 3: Delete services and networking
echo "Step 3: Removing services and network policies..."
kubectl delete service --all -n $NAMESPACE --ignore-not-found=true
kubectl delete networkpolicy --all -n $NAMESPACE --ignore-not-found=true

# Step 4: Delete configuration and secrets
echo "Step 4: Removing configuration and secrets..."
kubectl delete configmap --all -n $NAMESPACE --ignore-not-found=true
kubectl delete secret --all -n $NAMESPACE --ignore-not-found=true

# Step 5: Delete persistent storage
echo "Step 5: Removing persistent storage..."
kubectl delete pvc --all -n $NAMESPACE --ignore-not-found=true
kubectl delete pv mongodb-pv kafka-pv --ignore-not-found=true

# Step 6: Delete namespace
echo "Step 6: Removing namespace..."
kubectl delete namespace $NAMESPACE --ignore-not-found=true

# Step 7: Clean up EBS CSI driver (optional)
echo "Step 7: EBS CSI Driver cleanup (optional)..."
read -p "Do you want to remove the EBS CSI driver? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete deployment ebs-csi-controller -n kube-system --ignore-not-found=true
    kubectl delete daemonset ebs-csi-node -n kube-system --ignore-not-found=true
    kubectl delete storageclass gp2 gp3 --ignore-not-found=true
    kubectl delete csidriver ebs.csi.aws.com --ignore-not-found=true
    echo "✅ EBS CSI driver removed"
else
    echo "ℹ️  EBS CSI driver kept (can be used by other applications)"
fi

# Wait for cleanup to complete
echo ""
echo "Waiting for cleanup to complete..."
sleep 10

# Verify cleanup
echo ""
echo -e "${BLUE}📊 Teardown Status:${NC}"
echo "Namespace status:"
kubectl get namespace $NAMESPACE 2>/dev/null || echo "✅ Namespace deleted"

echo ""
echo "Remaining PVs:"
kubectl get pv | grep -E "(mongodb-pv|kafka-pv)" || echo "✅ No Plant Monitoring PVs found"

echo ""
echo "Storage classes:"
kubectl get storageclass | grep gp2 || echo "✅ gp2 StorageClass removed"

echo ""
echo -e "${GREEN}✅ Plant Monitoring System teardown completed!${NC}"
echo ""
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo "• Verify no AWS EBS volumes are orphaned (check AWS Console)"
echo "• Check for any remaining resources: kubectl get all -A | grep plant"
echo "• Redeploy with: ./deploy-production.sh"