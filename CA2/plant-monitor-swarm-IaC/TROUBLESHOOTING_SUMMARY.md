# Troubleshooting Summary: October 18, 2025

## Issue Timeline

### Initial Symptom
Services on worker nodes couldn't connect to Kafka, showing:
- `Connection timeout` errors
- `getaddrinfo ENOTFOUND kafka` DNS errors
- Processor service crashing (0/1 replicas)
- Sensor replicas on workers failing

### Troubleshooting Journey

#### Phase 1: DNS Investigation (WRONG ASSUMPTION)
**Hypothesis**: Docker Swarm VIP mode causes DNS failures  
**Action**: Added `endpoint_mode: dnsrr` to Kafka service  
**Result**: DNS started resolving, but **connections still timed out!**  
**Conclusion**: DNS wasn't the root cause

#### Phase 2: Endpoint Mode Testing (STILL WRONG)
**Hypothesis**: Need to use DNSRR instead of VIP for stateful services  
**Action**: Tried both VIP and DNSRR modes  
**Result**: Both modes had same timeout issue on workers  
**Conclusion**: Something deeper was wrong

#### Phase 3: Location Pattern Analysis (BREAKTHROUGH)
**Observation**: 
- ✅ Services on manager (10.0.1.52) worked fine
- ❌ Services on workers (10.0.2.x) all timed out

**Investigation**:
```bash
# Checked overlay network configuration
docker network inspect plant-monitoring_plant-network
# Result: Overlay using 10.0.1.0/24

# Checked AWS subnet configuration
terraform output
# Result: AWS public subnet ALSO 10.0.1.0/24!
```

**ROOT CAUSE FOUND**: IP address overlap between Docker overlay network and AWS physical network!

---

## Root Cause: Overlay Network IP Conflict

### The Problem

```
AWS Infrastructure:
├── VPC: 10.0.0.0/16
├── Public Subnet (Manager): 10.0.1.0/24  ← Manager node lives here
└── Private Subnet (Workers): 10.0.2.0/24  ← Worker nodes live here

Docker Overlay Network:
└── plant-network: 10.0.1.0/24  ← CONFLICT with AWS public subnet!
```

### Why This Broke Everything

When a container on a worker node (10.0.2.x) tried to reach Kafka VIP (10.0.1.68):

1. **DNS Resolution**: ✅ Worked fine
   - `kafka` resolved to `10.0.1.68` (overlay VIP)

2. **Routing Decision**: ❌ AMBIGUOUS
   - Container saw: "Destination is 10.0.1.68"
   - Routing table had TWO 10.0.1.0/24 routes:
     * One for overlay network (VXLAN tunnel)
     * One for AWS network (physical eth0)
   - **Couldn't determine which path to use!**

3. **Result**: Connection timeout
   - Packets sent to wrong interface
   - Never reached Kafka container
   - Timeout (not DNS error!)

### Why Manager Node Worked

Services on the manager node (10.0.1.52) didn't have routing ambiguity:
- Both AWS network and overlay network physically on same host
- No cross-node routing required
- Local bridge handled communication

**This masked the problem and made us think it was worker-specific!**

---

## The Solution

### Fix: Specify Non-Conflicting Overlay Subnet

**Before** (auto-assigned, conflicting):
```yaml
networks:
  plant-network:
    driver: overlay
    driver_opts:
      encrypted: "true"
    # No subnet specified - Docker chose 10.0.1.0/24 (conflict!)
```

**After** (explicit, non-conflicting):
```yaml
networks:
  plant-network:
    driver: overlay
    driver_opts:
      encrypted: "true"
    ipam:
      driver: default
      config:
        - subnet: 10.10.0.0/24  # Different from AWS 10.0.x.x ranges
```

### Result

- Overlay network: 10.10.0.0/24
- AWS public subnet: 10.0.1.0/24
- AWS private subnet: 10.0.2.0/24
- **No overlap = Clear routing decisions**

---

## Lessons Learned

### 1. Connection Timeouts ≠ Always DNS

We spent hours debugging DNS when routing was the real problem.

**Symptom**: Connection timeout  
**Assumption**: DNS not resolving  
**Reality**: DNS worked, routing failed

### 2. Layer Your Debugging

Always check from bottom to top:
1. **Physical layer**: Are nodes connected?
2. **Network layer**: Can packets route? ← Our issue was here
3. **Transport layer**: Are ports open?
4. **Application layer**: Can service connect?

### 3. Working Components Can Mislead

"It works on the manager" suggested a worker configuration issue.  
**Reality**: Manager had no routing conflict, hiding the architecture problem.

### 4. Always Specify Overlay Subnets

**Never** rely on Docker's auto-assigned overlay network IPs in production.

**Always** explicitly configure subnets that don't conflict with your infrastructure:
- Check your cloud provider's network ranges
- Choose overlay subnets from different IP ranges
- Document your IP allocation strategy

### 5. AWS/Cloud Network Planning

When deploying to AWS/Azure/GCP:
1. Document all VPC/VNet CIDR blocks
2. Document all subnet CIDRs
3. Choose overlay networks from different ranges
4. Keep an IP allocation table in your README

---

## IP Allocation Strategy

### Our Final Configuration

| Network Type | CIDR | Purpose |
|--------------|------|---------|
| **AWS VPC** | 10.0.0.0/16 | Physical cloud network |
| AWS Public Subnet | 10.0.1.0/24 | Manager node |
| AWS Private Subnet | 10.0.2.0/24 | Worker nodes |
| **Docker Overlay** | **10.10.0.0/24** | **Container network** |

