#!/bin/bash

##########################################
# PLANT MONITORING SYSTEM - TEARDOWN
# Safely destroy all AWS resources
##########################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
TERRAFORM_DIR="terraform"
APP_DIR="application-deployment"

print_header() {
    echo ""
    echo "============================================"
    echo "🗑️  PLANT MONITORING SYSTEM TEARDOWN"
    echo "🔧 Terraform Infrastructure Cleanup"
    echo "============================================"
}

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

confirm_teardown() {
    echo ""
    print_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo "This will permanently destroy ALL AWS resources including:"
    echo "  • EC2 instances (4 VMs)"
    echo "  • VPC and networking components"
    echo "  • Security groups"
    echo "  • Elastic IPs"
    echo "  • AWS Secrets Manager secrets"
    echo "  • NAT Gateway (incurs charges)"
    echo ""
    echo "💾 All application data on VMs will be LOST!"
    echo ""
    read -p "❓ Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        echo "❌ Teardown cancelled by user"
        exit 0
    fi
}

stop_applications() {
    print_status "Phase 1: Stopping applications gracefully..."
    
    if [ -f "$APP_DIR/inventory.ini" ]; then
        print_status "Stopping Docker containers on all VMs..."
        
        # Stop MongoDB
        print_status "Stopping MongoDB..."
        ansible mongodb_vm -i "$APP_DIR/inventory.ini" -m shell \
            -a "cd /opt/apps/mongodb && docker compose down -v" \
            --become-user ubuntu || print_warning "MongoDB stop failed (may already be stopped)"
        
        # Stop Kafka
        print_status "Stopping Kafka..."
        ansible kafka_vm -i "$APP_DIR/inventory.ini" -m shell \
            -a "cd /opt/apps && find . -name 'docker-compose.yml' -execdir docker compose down -v \;" \
            --become-user ubuntu || print_warning "Kafka stop failed (may already be stopped)"
        
        # Stop Home Assistant
        print_status "Stopping Home Assistant..."
        ansible homeassistant_vm -i "$APP_DIR/inventory.ini" -m shell \
            -a "cd /opt/apps && find . -name 'docker-compose.yml' -execdir docker compose down -v \;" \
            --become-user ubuntu || print_warning "Home Assistant stop failed (may already be stopped)"
        
        # Stop Processor
        print_status "Stopping Processor..."
        ansible processor_vm -i "$APP_DIR/inventory.ini" -m shell \
            -a "cd /opt/apps && find . -name 'docker-compose.yml' -execdir docker compose down -v \;" \
            --become-user ubuntu || print_warning "Processor stop failed (may already be stopped)"
            
        print_success "Applications stopped gracefully"
    else
        print_warning "No inventory found - skipping application cleanup"
    fi
}

destroy_infrastructure() {
    print_status "Phase 2: Destroying AWS infrastructure with Terraform..."
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        print_error "Terraform directory not found!"
        exit 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    print_status "Planning infrastructure destruction..."
    terraform plan -destroy -out=destroy.tfplan
    
    print_status "Executing infrastructure destruction..."
    terraform apply destroy.tfplan
    
    print_status "Cleaning up Terraform state files..."
    rm -f destroy.tfplan
    rm -f terraform.tfstate.backup
    
    cd ..
    print_success "Infrastructure destroyed successfully"
}

verify_cleanup() {
    print_status "Phase 3: Verifying cleanup..."
    
    print_status "Checking for remaining EC2 instances..."
    INSTANCES=$(aws ec2 describe-instances --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' --output text)
    
    if [ -n "$INSTANCES" ]; then
        print_warning "Remaining instances found: $INSTANCES"
        print_warning "These may be from other projects or still terminating"
    else
        print_success "No active EC2 instances found"
    fi
    
    print_status "Checking for remaining Elastic IPs..."
    EIPS=$(aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].AllocationId' --output text)
    
    if [ -n "$EIPS" ]; then
        print_warning "Unassociated Elastic IPs found: $EIPS"
        print_warning "Consider releasing these to avoid charges"
    else
        print_success "No unassociated Elastic IPs found"
    fi
}

cleanup_local_files() {
    print_status "Phase 4: Cleaning up local files..."
    
    # Remove generated inventory
    if [ -f "$APP_DIR/inventory.ini" ]; then
        print_status "Removing generated inventory file..."
        rm -f "$APP_DIR/inventory.ini"
    fi
    
    # Clean up any temporary files
    print_status "Removing temporary files..."
    find . -name "*.tmp" -delete 2>/dev/null || true
    find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
    
    print_success "Local cleanup completed"
}

main() {
    print_header
    
    confirm_teardown
    
    stop_applications
    destroy_infrastructure  
    verify_cleanup
    cleanup_local_files
    
    echo ""
    print_success "🎉 Teardown completed successfully!"
    echo ""
    print_status "Summary:"
    echo "  ✅ Applications stopped gracefully"
    echo "  ✅ AWS infrastructure destroyed"
    echo "  ✅ Terraform state cleaned"
    echo "  ✅ Local files cleaned"
    echo ""
    print_warning "💡 Remember to check your AWS billing console to confirm no resources are still running"
    print_status "💾 Any local backups in /opt/* directories on your local machine have been preserved"
    echo ""
}

# Run main function
main "$@"