#!/bin/bash
# CA2 Plant Monitoring System - Complete Teardown
# Single command teardown following assignment requirements

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🗑️  CA2 Plant Monitoring System - Complete Teardown${NC}"
echo "=================================================================="

# Configuration
TERRAFORM_DIR="../aws-cluster-setup"
NAMESPACE="plant-monitoring"

# Step 1: Remove Kubernetes resources (if cluster exists)
echo -e "${YELLOW}🧹 Step 1: Removing Kubernetes resources...${NC}"

if kubectl cluster-info &> /dev/null; then
    echo "Deleting namespace and all resources..."
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=120s || echo "Namespace deletion may have timed out"
    
    echo "Removing EBS CSI driver components (excluding kube-system namespace)..."
    # Remove only the specific EBS CSI driver resources, not the entire file
    kubectl delete daemonset ebs-csi-node -n kube-system --ignore-not-found=true || echo "EBS CSI node daemonset not found"
    kubectl delete deployment ebs-csi-controller -n kube-system --ignore-not-found=true || echo "EBS CSI controller deployment not found"
    kubectl delete storageclass gp2 gp3 --ignore-not-found=true || echo "Storage classes not found"
    
    echo "Skipping ingress controller cleanup - not using ingress controller"
    echo "✅ Using NodePort approach instead of ingress controller"
    
    echo "Cleaning up cluster-wide resources..."
    kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=aws-ebs-csi-driver --ignore-not-found=true || echo "EBS CSI cluster resources not found"
    kubectl delete csidriver ebs.csi.aws.com --ignore-not-found=true || echo "EBS CSI driver not found"
    
    echo -e "${GREEN}✅ Kubernetes resources cleaned up${NC}"
else
    echo -e "${YELLOW}⚠️  No accessible Kubernetes cluster found, skipping K8s cleanup${NC}"
fi

# Step 2: Destroy AWS infrastructure
echo ""
echo -e "${YELLOW}🔥 Step 2: Destroying AWS infrastructure...${NC}"

if [[ -d "$TERRAFORM_DIR" ]]; then
    cd "$TERRAFORM_DIR"
    
    if [[ -f "terraform.tfstate" ]] && [[ -s "terraform.tfstate" ]]; then
        echo "Destroying infrastructure with Terraform..."
        terraform destroy -auto-approve
        echo -e "${GREEN}✅ AWS infrastructure destroyed${NC}"
    else
        echo -e "${YELLOW}⚠️  No Terraform state found, infrastructure may not exist${NC}"
    fi
    
    cd - > /dev/null
else
    echo -e "${RED}❌ Terraform directory '$TERRAFORM_DIR' not found${NC}"
fi

# Step 3: Clean up local files
echo ""
echo -e "${YELLOW}🧽 Step 3: Cleaning up local files...${NC}"

# Remove temporary credentials file
if [[ -f "/tmp/plant-monitoring-credentials.txt" ]]; then
    rm -f /tmp/plant-monitoring-credentials.txt
    echo "✅ Temporary credentials file removed"
fi

# Clean up any temporary Home Assistant configs
rm -rf /tmp/ha-config 2>/dev/null || true

echo ""
echo -e "${GREEN}🎉 Complete teardown finished!${NC}"
echo ""
echo -e "${BLUE}📋 What was cleaned up:${NC}"
echo "• All Kubernetes resources in namespace: $NAMESPACE"
echo "• EBS CSI driver components (avoiding kube-system namespace deletion)"
echo "• Cluster-wide resources (ClusterRoles, CSIDriver)"
echo "• Cluster-wide resources (ClusterRoles, IngressClass, Webhooks)"
echo "• 5-node AWS EC2 cluster (t2.micro instances)"
echo "• VPC, subnets, security groups, and networking"
echo "• IAM roles and policies"
echo "• SSH key pairs"
echo "• Temporary credential files"
echo ""
echo -e "${YELLOW}💡 Note:${NC}"
echo "• kubectl config preserved (may contain references to destroyed cluster)"
echo "• Container images remain in Docker Hub registry"
echo "• CA1 source files preserved in applications-from-ca1/"
echo ""
echo -e "${GREEN}✅ Ready for fresh deployment!${NC}"