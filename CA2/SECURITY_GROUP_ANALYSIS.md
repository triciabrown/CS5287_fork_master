# Security Group Analysis for Docker Swarm

**Date**: October 19, 2025  
**Purpose**: Verify AWS security groups allow proper Docker Swarm networking

---

## Current Configuration

### Manager Security Group (`swarm_manager_sg`)

**Ingress Rules**:
```
✅ Port 22 (SSH)           - From: 0.0.0.0/0
✅ Port 8123 (Home Asst)   - From: 0.0.0.0/0
✅ Port 2377 (Swarm Mgmt)  - From: VPC CIDR (10.0.0.0/16)
✅ Port 7946 TCP (Node Comm) - From: VPC CIDR
✅ Port 7946 UDP (Node Comm) - From: VPC CIDR
✅ Port 4789 UDP (Overlay)   - From: VPC CIDR
✅ Ports 0-65535 TCP        - From: VPC CIDR
```

**Egress Rules**:
```
✅ All traffic - To: 0.0.0.0/0
```

### Worker Security Group (`swarm_worker_sg`)

**Ingress Rules**:
```
✅ Port 22 (SSH)           - From: Manager SG only
✅ Port 2377 (Swarm Mgmt)  - From: Manager SG only
✅ Port 7946 TCP (Node Comm) - From: VPC CIDR (10.0.0.0/16)
✅ Port 7946 UDP (Node Comm) - From: VPC CIDR
✅ Port 4789 UDP (Overlay)   - From: VPC CIDR
✅ Ports 0-65535 TCP        - From: VPC CIDR
```

**Egress Rules**:
```
✅ All traffic - To: 0.0.0.0/0
```

---

## Docker Swarm Required Ports

According to Docker documentation, Swarm requires:

| Port | Protocol | Purpose | Our Config |
|------|----------|---------|------------|
| 2377 | TCP | Cluster management | ✅ Configured |
| 7946 | TCP | Node communication | ✅ Configured |
| 7946 | UDP | Node communication | ✅ Configured |
| 4789 | UDP | Overlay network (VXLAN) | ✅ Configured |

**Reference**: https://docs.docker.com/engine/swarm/swarm-tutorial/#open-protocols-and-ports-between-the-hosts

---

## Potential Issues

### 1. ⚠️ UDP Port 4789 May Need Self-Reference

**Current**: Workers allow UDP 4789 from VPC CIDR  
**Issue**: Some configurations require UDP 4789 to also allow from **the security group itself**

This is because overlay network traffic is **encrypted and encapsulated** VXLAN traffic between containers, not just nodes.

**Recommendation**: Add self-referencing rule for workers:
```hcl
ingress {
  from_port       = 4789
  to_port         = 4789
  protocol        = "udp"
  self            = true
  description     = "Overlay network - worker to worker"
}
```

### 2. ⚠️ Worker-to-Worker Port 7946 Needs Self-Reference

**Current**: Workers allow 7946 from VPC CIDR  
**Issue**: Workers need to gossip with **each other**, not just with manager

**Recommendation**: Add self-referencing rule:
```hcl
ingress {
  from_port       = 7946
  to_port         = 7946
  protocol        = "tcp"
  self            = true
  description     = "Worker to worker gossip TCP"
}

ingress {
  from_port       = 7946
  to_port         = 7946
  protocol        = "udp"
  self            = true
  description     = "Worker to worker gossip UDP"
}
```

### 3. ❓ Catch-All TCP Rule Might Be Masking Issues

**Current**: Both groups have `0-65535 TCP` from VPC CIDR

**Analysis**: This rule should theoretically allow all container-to-container communication, but:
- It only covers **TCP**, not UDP
- May not apply to encapsulated overlay traffic
- VXLAN uses UDP 4789 for overlay, which needs special handling

---

## Network Topology

```
VPC: 10.0.0.0/16
├── Public Subnet: 10.0.1.0/24
│   └── Manager: 10.0.1.54 (+ public IP 3.137.198.166)
│       └── Security Group: swarm_manager_sg
└── Private Subnet: 10.0.2.0/24
    ├── Worker1: 10.0.2.200
    ├── Worker2: 10.0.2.37
    ├── Worker3: 10.0.2.150
    └── Worker4: 10.0.2.156
        └── Security Group: swarm_worker_sg (all 4 workers)

Overlay Network: 10.10.0.0/24 (virtual, encrypted VXLAN)
```

**Key Point**: Workers share the **same security group**, so they need **self-referencing rules** to communicate with each other.

---

## Testing Network Connectivity

### From Manager to Workers

