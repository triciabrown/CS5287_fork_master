# CA4 Teardown Guide

## Quick Teardown

To destroy the entire CA4 edge-to-cloud infrastructure:

```bash
cd CA4/scripts
./teardown.sh
```

**Or use the force mode** (skip confirmations):
```bash
./teardown.sh --force
```

---

## What Gets Destroyed

The teardown script will remove **all** CA4 infrastructure in this order:

### 1. ✅ Edge Components (Local)
- **Edge sensors**: 3 Docker containers stopped and removed
- **Edge VPN**: WireGuard `wg0` interface brought down
- **Local config**: `/etc/wireguard/wg0.conf` removed

### 2. ✅ Cloud Services (AWS)
- **Docker Stack**: `plant-monitoring` stack removed from Swarm
  - Home Assistant
  - Kafka & Zookeeper
  - MongoDB
  - Mosquitto
  - Processor
- **Cloud VPN**: WireGuard stopped on manager node

### 3. ✅ AWS Infrastructure (Terraform)
- **EC2 Instances**: Manager (1) + Workers (4) terminated
- **VPC & Networking**: VPC, subnets, internet gateway, route tables deleted
- **Security Groups**: All custom security groups removed
- **SSH Key Pair**: `plant-mon-swarm` key deleted

### 4. ✅ Local Files
- `.manager-ip` - Manager IP address
- `.worker-token` - Swarm join token
- `terraform-outputs.json` - Terraform outputs
- `vpn-config/keys/` - Generated VPN keys
- `vpn-config/generated/` - Generated VPN configs

---

## Teardown Process Details

```
╔════════════════════════════════════════════════════════════════╗
║                     TEARDOWN SEQUENCE                          ║
╚════════════════════════════════════════════════════════════════╝

1. Stop Edge Sensors
   └─> docker compose down -v (removes containers & volumes)

2. Stop Edge VPN
   └─> sudo wg-quick down wg0 (terminates VPN tunnel)

3. Remove Cloud Stack
   └─> SSH to manager: docker stack rm plant-monitoring
   └─> Wait 30s for graceful shutdown

4. Stop Cloud VPN
   └─> SSH to manager: sudo wg-quick down wg0

5. Destroy Terraform Infrastructure
   └─> terraform destroy -auto-approve (10 min timeout)
   └─> Destroys ~18 AWS resources

6. Cleanup Local Files
   └─> Remove generated configs and state files
```

---

## Safety Features

✅ **Confirmation Prompts**: Asks before destroying resources  
✅ **Force Mode Available**: `--force` flag for automation  
✅ **Timeout Protection**: Terraform destroy times out after 10 minutes  
✅ **Graceful Shutdown**: Docker stack waits 30s for services to stop  
✅ **Error Handling**: Continues even if some steps fail  

---

## Verification After Teardown

### Check Local System
```bash
# Verify edge sensors stopped
docker ps | grep plant-sensor  # Should be empty

# Verify VPN down
sudo wg show  # Should show no interfaces

# Verify files removed
ls -la CA4/.manager-ip  # Should not exist
```

### Check AWS Console
1. **EC2 → Instances**: Should show 0 instances with tag `plant-monitoring`
2. **VPC → Your VPCs**: Should not have VPC named `plant-monitoring-vpc`
3. **EC2 → Security Groups**: No `plant-mon-*` groups
4. **EC2 → Key Pairs**: No `plant-mon-swarm` key

---

## Troubleshooting

### Terraform Destroy Hangs

If `terraform destroy` hangs or times out:

```bash
# 1. Force kill the process
Ctrl+C

# 2. Manually clean up AWS resources via Console
# - Terminate all EC2 instances
# - Delete security groups (must delete instances first)
# - Delete VPC

# 3. Clean up Terraform state
cd CA4/cloud-site/terraform
rm -f terraform.tfstate*
terraform init
```

### Stack Won't Remove

If Docker stack won't remove:

```bash
# SSH to manager
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP>

# Force remove services one by one
docker service rm $(docker service ls -q)

# Leave swarm to clean up
docker swarm leave --force
```

### Edge Sensors Won't Stop

```bash
# Force remove containers
cd CA4/edge-site
docker compose down -v --remove-orphans

# If that fails, force remove
docker rm -f $(docker ps -aq --filter name=plant-sensor)
```

### VPN Won't Stop

```bash
# Force down the interface
sudo ip link del wg0

# Remove config
sudo rm -f /etc/wireguard/wg0.conf
```

---

## Partial Teardown

You can also destroy components individually using `deploy-all.sh`:

```bash
# Just cleanup (no Terraform destroy)
cd CA4/scripts
./deploy-all.sh cleanup

# Or destroy manually in reverse order:

# 1. Stop edge components
cd CA4/edge-site && docker compose down -v
sudo wg-quick down wg0

# 2. Remove cloud stack
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP> "docker stack rm plant-monitoring"

# 3. Destroy infrastructure
cd CA4/cloud-site/terraform
terraform destroy -auto-approve
```

---

## Cost Savings

After teardown, you avoid AWS charges for:
- ✅ 5 EC2 instances (t3.medium)
- ✅ EBS volumes
- ✅ Data transfer
- ✅ Elastic IPs (if any)

**Estimated savings**: ~$0.50-1.00/hour (depending on region)

---

## Redeployment

To redeploy after teardown:

```bash
cd CA4/scripts
./deploy-all.sh all
```

This will:
1. Create new AWS infrastructure
2. Initialize Docker Swarm
3. Deploy cloud services
4. Generate new VPN keys
5. Configure VPN tunnel
6. Deploy edge sensors

**Time**: ~15-20 minutes for full deployment

---

## Quick Reference

| Task | Command |
|------|---------|
| **Full teardown** | `./teardown.sh` |
| **Force teardown** | `./teardown.sh --force` |
| **Check AWS resources** | AWS Console → EC2, VPC |
| **Check local state** | `ls CA4/.manager-ip` |
| **Redeploy** | `./deploy-all.sh all` |

---

## Emergency Teardown

If automation fails, manual AWS cleanup:

1. **EC2 Console** → Select all `plant-monitoring` instances → Terminate
2. Wait 5 minutes for instances to terminate
3. **VPC Console** → Select `plant-monitoring-vpc` → Actions → Delete VPC
4. **EC2 → Security Groups** → Delete any remaining `plant-mon-*` groups
5. **EC2 → Key Pairs** → Delete `plant-mon-swarm`

**Time**: ~10 minutes

---

## Notes

- ⚠️ Teardown is **irreversible** - all data in MongoDB will be lost
- ⚠️ VPN keys will be deleted - new keys generated on redeploy
- ⚠️ Terraform state is preserved unless manually deleted
- ✅ Source code and configuration templates are preserved
- ✅ Docker images remain cached locally (sensors, processor)

---

**Last Updated**: November 23, 2025  
**Script Version**: 1.0.0  
**Terraform Version**: ~> 5.0
