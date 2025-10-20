# Docker Overlay Network IP Conflict Issue

## Critical Issue: Overlay Network vs AWS Subnet IP Overlap

### Problem Summary

**Symptom**: Services running on worker nodes cannot connect to Kafka on the manager node, even though DNS resolution works. Connections timeout with `Connection timeout` errors.

**Root Cause**: Docker overlay network automatically assigned the same IP range (10.0.1.0/24) as the AWS public subnet, creating a routing conflict.

---

## Understanding Docker Overlay Networks

### What is an Overlay Network?

A Docker Swarm **overlay network** is a virtual network that spans multiple Docker hosts (nodes). It enables containers on different physical machines to communicate as if they were on the same local network.

**Key characteristics**:
- Creates a virtual Layer 2 network using VXLAN (Virtual Extensible LAN) tunneling
- Encrypts traffic between nodes when `encrypted: true` is set
- Assigns virtual IP addresses to services and containers
- Routes traffic between nodes automatically

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS VPC (10.0.0.0/16)                   │
│                                                             │
│  ┌──────────────────────┐      ┌──────────────────────────┐│
│  │ Manager Node         │      │ Worker Node              ││
│  │ AWS IP: 10.0.1.52    │      │ AWS IP: 10.0.2.13        ││
│  │ Public Subnet        │      │ Private Subnet           ││
│  │                      │      │                          ││
│  │ ┌──────────────────┐ │      │ ┌──────────────────────┐││
│  │ │ Kafka Container  │ │      │ │ Sensor Container     │││
│  │ │ Overlay IP: ???  │ │      │ │ Overlay IP: ???      │││
│  │ └──────────────────┘ │      │ └──────────────────────┘││
│  └──────────────────────┘      └──────────────────────────┘│
│           │                              │                  │
│           └──────────────────────────────┘                  │
│              Virtual Overlay Network                        │
│              (Tunneled over AWS network)                    │
└─────────────────────────────────────────────────────────────┘
```

**The overlay network operates OVER the physical AWS network**:
1. Container in sensor tries to reach `kafka:9092`
2. DNS resolves to Kafka's overlay IP (e.g., 10.X.X.X)
3. Docker routes through VXLAN tunnel to manager node
4. Manager node delivers to Kafka container

---

## The IP Conflict Problem

### What Happened

When we created the overlay network without specifying a subnet, Docker chose `10.0.1.0/24`:

```yaml
# Original (no subnet specified)
networks:
  plant-network:
    driver: overlay
    driver_opts:
      encrypted: "true"
```

**Result**:
```bash
$ docker network inspect plant-monitoring_plant-network
[{10.0.1.0/24  10.0.1.1 map[]}]  # Overlay network

# But our AWS subnet is ALSO 10.0.1.0/24!
AWS Public Subnet: 10.0.1.0/24
Manager Node: 10.0.1.52
```

### Why This Causes Problems

**Routing Ambiguity**: When a container on a worker node (10.0.2.x) tries to reach an overlay IP like `10.0.1.68`:

1. **Container routing table sees**: "10.0.1.0/24 is directly connected via overlay network"
2. **Host routing table sees**: "10.0.1.0/24 is the AWS public subnet"
3. **Result**: Packets get confused - should they go through the overlay tunnel or the AWS network?

```
Worker Container trying to reach 10.0.1.68 (Kafka VIP):

Option A (Overlay):        Option B (AWS):
Container                  Container
    ↓                          ↓
Overlay Interface          eth0 (AWS network)
    ↓                          ↓
VXLAN Tunnel              AWS routing
    ↓                          ↓
