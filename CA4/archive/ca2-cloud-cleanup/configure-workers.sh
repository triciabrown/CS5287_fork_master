#!/bin/bash
# Worker Join Configuration Guide
# How to enable multi-node Swarm cluster with workers in private subnet

set -e

echo "╔════════════════════════════════════════════════════════╗"
echo "║  Worker Node Join Configuration                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# CURRENT ISSUE
# =============================================================================
# Workers are in private subnet (10.0.2.0/24) with no public IPs
# Ansible inventory uses SSH ProxyJump through manager:
#   laptop → manager (bastion) → worker1 (private)
# 
# ProxyJump requires EITHER:
#   1. SSH agent forwarding (ForwardAgent=yes)
#   2. SSH key copied to manager
#
# Currently: Neither configured, so workers fail to join
# =============================================================================

# =============================================================================
# SOLUTION OPTIONS
# =============================================================================

echo "Three approaches to enable worker joining:"
echo ""
echo "Option A: SSH Agent Forwarding (RECOMMENDED - Most Secure)"
echo "  ✓ Keeps private key on laptop only"
echo "  ✓ Uses SSH agent to authenticate through bastion"
echo "  ✓ Industry best practice"
echo ""
echo "Option B: Copy Key to Manager (Works but less secure)"
echo "  ⚠ Private key stored on manager node"
echo "  ✓ Simple configuration"
echo ""
echo "Option C: Single-Node Deployment (CURRENT - Valid for assignment)"
echo "  ✓ All services run on manager"
echo "  ✓ Simplest approach"
echo "  ✓ Meets assignment requirements"
echo ""

read -p "Choose option (A/B/C): " OPTION

case $OPTION in
  A|a)
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "Implementing Option A: SSH Agent Forwarding"
    echo "════════════════════════════════════════════════════════"
    echo ""
    
    echo "Step 1: Add SSH key to agent"
    eval $(ssh-agent -s)
    ssh-add ~/.ssh/docker-swarm-key
    
    echo ""
    echo "Step 2: Test agent forwarding"
    MANAGER_IP=$(cd terraform && terraform output -raw manager_public_ip)
    ssh -A -o StrictHostKeyChecking=no ubuntu@${MANAGER_IP} 'ssh-add -l'
    
    echo ""
    echo "Step 3: Run Ansible with agent forwarding"
    ansible-playbook -i ansible/inventory.ini \
      ansible/setup-swarm.yml \
      --ssh-common-args='-o ForwardAgent=yes -o StrictHostKeyChecking=no'
    
    echo ""
    echo "✓ Workers should now join successfully!"
    echo ""
    echo "Verify with:"
    echo "  ssh ubuntu@${MANAGER_IP} 'docker node ls'"
    ;;
    
  B|b)
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "Implementing Option B: Copy SSH Key to Manager"
    echo "════════════════════════════════════════════════════════"
    echo ""
    
    MANAGER_IP=$(cd terraform && terraform output -raw manager_public_ip)
    
    echo "Step 1: Copy SSH key to manager"
    scp -i ~/.ssh/docker-swarm-key \
      ~/.ssh/docker-swarm-key \
      ubuntu@${MANAGER_IP}:~/.ssh/
    
    echo ""
    echo "Step 2: Set correct permissions"
    ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP} \
      'chmod 600 ~/.ssh/docker-swarm-key'
    
    echo ""
    echo "Step 3: Run Ansible (ProxyJump will now work)"
    ansible-playbook -i ansible/inventory.ini \
      ansible/setup-swarm.yml \
      --ssh-common-args='-o StrictHostKeyChecking=no'
    
    echo ""
    echo "✓ Workers should now join successfully!"
    echo ""
    echo "⚠ Security Note: Private key is now on manager node"
    echo "  Consider rotating key after setup"
    ;;
    
  C|c)
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "Using Option C: Single-Node Deployment"
    echo "════════════════════════════════════════════════════════"
    echo ""
    
    echo "Current configuration already supports this!"
    echo ""
    echo "All services will run on the manager node:"
    echo "  • Docker Swarm supports running all services on one node"
    echo "  • No changes needed to docker-compose.yml"
    echo "  • Meets assignment requirements (3+ nodes created, 1 active)"
    echo ""
    echo "Service distribution:"
    echo "  • Zookeeper: Manager"
    echo "  • Kafka: Manager"
    echo "  • MongoDB: Manager"  
    echo "  • MQTT: Manager (labeled node)"
    echo "  • Home Assistant: Manager (labeled node)"
    echo "  • Processor: Manager"
    echo "  • Sensors: Manager (2 replicas)"
    echo ""
    echo "✓ This is a valid configuration for the assignment!"
    echo ""
    echo "To verify services:"
    MANAGER_IP=$(cd terraform && terraform output -raw manager_public_ip)
    echo "  ssh ubuntu@${MANAGER_IP} 'docker service ls'"
    ;;
    
  *)
    echo "Invalid option. Exiting."
    exit 1
    ;;
esac

echo ""
echo "════════════════════════════════════════════════════════"
echo "Configuration complete!"
echo "════════════════════════════════════════════════════════"
