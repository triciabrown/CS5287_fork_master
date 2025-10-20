#!/bin/bash
# teardown.sh
# Complete teardown: Remove applications AND destroy AWS infrastructure
# Idempotent cleanup script
#
# Usage:
#   ./teardown.sh                  # AWS teardown (DEFAULT)
#   MODE=local ./teardown.sh       # Local teardown only

set -e

STACK_NAME="${1:-plant-monitoring}"
MODE="${MODE:-aws}"  # DEFAULT: aws (use MODE=local for development cleanup)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║     Plant Monitoring - Complete Teardown                 ║${NC}"
echo -e "${RED}║     WARNING: This will destroy all resources!            ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Mode: ${MODE} $([ "${MODE}" = "aws" ] && echo "(DEFAULT)" || echo "(override)")"
echo "Stack: ${STACK_NAME}"
echo ""

# Confirm removal
echo -e "${YELLOW}This will:${NC}"
if [ "${MODE}" = "aws" ]; then
    echo "  1. Remove Docker Swarm stack (all applications)"
    echo "  2. Destroy AWS infrastructure (EC2 instances, VPC, etc.)"
    echo "  3. Delete ALL data (databases, volumes, configs)"
else
    echo "  1. Remove Docker Swarm stack (all applications)"
    echo "  2. Remove Docker secrets, configs, volumes"
    echo "  3. Delete ALL application data"
fi
echo ""
read -p "Are you sure you want to proceed? (yes/NO): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Teardown cancelled"
    exit 0
fi

# ============================================================================
# AWS MODE: Destroy everything via Terraform
# ============================================================================

