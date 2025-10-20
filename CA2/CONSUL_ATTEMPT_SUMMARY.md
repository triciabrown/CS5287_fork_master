# Consul Service Discovery Attempt - Summary

**Date**: October 19, 2025  
**Status**: Abandoned - Consul is for Legacy Docker Swarm, not Swarm Mode

---

## Background: The DNS Problem

Throughout CA2 development, we consistently encountered DNS resolution failures when services tried to communicate across Docker Swarm nodes:

```
Error: getaddrinfo ENOTFOUND kafka
Error: connect ENOTFOUND mongodb
```

**Symptoms**:
- Services on worker nodes could NOT resolve hostnames for services on other nodes
- Docker's embedded DNS (127.0.0.11) would fail with `ENOTFOUND` errors
- Same services worked fine when forced to run on manager node only
- Cross-node communication was completely broken

**Previous Failed Attempts**:
1. ❌ Network offload fixes (`ethtool` settings for checksums)
2. ❌ Static IP assignment (doesn't work without `attachable: true`)
3. ❌ DNS hostname configuration
4. ❌ VIP endpoints (IPs would change, routing unreliable)
5. ❌ Custom DNS servers
6. ✅ **Forcing all services to manager** - This worked but defeated scalability purpose

---

## Why We Tried Consul

After exhausting Docker-native solutions, we decided to implement external service discovery using Consul + Registrator pattern.

**Rationale**:
- If Docker's built-in DNS is broken, use a proven external service discovery tool
- Consul provides reliable DNS-based service discovery
- Registrator auto-registers Docker services with Consul
- Services could query Consul DNS directly at a known static IP
- Production-grade solution used in many containerized environments

**The Plan**:
1. Deploy Consul at static IP `10.10.0.10` on the manager node
2. Deploy Registrator in global mode (runs on all nodes)
3. Configure all services with `dns: [10.10.0.10, 127.0.0.11]`
4. Services use `*.service.consul` hostnames (e.g., `kafka.service.consul:9092`)
5. Registrator watches Docker events and auto-registers services with Consul
6. Services query Consul DNS to discover each other

---

## Implementation Details

### docker-compose.yml Changes

```yaml
services:
  # Consul - Service Discovery
  consul:
    image: consul:1.15
    command: agent -server -bootstrap-expect=1 -ui -client=0.0.0.0 -recursor=8.8.8.8
    environment:
      CONSUL_BIND_INTERFACE: eth0
    ports:
      - target: 8500
        published: 8500
        mode: host  # UI
      - target: 8600
        published: 8600
        protocol: udp
        mode: host  # DNS
    networks:
      plant-network:
        ipv4_address: 10.10.0.10  # Static IP
    deploy:
      placement:
        constraints:
          - node.role == manager

  # Registrator - Auto-registration
  registrator:
    image: gliderlabs/registrator:master
    command: -internal consul://10.10.0.10:8500
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock
    deploy:
      mode: global  # Run on every node
      
  # Example service configuration
  kafka:
    dns:
      - 10.10.0.10  # Consul DNS
      - 127.0.0.11  # Docker DNS fallback
    dns_search:
      - service.consul
    environment:
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper.service.consul:2181'
      KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://kafka.service.consul:9092'
    deploy:
      endpoint_mode: dnsrr
    labels:
      SERVICE_NAME: "kafka"
```

### Network Configuration

```yaml
networks:
  plant-network:
    driver: overlay
    attachable: true  # Required for static IP assignment
    ipam:
      config:
        - subnet: 10.10.0.0/24
```

All services updated to use `.service.consul` domains in connection strings.

---

## What Happened During Deployment

### Attempt 1: YAML Syntax Errors
- **Issue**: Multiple YAML parse errors during deployment
- **Line 1**: Had `version: consul:` instead of `version: '3.8'`
- **Line 27**: Duplicate `services:` section
- **Resolution**: Fixed YAML syntax, redeployed

### Attempt 2: Consul Got Wrong IP
- **Expected**: Consul at `10.10.0.10`
- **Actual**: Consul assigned `10.10.0.16`
- **Why**: Other services started first and claimed earlier IPs in the subnet
- **Impact**: Registrator couldn't connect to Consul at expected address

### Attempt 3: Registrator Failures on Workers
- **Manager Node**: ✅ Registrator connected successfully, registered services
- **Worker Nodes**: ❌ Registrator couldn't reach Consul
  ```
  Get http://consul:8500/v1/status/leader: dial tcp: lookup consul on 127.0.0.11:53: no such host
  Get http://consul:8500/v1/status/leader: dial tcp 10.10.0.15:8500: i/o timeout
  ```
- **Root Cause**: Same DNS problem we were trying to solve! Workers can't resolve `consul` hostname or reliably reach Consul's IP

**The Irony**: We were using Consul to fix DNS, but Consul itself couldn't work because of the DNS problem!

---

## Why We Abandoned Consul

### Discovery: Consul is for Legacy Swarm Only

Found Stack Overflow answer explaining:
- **Legacy/Classic Swarm**: Required external key/value store (Consul/Etcd/ZooKeeper)
- **Modern Swarm Mode**: Has built-in raft consensus and service discovery
- **Docker 1.12+**: Swarm Mode integrated into Docker Engine
- **Key Quote**: "Any guide that doesn't start with `docker swarm init` should be ignored as outdated"

**Reference**: https://stackoverflow.com/questions/61137756/

### Our Swarm Uses Modern Swarm Mode

```bash
# We initialized with:
docker swarm init --advertise-addr 10.0.1.54

# NOT the legacy standalone Swarm setup
```

### Consul is Unnecessary and Won't Fix The Real Problem

1. **Not Needed**: Swarm Mode has built-in service discovery
2. **Wrong Tool**: Consul is for legacy standalone Docker mode
3. **Won't Work**: Consul itself suffers from the same networking issue
4. **Adds Complexity**: Extra moving parts that aren't solving the root cause

---

## The REAL Problem

The issue is **NOT** Docker's service discovery mechanism. The issue is **underlying network connectivity** between Swarm nodes.

**Evidence**:
- Services work fine when on same node (manager-only deployment worked)
- Cross-node communication fails consistently
- Even Consul's Registrator can't communicate across nodes
- Worker nodes are in private subnet (10.0.2.x)
- Manager node has both public and private IPs

**Likely Root Causes**:
1. **AWS Security Group Rules**: May be blocking required Swarm ports between nodes
   - TCP/UDP 2377 (cluster management)
   - TCP/UDP 7946 (container network discovery)
   - UDP 4789 (overlay network VXLAN traffic)
2. **Subnet Routing**: Workers in 10.0.2.0/24, manager in 10.0.1.0/24
3. **Firewall Rules**: iptables or AWS NACLs blocking inter-node traffic

---

## Lessons Learned

1. ✅ **Always check if tool is needed**: Modern Docker Swarm has built-in service discovery
2. ✅ **Fix root causes, not symptoms**: Adding Consul didn't fix the networking issue
3. ✅ **Research tool applicability**: Consul is for legacy Swarm, not Swarm Mode
4. ✅ **Network issues affect everything**: If Docker DNS fails, external tools will too

---

## Next Steps (Post-Consul)

1. **Remove Consul/Registrator** from docker-compose.yml
2. **Verify AWS Security Groups** allow required Swarm ports:
   ```
   TCP 2377  - Cluster management
   TCP 7946  - Node communication
   UDP 7946  - Node communication
   UDP 4789  - Overlay network traffic
   ```
3. **Test inter-node connectivity** manually:
   ```bash
   # From worker node, test overlay network
   ping -c 3 <manager-overlay-ip>
   nc -zv <manager-ip> 2377 7946 4789
   ```
4. **Use Docker's built-in DNS** as designed
5. **Strategic service placement**:
   - Home Assistant → Manager (needs public IP for port 8123)
   - Other services → Let Swarm schedule naturally
   - Use `endpoint_mode: vip` for internal services

---

## Files Modified for Consul Attempt

- `docker-compose.yml`: Added Consul, Registrator services; configured all services with Consul DNS
- `ansible/deploy-stack.yml`: Updated MongoDB connection string to use `mongodb.service.consul`

**Commit before removal**: (Current state with Consul implementation)

---

## Conclusion

While Consul is an excellent service discovery tool, it's designed for legacy Docker Swarm (pre-1.12). Modern Docker Swarm Mode has built-in service discovery that works reliably **when the underlying network is configured correctly**.

Our DNS problems are network connectivity issues, not service discovery architectural issues. Adding Consul was trying to solve a network problem with an application-layer solution, which cannot work.

**The path forward**: Fix the AWS networking configuration to allow proper Swarm communication between nodes.