**Key**: Different IP ranges = No routing conflicts

### Alternative Ranges

If 10.10.x.x conflicts with your infrastructure:
- `172.20.0.0/16` - Private range
- `192.168.100.0/24` - Private range
- `10.20.0.0/16` - Different class A range

---

## Secondary Issue: DNS/Endpoint Mode

After fixing the overlay network, we found that **VIP mode works fine!**

The `endpoint_mode: dnsrr` workaround we tried **was not needed** once routing was fixed.

However, `dnsrr` mode can still be beneficial for:
- Stateful services with persistent connections
- Services that need to know exact container IPs
- Debugging networking issues

**Both modes work correctly with proper overlay network configuration.**

---

## Verification Checklist

After redeployment with the fix:

- [ ] Check overlay network subnet:
  ```bash
  docker network inspect plant-monitoring_plant-network --format '{{.IPAM.Config}}'
  # Should show: 10.10.0.0/24 (not 10.0.1.0/24)
  ```

- [ ] Check service VIPs are in correct range:
  ```bash
  docker service inspect plant-monitoring_kafka --format '{{.Endpoint.VirtualIPs}}'
  # Should show: 10.10.x.x (not 10.0.1.x)
  ```

- [ ] Verify all services are running:
  ```bash
  docker service ls
  # All services should show X/X (desired/actual match)
  ```

- [ ] Test connectivity from worker node:
  ```bash
  docker exec <worker-container> wget -O- kafka:9092
  # Should connect without timeout
  ```

- [ ] Check sensor logs from ALL replicas:
  ```bash
  docker service logs plant-monitoring_sensor --tail 20
  # Should see "Sent sensor data" from all sensor instances
  ```

- [ ] Verify processor is working:
  ```bash
  docker service logs plant-monitoring_processor --tail 20
  # Should see "Processed sensor data" messages
  ```

---

## Documentation Created

1. **`OVERLAY_NETWORK_IP_CONFLICT.md`** (PRIMARY)
   - Detailed explanation of overlay networks
   - How they work with AWS/cloud infrastructure
   - Routing conflict analysis
   - Best practices for IP allocation

2. **`KAFKA_DNS_TROUBLESHOOTING.md`** (UPDATED)
   - Original DNS debugging steps
   - Added section explaining real root cause
   - Shows how DNS was secondary to routing issue

3. **`README.md`** (UPDATED)
   - Added critical warning about overlay network conflicts
   - Quick reference for the fix
   - Link to detailed documentation

4. **`TROUBLESHOOTING_SUMMARY.md`** (THIS FILE)
   - Complete timeline of investigation
   - Lessons learned
   - Quick reference guide

---

## Prevention Strategy

### For Future Deployments

1. **Before Terraform Apply**:
   - Document all AWS VPC/subnet CIDRs
   - Choose overlay network CIDRs from different range
   - Update docker-compose.yml with explicit subnet

2. **In docker-compose.yml**:
   ```yaml
   networks:
     my-overlay:
       driver: overlay
       ipam:  # ← ALWAYS include this!
         config:
           - subnet: X.X.X.X/24  # Choose non-conflicting range
   ```

3. **Document Your Ranges**:
   ```markdown
   ## Network Configuration
   
   | Network | CIDR | Purpose |
   |---------|------|---------|
   | AWS VPC | 10.0.0.0/16 | Cloud infrastructure |
   | Manager Subnet | 10.0.1.0/24 | Public nodes |
   | Worker Subnet | 10.0.2.0/24 | Private nodes |
   | Overlay Network | 10.10.0.0/24 | Container network |
   ```

4. **Verify After Deployment**:
   ```bash
   # Quick check script
   echo "AWS Subnets:"
   terraform output
   
   echo "\nOverlay Network:"
   ssh manager "docker network inspect <network> --format '{{.IPAM.Config}}'"
   
   echo "\nShould be DIFFERENT ranges!"
   ```

---

## Cost of This Issue

### Time Spent
- Initial debugging: ~2 hours (DNS focus)
- Endpoint mode testing: ~1 hour
- Root cause discovery: ~30 minutes
- Documentation: ~1 hour
- **Total**: ~4.5 hours

### What We Learned
- Deep understanding of Docker overlay networks
- AWS VPC routing fundamentals
- Importance of explicit network configuration
- Systematic debugging methodology

**Worth it!** This knowledge prevents future similar issues.

---

## References

- Full overlay network analysis: `OVERLAY_NETWORK_IP_CONFLICT.md`
- DNS troubleshooting details: `KAFKA_DNS_TROUBLESHOOTING.md`
- Quick fix: `README.md` → Troubleshooting section
- Docker overlay networks: https://docs.docker.com/network/overlay/
- AWS VPC networking: https://docs.aws.amazon.com/vpc/

---

## Bottom Line

**Problem**: Docker overlay network used same IP range as AWS subnet  
**Impact**: Cross-node container communication failed  
**Solution**: Specify explicit overlay subnet in different range  
**Prevention**: Always configure overlay network subnets explicitly  

**One critical change to docker-compose.yml**:
```yaml
networks:
  plant-network:
    ipam:
      config:
        - subnet: 10.10.0.0/24  # ← This fixes everything!
```
