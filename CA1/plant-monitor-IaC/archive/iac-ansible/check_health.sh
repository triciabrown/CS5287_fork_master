#!/bin/bash

# Quick Health Check Script for Plant Monitoring System
# This script runs just the health check without full deployment

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the correct directory
if [ ! -f "inventory.ini" ]; then
    print_error "inventory.ini not found. Please run this script from the CA1/ansible directory."
    exit 1
fi

print_status "Running Plant Monitoring System Health Check..."

if ansible-playbook -i inventory.ini health_check.yml; then
    print_success "Health check completed successfully!"
else
    print_error "Health check completed with issues - see output above for details"
    exit 1
fi

echo ""
print_success "✅ Health check finished. Check the report above for system status."