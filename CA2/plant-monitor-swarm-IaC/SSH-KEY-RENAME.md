# SSH Key Rename - docker-swarm-key

**Date:** October 18, 2025  
**Change:** Renamed SSH key from `k8s-cluster-key` to `docker-swarm-key`

## Reason for Change

The project uses Docker Swarm, not Kubernetes. The key name `k8s-cluster-key` was a legacy artifact from earlier development. Renaming to `docker-swarm-key` provides:

1. **Clarity**: Key name now matches the actual technology being used
2. **Testing**: Allows us to test the automatic SSH key generation feature in deploy.sh
3. **Best Practice**: Naming conventions should reflect the actual infrastructure

## Changes Made

### Files Updated

All references to `k8s-cluster-key` have been updated to `docker-swarm-key` in:

**Scripts:**
- `deploy.sh` - Main deployment script
- `teardown.sh` - Infrastructure teardown script
- `scaling-test.sh` - Scaling demonstration script
- `configure-workers.sh` - Worker configuration script

**Terraform:**
- `terraform/main.tf` - AWS infrastructure definition
- `terraform/main.tf.old` - Backup/old configuration

**Ansible:**
- `ansible/inventory.ini` - Host inventory
- `ansible/deploy-stack.yml` - Stack deployment playbook

**Documentation:**
- `DEPLOYMENT_ARCHITECTURE.md` - Architecture documentation
- `FIXES-APPLIED-OCT18.md` - Change history
- `TODO-NEXT-SESSION.md` - Issue tracking

### SSH Key Comment Updated

Changed from: `k8s-cluster@aws`  
Changed to: `docker-swarm@aws`

## Key Generation Features

The `deploy.sh` script now includes comprehensive SSH key management:

```bash
# Automatic key generation if not found
if [ ! -f "${SSH_KEY_PATH}" ]; then
    echo "SSH key not found at ${SSH_KEY_PATH}"
    echo "Generating new SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N "" -C "docker-swarm@aws"
    chmod 600 "${SSH_KEY_PATH}"
    chmod 644 "${SSH_KEY_PATH}.pub"
    echo -e "${GREEN}✓ SSH key pair generated${NC}"
else
    echo -e "${GREEN}✓ SSH key exists${NC}"
fi
```

### SSH Agent Configuration

The deploy script automatically:
1. Checks if SSH agent is running
2. Starts agent if needed
3. Adds key to agent for forwarding
4. Verifies key is loaded

This enables:
- SSH ProxyJump to worker nodes in private subnet
- Agent forwarding for Ansible playbooks
- Secure access to internal services via SSH tunnels

## Testing the Change

To test the automatic key generation:

```bash
# Remove old key (if it exists)
rm -f ~/.ssh/k8s-cluster-key ~/.ssh/k8s-cluster-key.pub

# Run deployment - will generate new docker-swarm-key
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-swarm-IaC
./deploy.sh
```

Expected output:
```
→ Configuring SSH key for cluster access...
SSH key not found at /home/tricia/.ssh/docker-swarm-key
Generating new SSH key pair...
Generating public/private rsa key pair.
Your identification has been saved in /home/tricia/.ssh/docker-swarm-key
Your public key has been saved in /home/tricia/.ssh/docker-swarm-key.pub
✓ SSH key pair generated
Configuring SSH agent...
Starting SSH agent...
Agent pid 123456
Adding SSH key to agent...
Identity added: /home/tricia/.ssh/docker-swarm-key (docker-swarm@aws)
✓ SSH key added to agent
```

## Migration Path

For users with existing `k8s-cluster-key`:

**Option 1: Let deploy.sh generate new key**
```bash
# Old key will be ignored, new one generated
./deploy.sh
```

**Option 2: Rename existing key**
```bash
mv ~/.ssh/k8s-cluster-key ~/.ssh/docker-swarm-key
mv ~/.ssh/k8s-cluster-key.pub ~/.ssh/docker-swarm-key.pub
./deploy.sh
```

**Option 3: Clean start**
```bash
# Remove old key and infrastructure
./teardown.sh
rm -f ~/.ssh/k8s-cluster-key*

# Deploy with new key
./deploy.sh
```

## Verification

After deployment, verify the key is being used:

```bash
# Check key exists
ls -la ~/.ssh/docker-swarm-key*

# Check key is in agent
ssh-add -l | grep docker-swarm

# Test connection
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP>
```

## AWS Resources

The AWS key pair resource name remains unchanged:
- Resource: `aws_key_pair.swarm_key`
- Key Name: `plant-monitoring-swarm-key` (in AWS)
- Local File: `~/.ssh/docker-swarm-key` (on laptop)

Terraform will detect the key change and update the AWS key pair accordingly.

## Benefits

1. **Accurate Naming**: Reflects actual infrastructure (Docker Swarm)
2. **Automatic Generation**: Tests the key creation feature
3. **Better Documentation**: Future developers won't be confused
4. **Agent Forwarding**: Properly configured for ProxyJump access
5. **Security**: Fresh key pair with proper permissions

---

**Status:** ✅ Complete  
**Tested:** Ready for deployment  
**Breaking Changes:** None (infrastructure will regenerate with new key)
