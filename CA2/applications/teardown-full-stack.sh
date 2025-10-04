#!/bin/bash
# Plant Monitoring System - Complete Stack Teardown
# CS5287 CA2 - PaaS Implementation
# 
# Single command teardown script that:
# 1. Removes all Kubernetes resources
# 2. Destroys AWS infrastructure with Terraform

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="plant-monitoring"
TERRAFORM_DIR="../aws-cluster-setup"

echo -e "${BLUE}🗑️  Plant Monitoring System - Complete Stack Teardown${NC}"
echo "============================================================================"

# Step 1: Remove Kubernetes resources (if cluster exists)
echo -e "${YELLOW}🧹 Removing Kubernetes resources...${NC}"

if kubectl cluster-info &> /dev/null; then
    echo "Deleting namespace and all resources..."
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=120s || echo "Namespace deletion may have timed out"
    
    echo "Removing EBS CSI driver..."
    kubectl delete -f aws-ebs-csi-driver.yaml --ignore-not-found=true || echo "EBS CSI driver not found or already removed"
    
    echo "Cleaning up cluster-wide resources..."
    kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=aws-ebs-csi-driver --ignore-not-found=true || echo "Cluster resources not found"
    
    echo -e "${GREEN}✅ Kubernetes resources cleaned up${NC}"
else
    echo -e "${YELLOW}⚠️  No accessible Kubernetes cluster found, skipping K8s cleanup${NC}"
fi

# Step 2: Destroy AWS infrastructure
echo ""
echo -e "${YELLOW}🔥 Destroying AWS infrastructure...${NC}"

if [[ -d "$TERRAFORM_DIR" ]]; then
    cd "$TERRAFORM_DIR"
    
    if [[ -f "terraform.tfstate" ]]; then
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

# Step 3: Clean up local configuration
echo ""
echo -e "${YELLOW}🧽 Cleaning up local configuration...${NC}"

# Remove kubectl config (optional, commented out to preserve other clusters)
# rm -f ~/.kube/config

# Remove local DNS entries (optional)
if grep -q "plant-monitor.local" /etc/hosts 2>/dev/null; then
    echo "Note: You may want to remove plant-monitor.local entries from /etc/hosts"
fi

echo ""
echo -e "${GREEN}🎉 Complete stack teardown finished!${NC}"
echo ""
echo -e "${BLUE}📋 What was cleaned up:${NC}"
echo "• All Kubernetes resources in namespace: $NAMESPACE"
echo "• EBS CSI driver and related cluster resources"
echo "• 3-node AWS EC2 cluster (t2.micro instances)"
echo "• VPC, subnets, security groups, and networking"
echo "• IAM roles and policies"
echo "• SSH key pairs"
echo ""
echo -e "${YELLOW}💡 Note:${NC}"
echo "• kubectl config preserved (may contain references to destroyed cluster)"
echo "• Local DNS entries in /etc/hosts preserved"
echo "• Container images remain in Docker Hub registry"