#!/bin/bash
# ============================================================================
# CA4 Teardown Script - Complete Infrastructure Destruction
# ============================================================================
# This script safely tears down the entire CA4 edge-to-cloud architecture:
# - Edge sensors (Docker Compose)
# - Edge VPN (WireGuard)
# - Cloud Docker Swarm services
# - AWS infrastructure (Terraform)
# - Generated configuration files
#
# Usage: ./teardown.sh [--force]
#        --force: Skip confirmation prompts
# ============================================================================

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA4_ROOT="$(dirname "${SCRIPT_DIR}")"

# Configuration
EDGE_SITE="${CA4_ROOT}/edge-site"
CLOUD_SITE="${CA4_ROOT}/cloud-site"
TERRAFORM_DIR="${CLOUD_SITE}/terraform"
VPN_CONFIG="${CA4_ROOT}/vpn-config"
MANAGER_IP_FILE="${CA4_ROOT}/.manager-ip"
SSH_KEY="${HOME}/.ssh/docker-swarm-key"

FORCE_MODE=false
if [[ "$1" == "--force" ]]; then
    FORCE_MODE=true
fi

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║$(printf '%64s' | tr ' ' ' ')║${NC}"
    echo -e "${CYAN}║  $(printf '%-60s' "$1")  ║${NC}"
    echo -e "${CYAN}║$(printf '%64s' | tr ' ' ' ')║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$FORCE_MODE" == true ]]; then
        print_info "Force mode: Auto-confirming: $message"
        return 0
    fi
    
    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    while true; do
        echo -ne "${YELLOW}${message} ${prompt}: ${NC}"
        read -r response
        
        # Use default if no response
        if [[ -z "$response" ]]; then
            response="$default"
        fi
        
        case "$response" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# ============================================================================
# Teardown Functions
# ============================================================================

stop_edge_sensors() {
    print_header "Stopping Edge Sensors"
    
    if [[ -d "$EDGE_SITE" ]]; then
        cd "$EDGE_SITE"
        if [[ -f "docker-compose.yml" ]]; then
            print_info "Stopping edge sensor containers..."
            docker compose down -v 2>&1 || print_warning "Edge sensors already stopped or not running"
            print_success "Edge sensors stopped"
        else
            print_warning "No docker-compose.yml found in $EDGE_SITE"
        fi
    else
        print_warning "Edge site directory not found: $EDGE_SITE"
    fi
}

stop_edge_vpn() {
    print_header "Stopping Edge VPN"
    
    if sudo wg show wg0 &>/dev/null; then
        print_info "Bringing down WireGuard VPN interface..."
        sudo wg-quick down wg0 || print_warning "VPN already stopped"
        print_success "VPN interface stopped"
    else
        print_info "WireGuard VPN not active"
    fi
}

remove_cloud_stack() {
    print_header "Removing Cloud Docker Stack"
    
    if [[ ! -f "$MANAGER_IP_FILE" ]]; then
        print_warning "Manager IP file not found. Skipping cloud stack removal."
        return
    fi
    
    MANAGER_IP=$(cat "$MANAGER_IP_FILE")
    print_info "Manager IP: $MANAGER_IP"
    
    if [[ ! -f "$SSH_KEY" ]]; then
        print_warning "SSH key not found at $SSH_KEY. Skipping cloud stack removal."
        return
    fi
    
    print_info "Connecting to manager to remove stack..."
    
    # Check if stack exists
    STACK_EXISTS=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "docker stack ls --format '{{.Name}}' | grep -w 'plant-monitoring' || true" 2>/dev/null || echo "")
    
    if [[ -n "$STACK_EXISTS" ]]; then
        print_info "Removing plant-monitoring stack..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
            "docker stack rm plant-monitoring" || print_warning "Failed to remove stack"
        
        # Wait for stack removal
        print_info "Waiting for services to terminate (30s)..."
        sleep 30
        print_success "Stack removed"
    else
        print_info "No stack to remove"
    fi
}

stop_cloud_vpn() {
    print_header "Stopping Cloud VPN"
    
    if [[ ! -f "$MANAGER_IP_FILE" ]]; then
        print_warning "Manager IP file not found. Skipping cloud VPN removal."
        return
    fi
    
    MANAGER_IP=$(cat "$MANAGER_IP_FILE")
    
    if [[ ! -f "$SSH_KEY" ]]; then
        print_warning "SSH key not found. Skipping cloud VPN removal."
        return
    fi
    
    print_info "Stopping WireGuard on manager node..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" ubuntu@"$MANAGER_IP" \
        "sudo wg-quick down wg0 2>/dev/null || true" || print_warning "VPN already stopped on manager"
    
    print_success "Cloud VPN stopped"
}

