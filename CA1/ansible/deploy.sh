#!/bin/bash

# Complete Plant Monitoring System Deployment Script
# This script deploys the entire infrastructure and applications automatically

set -e  # Exit on any error

echo "=========================================="
echo "🚀 PLANT MONITORING SYSTEM DEPLOYMENT"
echo "=========================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the correct directory
if [ ! -f "inventory.ini" ]; then
    print_error "inventory.ini not found. Please run this script from the CA1/ansible directory."
    exit 1
fi

# Check if Ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    print_error "Ansible is not installed. Please install Ansible first."
    exit 1
fi

print_status "Starting deployment process..."

# Phase 1: Infrastructure Deployment
print_status "Phase 1: Deploying AWS Infrastructure..."
if ansible-playbook -i inventory.ini networking.yml; then
    print_success "Networking infrastructure deployed"
else
    print_error "Failed to deploy networking infrastructure"
    exit 1
fi

if ansible-playbook -i inventory.ini security.yml; then
    print_success "Security groups deployed"
else
    print_error "Failed to deploy security groups"
    exit 1
fi

if ansible-playbook -i inventory.ini compute.yml; then
    print_success "EC2 instances deployed"
else
    print_error "Failed to deploy EC2 instances"
    exit 1
fi

if ansible-playbook -i inventory.ini network_endpoints.yml; then
    print_success "Network endpoints configured"
else
    print_error "Failed to configure network endpoints"
    exit 1
fi

print_success "✅ AWS Infrastructure deployment completed!"

# Wait for instances to be fully ready
print_status "Waiting for EC2 instances to be fully ready..."
sleep 60

# Phase 2: Application Deployment
print_status "Phase 2: Deploying Applications..."

print_status "Installing Docker on all VMs..."
if ansible-playbook -i inventory.ini setup_docker.yml; then
    print_success "Docker installed on all VMs"
else
    print_error "Failed to install Docker"
    exit 1
fi

print_status "Deploying Kafka service..."
if ansible-playbook -i inventory.ini deploy_kafka.yml; then
    print_success "Kafka deployed successfully"
else
    print_error "Failed to deploy Kafka"
    exit 1
fi

print_status "Deploying MongoDB service..."
if ansible-playbook -i inventory.ini deploy_mongodb.yml; then
    print_success "MongoDB deployed successfully"
else
    print_error "Failed to deploy MongoDB"
    exit 1
fi

print_status "Deploying Plant Processor service..."
if ansible-playbook -i inventory.ini deploy_processor.yml; then
    print_success "Plant Processor deployed successfully"
else
    print_error "Failed to deploy Plant Processor"
    exit 1
fi

print_status "Deploying Home Assistant and Plant Sensors..."
if ansible-playbook -i inventory.ini deploy_homeassistant.yml; then
    print_success "Home Assistant and Plant Sensors deployed successfully"
else
    print_error "Failed to deploy Home Assistant"
    exit 1
fi

print_success "✅ Application deployment completed!"

# Phase 3: System Validation
print_status "Phase 3: Running System Health Check..."
sleep 30  # Give services time to fully start

if ansible-playbook -i inventory.ini health_check.yml; then
    print_success "System health check completed"
else
    print_warning "Health check completed with some issues - check the output above"
fi

# Get the Home Assistant IP for access information
HA_IP=$(ansible-inventory -i inventory.ini --host vm-4-homeassistant | grep ansible_host | cut -d'"' -f4)

echo ""
echo "=========================================="
echo "🎉 DEPLOYMENT COMPLETED!"
echo "=========================================="
echo ""
echo "📊 System Status: All components deployed"
echo "🌐 Home Assistant Dashboard: http://${HA_IP}:8123"
echo "🔑 SSH Access (bastion): ssh ubuntu@${HA_IP}"
echo ""
echo "📖 Next Steps:"
echo "1. Access the Home Assistant dashboard using the URL above"
echo "2. Wait 2-3 minutes for all services to fully initialize"
echo "3. Check sensor data is appearing in the dashboard"
echo "4. Monitor system logs if needed:"
echo "   - SSH to each VM and run 'docker compose logs' in the app directories"
echo ""
echo "🎯 Project completed successfully! Your IoT plant monitoring system is ready."
echo "=========================================="