if [ "${MODE}" = "aws" ]; then
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Phase 1: Removing Application Stack${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Check if we have terraform state
    if [ -f "${SCRIPT_DIR}/terraform/terraform.tfstate" ]; then
        MANAGER_IP=$(cd "${SCRIPT_DIR}/terraform" && terraform output -raw manager_public_ip 2>/dev/null || echo "")
        
        if [ -n "$MANAGER_IP" ]; then
            echo -e "${YELLOW}→ Removing stack from AWS manager node...${NC}"
            
            # Try to remove stack via SSH
            ssh -i ~/.ssh/docker-swarm-key -o StrictHostKeyChecking=no ubuntu@${MANAGER_IP} \
                "docker stack rm ${STACK_NAME}" 2>/dev/null || true
            
            echo -e "${GREEN}✓ Stack removal initiated${NC}"
            echo "Waiting for services to stop..."
            sleep 15
        else
            echo -e "${YELLOW}⚠ Could not determine manager IP${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ No Terraform state found${NC}"
    fi
    echo ""
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Phase 2: Force Clean Docker Resources (prevents ENI issues)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ -n "$MANAGER_IP" ]; then
        echo -e "${YELLOW}→ Removing stack volumes on manager...${NC}"
        ssh -i ~/.ssh/docker-swarm-key -o StrictHostKeyChecking=no ubuntu@${MANAGER_IP} \
            "docker volume ls -q | grep '${STACK_NAME}' | xargs -r docker volume rm" 2>/dev/null || true
        echo -e "${GREEN}✓ Stack volumes removed${NC}"
        
        echo -e "${YELLOW}→ Cleaning Docker networks and unused volumes on manager...${NC}"
        ssh -i ~/.ssh/docker-swarm-key -o StrictHostKeyChecking=no ubuntu@${MANAGER_IP} \
            "docker network prune -f && docker volume prune -f" 2>/dev/null || true
        echo -e "${GREEN}✓ Docker cleanup complete${NC}"
        
        echo -e "${YELLOW}→ Cleaning Docker resources on workers...${NC}"
        # Get worker IPs from terraform
        WORKER_IPS=$(cd "${SCRIPT_DIR}/terraform" && terraform output -json worker_private_ips 2>/dev/null | grep -o '"[0-9.]*"' | tr -d '"' || echo "")
        if [ -n "$WORKER_IPS" ]; then
            for WORKER_IP in $WORKER_IPS; do
                echo "  Cleaning worker $WORKER_IP..."
                ssh -i ~/.ssh/docker-swarm-key -o StrictHostKeyChecking=no -o ProxyJump=ubuntu@${MANAGER_IP} ubuntu@${WORKER_IP} \
                    "docker volume ls -q | xargs -r docker volume rm 2>/dev/null || true; docker volume prune -f" 2>/dev/null || true
            done
            echo -e "${GREEN}✓ Worker cleanup complete${NC}"
        fi
        
        echo "Waiting 15 seconds for AWS ENI cleanup..."
        sleep 15
    fi
    echo ""
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Phase 3: Destroying AWS Infrastructure${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ! -f "${SCRIPT_DIR}/terraform/terraform.tfstate" ]; then
        echo -e "${YELLOW}⚠ No Terraform state found - nothing to destroy${NC}"
    else
        echo -e "${YELLOW}→ Destroying AWS resources with Terraform...${NC}"
        cd "${SCRIPT_DIR}/terraform"
        
        # First attempt - give it 5 minutes
        echo "Attempting Terraform destroy (timeout: 5 minutes)..."
        timeout 300 terraform destroy -auto-approve 2>&1 | tee destroy.log || DESTROY_FAILED=$?
        
        if [ "${DESTROY_FAILED}" = "124" ]; then
            echo -e "${RED}✗ Terraform destroy timed out after 5 minutes${NC}"
            echo -e "${YELLOW}→ This is usually due to lingering ENIs from Docker overlay networks${NC}"
            echo ""
            
            # Get VPC ID from state
            VPC_ID=$(terraform state show aws_vpc.swarm_vpc 2>/dev/null | grep "^    id " | awk '{print $3}' | tr -d '"')
            
            if [ -n "$VPC_ID" ]; then
                echo "VPC ID: $VPC_ID"
                echo -e "${YELLOW}→ Checking for stuck EC2 instances...${NC}"
                
                # Find any instances still running in the VPC
                STUCK_INSTANCES=$(aws ec2 describe-instances \
                    --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
                    --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null)
                
                if [ -n "$STUCK_INSTANCES" ]; then
                    echo -e "${YELLOW}Found stuck instances: $STUCK_INSTANCES${NC}"
                    echo -e "${YELLOW}→ Terminating stuck instances...${NC}"
                    aws ec2 terminate-instances --instance-ids $STUCK_INSTANCES >/dev/null 2>&1 || true
                    echo "Waiting 60 seconds for instances to terminate..."
                    sleep 60
                else
                    echo -e "${GREEN}✓ No stuck instances found${NC}"
                    echo "Waiting 30 seconds for ENI cleanup..."
                    sleep 30
                fi
                
                # Retry destroy
                echo -e "${YELLOW}→ Retrying Terraform destroy...${NC}"
                terraform destroy -auto-approve
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}✗ Retry failed. Attempting one more time after delay...${NC}"
                    sleep 30
                    terraform destroy -auto-approve || {
                        echo -e "${RED}✗ Final retry failed${NC}"
                        echo "Remaining resources:"
                        terraform state list
                        exit 1
                    }
                fi
            else
                echo -e "${RED}✗ Could not determine VPC ID from Terraform state${NC}"
                echo "Attempting destroy anyway..."
                terraform destroy -auto-approve || {
                    echo -e "${RED}✗ Manual cleanup may be required${NC}"
                    terraform state list
                    exit 1
                }
            fi
        elif [ -n "${DESTROY_FAILED}" ] && [ "${DESTROY_FAILED}" != "0" ]; then
            echo -e "${RED}✗ Terraform destroy failed with error code: ${DESTROY_FAILED}${NC}"
            echo "See destroy.log for details"
            echo "Attempting one retry..."
            sleep 20
            terraform destroy -auto-approve || {
                echo -e "${RED}✗ Retry failed. Remaining resources:${NC}"
                terraform state list
                exit 1
            }
        fi
        
        echo -e "${GREEN}✓ AWS infrastructure destroyed${NC}"
    fi
    echo ""
    
    # Clean up local files
    echo -e "${YELLOW}→ Cleaning up local configuration files...${NC}"
    rm -f "${SCRIPT_DIR}/ansible/inventory.ini"
    echo -e "${GREEN}✓ Local files cleaned${NC}"
    echo ""
    
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     AWS Teardown Complete! ✓                              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "All AWS resources have been destroyed."
    echo ""
    exit 0
fi

# ============================================================================
# LOCAL MODE: Remove stack and clean up Docker resources
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Local Docker Swarm Teardown${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}Step 1: Removing stack${NC}"
echo "------------------------------"
if docker stack ls | grep -q "${STACK_NAME}"; then
    docker stack rm ${STACK_NAME}
    echo -e "${GREEN}✓ Stack removal initiated${NC}"
    
    echo "Waiting for services to stop..."
    sleep 20
    
    # Wait for all services to be removed
    while docker stack ps ${STACK_NAME} 2>/dev/null | grep -q .; do
        echo "Waiting for services to stop..."
        sleep 5
    done
    
    echo -e "${GREEN}✓ All services stopped${NC}"
else
    echo -e "${YELLOW}⚠ Stack '${STACK_NAME}' not found${NC}"