destroy_terraform() {
    print_header "Destroying Terraform Infrastructure"
    
    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        print_error "Terraform directory not found: $TERRAFORM_DIR"
        return 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    if [[ ! -f "terraform.tfstate" ]]; then
        print_warning "No terraform state found. Infrastructure may already be destroyed."
        return
    fi
    
    # Check if there are resources to destroy
    RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l || echo "0")
    
    if [[ "$RESOURCE_COUNT" -eq 0 ]]; then
        print_info "No resources in Terraform state"
        return
    fi
    
    print_info "Found $RESOURCE_COUNT resources to destroy"
    
    if confirm_action "Destroy $RESOURCE_COUNT AWS resources?" "y"; then
        print_info "Running terraform destroy..."
        
        # Set timeout to prevent hanging
        if timeout 600 terraform destroy -auto-approve; then
            print_success "Terraform destroy completed successfully"
        else
            print_error "Terraform destroy failed or timed out after 10 minutes"
            print_info "You may need to manually clean up AWS resources"
            print_info "Check AWS Console for remaining resources"
            return 1
        fi
    else
        print_warning "Terraform destroy cancelled"
        return 1
    fi
}

cleanup_local_files() {
    print_header "Cleaning Up Local Files"
    
    local files_to_remove=(
        "${CA4_ROOT}/.manager-ip"
        "${CA4_ROOT}/.worker-token"
        "${CA4_ROOT}/terraform-outputs.json"
        "${VPN_CONFIG}/keys"
        "${VPN_CONFIG}/generated"
        "${VPN_CONFIG}/cloud-wg0.conf"
        "${VPN_CONFIG}/edge-wg0.conf"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            print_info "Removing: $file"
            rm -rf "$file" || print_warning "Failed to remove $file"
        fi
    done
    
    # Remove generated edge VPN config if it exists
    if [[ -f "/etc/wireguard/wg0.conf" ]]; then
        if confirm_action "Remove /etc/wireguard/wg0.conf?" "y"; then
            sudo rm -f /etc/wireguard/wg0.conf
            print_success "Removed VPN configuration"
        fi
    fi
    
    print_success "Local files cleaned up"
}

show_summary() {
    print_banner "TEARDOWN SUMMARY"
    
    echo -e "${CYAN}The following has been destroyed:${NC}"
    echo -e "  ${GREEN}✓${NC} Edge sensors stopped and removed"
    echo -e "  ${GREEN}✓${NC} Edge VPN tunnel terminated"
    echo -e "  ${GREEN}✓${NC} Cloud Docker stack removed"
    echo -e "  ${GREEN}✓${NC} Cloud VPN stopped"
    echo -e "  ${GREEN}✓${NC} AWS infrastructure destroyed"
    echo -e "  ${GREEN}✓${NC} Generated files cleaned up"
    echo ""
    echo -e "${YELLOW}⚠ Please verify in AWS Console that all resources are deleted:${NC}"
    echo -e "  - EC2 Instances"
    echo -e "  - VPC and Subnets"
    echo -e "  - Security Groups"
    echo -e "  - Internet Gateway"
    echo -e "  - SSH Key Pairs"
    echo ""
    echo -e "${CYAN}To redeploy, run:${NC}"
    echo -e "  cd ${SCRIPT_DIR}"
    echo -e "  ./deploy-all.sh all"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    print_banner "CA4 EDGE-TO-CLOUD TEARDOWN"
    
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  WARNING: This will destroy all CA4 infrastructure!           ║${NC}"
    echo -e "${RED}║                                                                ║${NC}"
    echo -e "${RED}║  This includes:                                               ║${NC}"
    echo -e "${RED}║  • Edge sensors and VPN                                       ║${NC}"
    echo -e "${RED}║  • Cloud Docker Swarm services                                ║${NC}"
    echo -e "${RED}║  • All AWS EC2 instances and networking                       ║${NC}"
    echo -e "${RED}║  • Generated configuration files                              ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if ! confirm_action "Do you want to proceed with teardown?" "n"; then
        print_info "Teardown cancelled"
        exit 0
    fi
    
    # Execute teardown steps
    stop_edge_sensors
    stop_edge_vpn
    remove_cloud_stack
    stop_cloud_vpn
    destroy_terraform
    cleanup_local_files
    
    show_summary
}

# Run main function
main "$@"
