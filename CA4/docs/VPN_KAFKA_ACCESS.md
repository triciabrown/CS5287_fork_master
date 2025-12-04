# VPN to Kafka Access - Solution & Alternatives

**Date**: November 23, 2025  
**Status**: ✅ Working Solution Implemented

---

## Problem Statement

Edge sensors need to publish data to Kafka running in the cloud Docker Swarm, but:
- Kafka runs inside a Docker overlay network (`messaging-net` at 10.10.2.0/24)
- WireGuard VPN terminates on the manager node (`10.20.0.1`)
- These are different network namespaces
- Kafka's container IP changes on every redeployment

---

## ✅ Solution Implemented: Port Publishing with Manager Pinning

### Configuration

```yaml
kafka:
  ports:
    - target: 9092
      published: 9092
      protocol: tcp
      mode: host  # Publish on manager node's host network
  deploy:
    placement:
      constraints:
        - node.role == manager  # Pin Kafka to manager node
    # Removed endpoint_mode: dnsrr (incompatible with port publishing)
```

### How It Works

```
Edge Sensor (10.20.0.2)
    ↓ VPN tunnel (encrypted)
Manager Node wg0 interface (10.20.0.1:9092)
    ↓ Docker port publishing (mode: host)
Manager Node eth0 interface (10.0.1.161:9092)
    ↓ Docker bridge/routing
Kafka container (10.10.2.x:9092) ← Dynamic IP doesn't matter!
```

### Benefits

✅ **Works across redeployments** - Container IP changes don't affect connectivity  
✅ **No manual iptables rules** - Docker handles port forwarding automatically  
✅ **Simple configuration** - Just add ports + placement constraint  
✅ **Survives reboots** - Configuration is in docker-compose.yml  
✅ **Minimal overhead** - Direct port publishing, no extra routing hops

### Tradeoffs

⚠️ **Kafka pinned to manager** - Can't distribute Kafka across workers  
⚠️ **No load balancing** - Single Kafka instance (acceptable for CA4)  
⚠️ **Port conflict risk** - Port 9092 must be free on manager node  
⚠️ **Network isolation** - Kafka port exposed on manager's host network (controlled by AWS security group)

---

## 🔄 Alternative Solution: ZeroTier Overlay Network

### When to Use ZeroTier

ZeroTier would be better if:

1. **Multi-node Kafka cluster** - Need Kafka brokers on multiple workers
2. **Dynamic service placement** - Don't want to pin services to specific nodes
3. **Complex routing requirements** - Multiple VPN clients accessing different services
4. **Simplified networking** - Want all nodes on a flat L2 network
5. **Cross-cloud deployment** - Services spanning AWS + Azure + on-prem

### ZeroTier Architecture

```
┌─────────────────────────────────────────────────────────────┐
│         ZeroTier Network (e.g., 192.168.192.0/24)           │
├─────────────────────────────────────────────────────────────┤
│  Edge Laptop:     192.168.192.10                            │
│  Manager Node:    192.168.192.100  (also 10.0.1.161)        │
│  Worker 1:        192.168.192.101  (also 10.0.2.38)         │
│  Worker 2:        192.168.192.102  (also 10.0.2.147)        │
│  Worker 3:        192.168.192.103  (also 10.0.2.115)        │
│  Worker 4:        192.168.192.104  (also 10.0.2.160)        │
└─────────────────────────────────────────────────────────────┘
```

### Benefits of ZeroTier

✅ **All nodes accessible** - Edge can reach any service on any node  
✅ **No port publishing needed** - Direct container-to-container communication  
✅ **No manual routing** - ZeroTier handles all routing automatically  
✅ **Dynamic topology** - Services can move between nodes freely  
✅ **Multi-platform** - Works on Linux, Windows, macOS, mobile  
✅ **NAT traversal** - Works through most firewalls automatically

### Tradeoffs of ZeroTier

⚠️ **Additional dependency** - Requires ZeroTier controller (cloud or self-hosted)  
⚠️ **More complex setup** - Each node needs ZeroTier daemon installed  
⚠️ **IP address management** - Need to track ZeroTier IPs vs host IPs  
⚠️ **Potential performance** - Extra encapsulation layer  
⚠️ **Security surface** - Another network layer to secure

### ZeroTier Implementation for CA4

If we wanted to use ZeroTier instead:

1. **Install on all nodes**:
   ```bash
   curl -s https://install.zerotier.com | sudo bash
   sudo zerotier-cli join <NETWORK_ID>
   ```

2. **Update Kafka advertised listeners**:
   ```yaml
   KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://192.168.192.100:9092'
   ```

3. **No port publishing needed**:
   ```yaml
   kafka:
     # ports: section removed
     deploy:
       # No placement constraints needed
   ```

4. **Edge sensors connect directly**:
   ```yaml
   KAFKA_BROKERS: '192.168.192.100:9092'  # Manager's ZeroTier IP
   ```