fi
echo ""

echo -e "${BLUE}Step 2: Removing configs${NC}"
echo "------------------------------"
docker config rm mosquitto_config 2>/dev/null && echo -e "${GREEN}✓ Removed mosquitto_config${NC}" || echo -e "${YELLOW}⚠ mosquitto_config not found${NC}"
docker config rm sensor_config 2>/dev/null && echo -e "${GREEN}✓ Removed sensor_config${NC}" || echo -e "${YELLOW}⚠ sensor_config not found${NC}"
echo ""

echo -e "${BLUE}Step 3: Removing secrets${NC}"
echo "------------------------------"
docker secret rm mongo_root_username 2>/dev/null && echo -e "${GREEN}✓ Removed mongo_root_username${NC}" || true
docker secret rm mongo_root_password 2>/dev/null && echo -e "${GREEN}✓ Removed mongo_root_password${NC}" || true
docker secret rm mongo_app_username 2>/dev/null && echo -e "${GREEN}✓ Removed mongo_app_username${NC}" || true
docker secret rm mongo_app_password 2>/dev/null && echo -e "${GREEN}✓ Removed mongo_app_password${NC}" || true
docker secret rm mongodb_connection_string 2>/dev/null && echo -e "${GREEN}✓ Removed mongodb_connection_string${NC}" || true
docker secret rm mqtt_username 2>/dev/null && echo -e "${GREEN}✓ Removed mqtt_username${NC}" || true
docker secret rm mqtt_password 2>/dev/null && echo -e "${GREEN}✓ Removed mqtt_password${NC}" || true
echo -e "${GREEN}✓ Secrets removed${NC}"
echo ""

echo -e "${BLUE}Step 4: Removing networks${NC}"
echo "------------------------------"
NETWORK_NAME="${STACK_NAME}_plant-network"
# Wait a bit for network to be released
sleep 5
if docker network ls | grep -q "${NETWORK_NAME}"; then
    docker network rm ${NETWORK_NAME} 2>/dev/null && echo -e "${GREEN}✓ Removed ${NETWORK_NAME}${NC}" || echo -e "${YELLOW}⚠ Network still in use (will be removed automatically)${NC}"
else
    echo -e "${YELLOW}⚠ Network not found${NC}"
fi
echo ""

echo -e "${BLUE}Step 5: Removing volumes${NC}"
echo "------------------------------"
echo -e "${RED}⚠ This will DELETE all persistent data (databases, etc.)${NC}"
read -p "Remove ALL volumes? (yes/NO): " -r
echo
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}→ Removing volumes...${NC}"
    
    # List and remove volumes
    VOLUMES=$(docker volume ls -q | grep -E "(${STACK_NAME}|kafka|zookeeper|mongodb|mosquitto|homeassistant)" || true)
    
    if [ -n "$VOLUMES" ]; then
        echo "$VOLUMES" | xargs -r docker volume rm 2>/dev/null || true
        echo -e "${GREEN}✓ Volumes removed${NC}"
    else
        echo -e "${YELLOW}⚠ No volumes found${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Volumes preserved${NC}"
    echo ""
    echo "Existing volumes:"
    docker volume ls | grep -E "(${STACK_NAME}|kafka|zookeeper|mongodb|mosquitto|homeassistant)" || echo "  (none)"
    echo ""
    echo "To manually remove volumes later:"
    echo "  docker volume ls"
    echo "  docker volume rm <volume-name>"
fi
echo ""

echo -e "${BLUE}Step 6: Cleanup (optional)${NC}"
echo "------------------------------"
read -p "Leave Docker Swarm? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker swarm leave --force 2>/dev/null && echo -e "${GREEN}✓ Left swarm${NC}" || echo -e "${YELLOW}⚠ Not in swarm mode${NC}"
else
    echo -e "${YELLOW}⚠ Still in swarm mode${NC}"
fi
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Teardown Complete! ✓                                  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Remaining resources:"
echo ""
echo -e "${BLUE}Docker Secrets:${NC}"
docker secret ls || echo "  (none)"
echo ""
echo -e "${BLUE}Docker Volumes:${NC}"
docker volume ls | grep -E "(${STACK_NAME}|kafka|zookeeper|mongodb|mosquitto|homeassistant)" || echo "  (none)"
echo ""
echo -e "${BLUE}Docker Swarm:${NC}"
docker info 2>/dev/null | grep "Swarm:" || echo "  Not in swarm mode"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  Stack '${STACK_NAME}' has been removed"
echo "  All secrets and configs have been deleted"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  Docker Swarm has been deactivated"
fi
echo ""
