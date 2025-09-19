#!/bin/bash

# Generate Ansible Inventory from Terraform Outputs
# This script creates the inventory.ini file for Ansible using Terraform outputs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
ANSIBLE_DIR="$SCRIPT_DIR/../application-deployment"

echo "🔧 Generating Ansible inventory from Terraform outputs..."

# Check if Terraform state exists
if [ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    echo "❌ Error: terraform.tfstate not found. Please run 'terraform apply' first."
    exit 1
fi

# Generate inventory using Terraform output
cd "$TERRAFORM_DIR"
terraform output -raw ansible_inventory > "$ANSIBLE_DIR/inventory.ini"

if [ $? -eq 0 ]; then
    echo "✅ Ansible inventory generated successfully at: $ANSIBLE_DIR/inventory.ini"
    echo ""
    echo "📋 Generated inventory preview:"
    head -n 20 "$ANSIBLE_DIR/inventory.ini"
else
    echo "❌ Error: Failed to generate Ansible inventory"
    exit 1
fi