Manager Overlay           10.0.1.68 (doesn't exist!)
    ↓                          
Kafka Container           ❌ Timeout!
    ↓
✅ Success!
```

**The routing stack can't determine which path to use**, leading to:
- Connection timeouts
- Intermittent failures
- Services on manager work (same subnet) but worker services fail

### Services That Worked vs Failed

**✅ Working**:
- Sensor replica on manager node (10.0.1.52) - no routing ambiguity
- Services communicating within same node

**❌ Failing**:
- Sensor replicas on worker nodes (10.0.2.x) - routing conflict
- Processor on worker nodes - can't reach Kafka
- Any cross-node communication involving 10.0.1.x overlay IPs

---

## The Solution

### Specify a Non-Conflicting Subnet

```yaml
networks:
  plant-network:
    driver: overlay
    driver_opts:
      encrypted: "true"
    ipam:
      driver: default
      config:
        - subnet: 10.10.0.0/24  # Different from AWS subnets (10.0.x.x)
```

**Why this works**:
- Overlay network uses 10.10.0.0/24
- AWS networks use 10.0.1.0/24 and 10.0.2.0/24
- No ambiguity - routing tables are clear:
  - `10.0.x.x` → AWS network (physical)
  - `10.10.x.x` → Overlay network (virtual)

### Clear Routing Decision

```
Worker Container reaching 10.10.0.68 (Kafka VIP on new overlay):

Container
    ↓
Sees destination: 10.10.0.68
    ↓
Routing table: "10.10.0.0/24 → overlay network"
    ↓
VXLAN Tunnel to manager node
    ↓
Manager's overlay interface
    ↓
Kafka Container (10.10.0.68)
    ↓
✅ Success!
```

---

## Best Practices

### 1. Always Specify Overlay Subnet

**DON'T**:
```yaml
networks:
  mynetwork:
    driver: overlay
```

**DO**:
```yaml
networks:
  mynetwork:
    driver: overlay
    ipam:
      config:
        - subnet: 10.10.0.0/24  # Explicit, non-conflicting
```

### 2. Choose Non-Overlapping Ranges

**AWS Subnets**: 10.0.x.x
**Overlay Networks**: 10.10.x.x, 172.20.x.x, or 192.168.x.x

**Common ranges to avoid conflicts**:
- `10.10.0.0/16` - for overlay networks
- `172.20.0.0/16` - alternate overlay range
- `192.168.100.0/24` - small overlay networks

### 3. Document Your IP Ranges

Keep a table in your README:

| Network Type | CIDR | Usage |
|--------------|------|-------|
| AWS VPC | 10.0.0.0/16 | Physical network |
| AWS Public Subnet | 10.0.1.0/24 | Manager nodes |
| AWS Private Subnet | 10.0.2.0/24 | Worker nodes |
| **Overlay Network** | **10.10.0.0/24** | **Docker overlay** |

---

## Diagnosis Steps

If you suspect an overlay network conflict:

### 1. Check AWS Subnet Ranges
```bash
# In Terraform
grep "cidr_block" terraform/main.tf
```

### 2. Check Overlay Network Range
```bash
ssh manager "docker network inspect <network-name> --format '{{.IPAM.Config}}'"
```

### 3. Look for Overlap
```bash
AWS Subnet:    10.0.1.0/24
Overlay:       10.0.1.0/24  ❌ CONFLICT!

AWS Subnet:    10.0.1.0/24
Overlay:       10.10.0.0/24  ✅ No conflict
```

### 4. Check Service VIPs
```bash
docker service inspect <service> --format "{{.Endpoint.VirtualIPs}}"
# Example output: [{network-id 10.0.1.68/24}]
# If IP is in AWS range → CONFLICT
```

### 5. Test Cross-Node Connectivity
```bash
# From a container on worker node
docker exec <container> ping <service-name>
# If DNS works but ping/connection fails → likely routing issue
```

---

## Related Issues

### This Masked the DNS Issue

Initially, we thought the problem was Docker Swarm's VIP endpoint mode causing DNS failures. We tried:
- ✅ Adding `endpoint_mode: dnsrr` → Helped with DNS but didn't fix connectivity
- ❌ Services still timed out because of routing conflict

**The real problem was the IP overlap**, which prevented proper packet routing even after DNS resolved correctly.

### Why DNS Seemed to Work on Manager

Services on the manager node could connect because:
- Both the AWS network (10.0.1.52) and overlay network (10.0.1.x) were physically on the same host
- No cross-node routing required
- Local bridge handled communication

This created **misleading symptoms** - "it works on the manager but not workers" suggested a worker-specific issue, when it was actually a network architecture problem.

---

## Verification After Fix

After redeploying with `subnet: 10.10.0.0/24`:

```bash
# 1. Check overlay network
docker network inspect plant-monitoring_plant-network
# Should show: 10.10.0.0/24

# 2. Check service VIPs
docker service inspect plant-monitoring_kafka --format "{{.Endpoint.VirtualIPs}}"
# Should show: 10.10.x.x (not 10.0.1.x)

# 3. Test connectivity from worker
docker exec <worker-container> wget -O- kafka:9092
# Should connect successfully

# 4. Check sensor logs
docker service logs plant-monitoring_sensor --tail 10
# Should show "Sent sensor data" messages from ALL replicas
```

---

## Key Takeaway

**Docker overlay networks are virtual networks that exist OVER your physical infrastructure**. They must use IP ranges that don't conflict with your underlying cloud provider networks (AWS, Azure, GCP, etc.).

Always explicitly configure overlay network subnets in production deployments to avoid routing conflicts.

---

## References

- [Docker Overlay Network Driver](https://docs.docker.com/network/overlay/)
- [IPAM Configuration](https://docs.docker.com/compose/compose-file/compose-file-v3/#ipam)
- [VXLAN Protocol](https://en.wikipedia.org/wiki/Virtual_Extensible_LAN)
- AWS VPC CIDR Planning Best Practices
