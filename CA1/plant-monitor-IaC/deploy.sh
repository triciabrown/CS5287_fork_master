#!/bin/bash

# Plant Monitoring System - Terraform + Ansible Deployment Script
# This script deploys infrastructure with Terraform and applications with Ansible

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/application-deployment"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        print_status "Visit: https://developer.hashicorp.com/terraform/downloads"
        exit 1
    fi
    
    # Check if Ansible is installed
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "Ansible is not installed. Please install Ansible first."
        print_status "Run: sudo apt update && sudo apt install ansible"
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_warning "AWS CLI not configured or credentials not set"
        print_status "Please run: aws configure"
    fi
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/plant-monitoring-key.pem ]; then
        print_warning "SSH key not found at ~/.ssh/plant-monitoring-key.pem"
        print_status "Please ensure your AWS key pair is downloaded and placed at that location"
        print_status "Run: chmod 400 ~/.ssh/plant-monitoring-key.pem"
    fi
    
    print_success "Prerequisites checked"
}

# Function to deploy infrastructure
deploy_infrastructure() {
    print_status "Deploying infrastructure with Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform if not already done
    if [ ! -d ".terraform" ]; then
        print_status "Initializing Terraform..."
        terraform init
    fi
    
    # Plan the deployment
    print_status "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    # Apply the deployment
    print_status "Applying Terraform configuration..."
    terraform apply tfplan
    
    if [ $? -eq 0 ]; then
        print_success "Infrastructure deployed successfully"
    else
        print_error "Infrastructure deployment failed"
        exit 1
    fi
}

# Function to generate Ansible inventory
generate_inventory() {
    print_status "Generating Ansible inventory from Terraform outputs..."
    
    cd "$TERRAFORM_DIR"
    ./generate-inventory.sh
    
    if [ $? -eq 0 ]; then
        print_success "Ansible inventory generated"
    else
        print_error "Failed to generate Ansible inventory"
        exit 1
    fi
}

# Function to wait for instances to be ready
wait_for_instances() {
    print_status "Waiting for EC2 instances to be ready..."
    
    # Install jq if not available
    if ! command -v jq &> /dev/null; then
        print_status "Installing jq for JSON parsing..."
        sudo apt update && sudo apt install -y jq
    fi
    
    # Get the Home Assistant public IP for connectivity test
    cd "$TERRAFORM_DIR"
    HA_PUBLIC_IP=$(terraform output -json instance_details | jq -r '.homeassistant.public_ip')
    
    if [ -z "$HA_PUBLIC_IP" ] || [ "$HA_PUBLIC_IP" = "null" ]; then
        print_error "Could not get Home Assistant public IP"
        exit 1
    fi
    
    print_status "Testing SSH connectivity to bastion host ($HA_PUBLIC_IP)..."
    
    # Wait up to 5 minutes for SSH to be ready
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ssh -i ~/.ssh/plant-monitoring-key.pem -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no ubuntu@$HA_PUBLIC_IP exit &>/dev/null; then
            print_success "SSH connectivity established"
            break
        else
            print_status "Attempt $attempt/$max_attempts - SSH not ready, waiting 10 seconds..."
            sleep 10
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_error "SSH connectivity test failed after $max_attempts attempts"
        print_status "You may need to check security groups or wait longer for instances to boot"
        exit 1
    fi
}

# Function to deploy applications
deploy_applications() {
    print_status "Deploying applications with Ansible..."
    
    cd "$ANSIBLE_DIR"
    
    # Check if inventory exists
    if [ ! -f "inventory.ini" ]; then
        print_error "Ansible inventory not found. Please generate it first."
        exit 1
    fi
    
    # Install Docker on all VMs
    print_status "Installing Docker on all VMs..."
    if ansible-playbook -i inventory.ini setup_docker.yml; then
        print_success "Docker installation completed"
    else
        print_error "Docker installation failed"
        exit 1
    fi
    
    # Deploy applications
    print_status "Deploying applications to VMs..."
    if ansible-playbook -i inventory.ini deploy_kafka.yml deploy_mongodb.yml deploy_processor.yml deploy_homeassistant.yml; then
        print_success "Application deployment completed"
    else
        print_error "Application deployment failed"
        return 1
    fi
    
    # Run health checks
    print_status "Running health checks..."
    if ansible-playbook -i inventory.ini health_check.yml; then
        print_success "Health checks passed"
    else
        print_warning "Some health checks may have failed"
    fi
}

# Function to show deployment summary
show_summary() {
    print_status "Deployment Summary"
    echo "=========================================="
    
    cd "$TERRAFORM_DIR"
    
    # Show connection info
    echo ""
    print_status "🔗 Connection Information:"
    terraform output connection_info | jq -r '
        "Bastion Host (Home Assistant): \(.bastion_host.command)",
        "",
        "Private Instance Access:",
        "  Kafka:     \(.private_instances.kafka)",
        "  MongoDB:   \(.private_instances.mongodb)", 
        "  Processor: \(.private_instances.processor)"
    '
    
    # Show instance details  
    echo ""
    print_status "🖥️  Instance Details:"
    terraform output instance_details | jq -r '
        "Kafka:        \(.kafka.private_ip)",
        "MongoDB:      \(.mongodb.private_ip)",
        "Processor:    \(.processor.private_ip)",
        "Home Assistant: \(.homeassistant.private_ip) (Public: \(.homeassistant.public_ip))"
    '
    
    # Show Home Assistant URL
    HA_PUBLIC_IP=$(terraform output -raw instance_details | jq -r '.homeassistant.public_ip')
    echo ""
    print_success "🌱 Plant Monitoring Dashboard: http://$HA_PUBLIC_IP:8123"
    echo ""
    print_success "✅ Deployment completed successfully!"
}

# Main execution
main() {
    echo "=========================================="
    echo "🚀 PLANT MONITORING SYSTEM DEPLOYMENT"
    echo "🔧 Terraform + Ansible Architecture"
    echo "=========================================="
    
    check_prerequisites
    
    print_status "Phase 1: Infrastructure Deployment (Terraform)"
    deploy_infrastructure
    
    print_status "Phase 2: Inventory Generation"
    generate_inventory
    
    print_status "Phase 3: Instance Readiness Check"
    wait_for_instances
    
    print_status "Phase 4: Application Deployment (Ansible)"
    deploy_applications
    
    show_summary
}

# Handle script arguments
case "${1:-}" in
    "infra")
        print_status "Deploying infrastructure only..."
        check_prerequisites
        deploy_infrastructure
        generate_inventory
        ;;
    "apps")
        print_status "Deploying applications only..."
        check_prerequisites
        wait_for_instances
        deploy_applications
        ;;
    "clean")
        print_status "Cleaning up infrastructure..."
        cd "$TERRAFORM_DIR"
        terraform destroy
        ;;
    *)
        main
        ;;
esac