```bash
# Test from manager node
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.198.166

# Test TCP connectivity
for ip in 10.0.2.200 10.0.2.37 10.0.2.150 10.0.2.156; do
  echo "Testing $ip..."
  nc -zv -w2 $ip 2377  # Swarm management
  nc -zv -w2 $ip 7946  # Node comm TCP
done

# Test UDP connectivity (requires netcat-openbsd)
for ip in 10.0.2.200 10.0.2.37 10.0.2.150 10.0.2.156; do
  echo "Testing UDP $ip..."
  nc -uzv -w2 $ip 4789  # Overlay VXLAN
  nc -uzv -w2 $ip 7946  # Node comm UDP
done
```

### From Worker to Worker (via Manager)

```bash
# SSH to manager, then jump to worker
ssh -i ~/.ssh/docker-swarm-key ubuntu@3.137.198.166
ssh ubuntu@10.0.2.200  # Jump to worker1

# From worker1, test other workers
for ip in 10.0.2.37 10.0.2.150 10.0.2.156; do
  echo "Worker to worker: $ip"
  nc -zv -w2 $ip 7946
  nc -uzv -w2 $ip 4789
done
```

### Test Overlay Network Specifically

```bash
# From manager
docker network inspect plant-monitoring_plant-network

# Try to ping container IPs across nodes
docker run -it --rm --network plant-monitoring_plant-network alpine ping <container-ip>
```

---

## Recommended Security Group Changes

### Option 1: Add Self-Referencing Rules (RECOMMENDED)

Add to `swarm_worker_sg`:

```hcl
# Worker-to-worker gossip TCP
ingress {
  from_port   = 7946
  to_port     = 7946
  protocol    = "tcp"
  self        = true
  description = "Worker to worker communication TCP"
}

# Worker-to-worker gossip UDP
ingress {
  from_port   = 7946
  to_port     = 7946
  protocol    = "udp"
  self        = true
  description = "Worker to worker communication UDP"
}

# Worker-to-worker overlay
ingress {
  from_port   = 4789
  to_port     = 4789
  protocol    = "udp"
  self        = true
  description = "Worker to worker overlay network"
}
```

### Option 2: Add UDP Catch-All Rule

If Option 1 doesn't work, add UDP catch-all:

```hcl
ingress {
  from_port   = 0
  to_port     = 65535
  protocol    = "udp"
  cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
  description = "Internal VPC UDP communication"
}
```

---

## Why Security Groups Might Not Be The Problem

**Evidence that security groups are likely OK**:

1. ✅ All required Swarm ports are open
2. ✅ Catch-all TCP rule from VPC CIDR exists
3. ✅ Overlay network UDP port 4789 is open from VPC CIDR
4. ✅ Workers were able to **join the swarm** (requires port 2377 working)
5. ✅ Manager can see all workers (requires port 7946 working)

**If security groups were blocking**, we would see:
- Workers failing to join swarm
- `docker node ls` showing nodes as "Down"
- Timeout errors when deploying services

**What we actually see**:
- ✅ Workers joined successfully
- ✅ All nodes show as "Ready"
- ✅ Services deploy successfully
- ❌ **DNS resolution fails** - This is application-layer, not network-layer

---

## Alternative Theories

### Theory 1: Docker DNS Bug with Encrypted Overlay

Some reports suggest Docker's embedded DNS (127.0.0.11) has issues with **encrypted overlay networks**.

**Test**: Try removing `encrypted: "true"` from network config:

```yaml
networks:
  plant-network:
    driver: overlay
    # driver_opts:
    #   encrypted: "true"  # Try disabling
```

### Theory 2: Service Endpoint Mode Issues

Docker has two endpoint modes:
- **VIP** (default): Virtual IP with load balancing
- **DNSRR**: DNS Round Robin (no VIP)

**Test**: Try consistent endpoint mode across services:

```yaml
services:
  zookeeper:
    deploy:
      endpoint_mode: vip  # Try VIP mode consistently
```

### Theory 3: MTU Issues with Overlay Network

VXLAN adds overhead (50 bytes), which can cause MTU issues if not accounted for.

**Test**: Check MTU on nodes:
```bash
# On each node
ip link show eth0
# Should show MTU 9001 (AWS default)

# Check overlay network MTU
docker network inspect plant-monitoring_plant-network | grep -i mtu
```

---

## Next Steps

1. **Test connectivity** with commands above
2. **Add self-referencing rules** to worker security group
3. **Try disabling encryption** on overlay network
4. **Check Docker Swarm logs** for specific errors:
   ```bash
   journalctl -u docker.service -f
   ```
5. **Test with simple service**:
   ```bash
   docker service create --name test-ping \
     --network plant-monitoring_plant-network \
     alpine ping google.com
   
   docker service logs test-ping
   ```

---

## Summary

**Security groups look mostly correct**, but could benefit from:
- Self-referencing rules for worker-to-worker communication
- Explicit UDP rules for overlay network

**However, the DNS issue might not be a security group problem** - it could be:
- Docker DNS bug with encrypted overlays
- MTU mismatch issues
- Service endpoint mode inconsistencies

**Recommendation**: Add self-referencing rules first (easy win), then investigate Docker-specific issues if problem persists.