---

## 📊 Comparison Matrix

| Feature | WireGuard + Port Publishing | ZeroTier Overlay |
|---------|----------------------------|------------------|
| **Setup Complexity** | Low (VPN + docker-compose) | Medium (VPN + ZT daemon) |
| **Service Flexibility** | Low (must pin to manager) | High (any node) |
| **Performance** | Excellent (direct port) | Good (extra encapsulation) |
| **Redeployment Impact** | None (pinned) | None (dynamic) |
| **Multi-cloud Support** | Limited (VPN endpoints) | Excellent (global network) |
| **Kafka Clustering** | Single node only | Multi-node supported |
| **Edge Complexity** | Low (just VPN config) | Medium (VPN + ZT client) |
| **Dependencies** | None (built-in Docker) | ZeroTier controller |
| **Security** | VPN + AWS SG | VPN + ZT auth + AWS SG |
| **Cost** | $0 (open source) | $0 (free tier) or paid |

---

## 🎯 Recommendation for CA4

**Use Current Solution (WireGuard + Port Publishing)**

**Reasons:**
1. ✅ Meets assignment requirements (edge-to-cloud via VPN)
2. ✅ Simple and reliable architecture
3. ✅ Single Kafka instance is sufficient for plant monitoring
4. ✅ No additional dependencies required
5. ✅ Well-documented and easy to understand for grading

**When to Switch to ZeroTier:**
- If scaling to multiple Kafka brokers across workers
- If adding more edge sites in different locations
- If implementing multi-cloud disaster recovery
- If needing mesh network between edge sites
- If CA5 requires more complex multi-node scenarios

---

## 🔐 Security Considerations

### Current Solution (WireGuard + Port Publishing)

**Security Layers:**
1. **WireGuard encryption** - All VPN traffic encrypted with ChaCha20-Poly1305
2. **AWS Security Group** - Only VPN subnet (10.20.0.0/24) can access port 9092
3. **No public internet exposure** - Kafka not accessible from outside AWS
4. **Key-based authentication** - Only authorized edge clients with private keys

**Attack Surface:**
- Manager node port 9092 (restricted to VPN subnet)
- WireGuard port 51820 (UDP, encrypted handshake)

### ZeroTier Alternative

**Security Layers:**
1. **WireGuard encryption** (if still used for outer VPN)
2. **ZeroTier encryption** - AES-256 + Salsa20
3. **ZeroTier network auth** - Devices must be authorized in controller
4. **AWS Security Group** - Can still restrict by IP ranges

**Attack Surface:**
- ZeroTier daemon on each node (additional process)
- ZeroTier controller (if self-hosted, or trust ZeroTier cloud)
- Flat network access (all nodes can reach each other)

---

## 📝 Troubleshooting

### Current Solution

**Issue:** Can't connect to Kafka via VPN

1. Check VPN is up: `sudo wg show`
2. Test VPN connectivity: `ping 10.20.0.1`
3. Test Kafka port: `telnet 10.20.0.1 9092`
4. Verify Kafka on manager: `ssh manager 'docker ps | grep kafka'`
5. Check port publishing: `ssh manager 'sudo netstat -tlnp | grep 9092'`

**Issue:** Kafka fails to start

1. Check logs: `docker service logs plant-monitoring_kafka`
2. Verify listener ports are different (if using multiple)
3. Ensure manager node has port 9092 available

### ZeroTier (if implemented)

**Issue:** Can't reach Kafka

1. Check ZeroTier network: `sudo zerotier-cli listnetworks`
2. Verify authorized: Check ZeroTier controller web UI
3. Test ZeroTier connectivity: `ping <manager-zt-ip>`
4. Verify Kafka advertised listener matches ZeroTier IP

---

## ✅ Current Status

- **VPN**: ✅ WireGuard operational (10.20.0.0/24)
- **Kafka Access**: ✅ Port 9092 published on manager node
- **Connectivity**: ✅ Edge can reach 10.20.0.1:9092
- **Placement**: ✅ Kafka pinned to manager node
- **Port Publishing**: ✅ mode: host (not ingress)
- **Redeployment**: ✅ Survives stack redeploy

**Test Results:**
```bash
$ ping -c 3 10.20.0.1
3 packets transmitted, 3 received, 0% packet loss

$ telnet 10.20.0.1 9092
Connected to 10.20.0.1.
```

---

## 📚 References

- [WireGuard Documentation](https://www.wireguard.com/)
- [Docker Swarm Port Publishing](https://docs.docker.com/engine/swarm/services/#publish-ports)
- [ZeroTier Documentation](https://docs.zerotier.com/)
- [Kafka Listeners Explained](https://www.confluent.io/blog/kafka-listeners-explained/)

---

**Conclusion**: The current WireGuard + port publishing solution is simple, performant, and meets all CA4 requirements. ZeroTier remains a viable alternative for more complex multi-node scenarios in future assignments.
