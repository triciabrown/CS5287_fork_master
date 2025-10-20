# Dynamic VIP Solution for Docker Swarm

## Problem
Docker Swarm assigns Virtual IP addresses (VIPs) to services dynamically when they start. These VIPs can change between deployments, making hardcoded IP addresses unreliable.

## Why Not Use DNS Hostnames?
We discovered that Docker's embedded DNS has reliability issues in multi-node Swarm clusters, causing `ENOTFOUND` errors even with proper configuration.

## Why Not Use Static IPs?
Static IP assignment (`ipv4_address` in docker-compose.yml) only works with `attachable: true` on the network, which itself causes DNS resolution problems in Swarm mode.

## Solution: Two-Phase Deployment with Dynamic VIP Updates

### Phase 1: Initial Deployment
1. **Deploy stack with DNS hostnames** (kafka, mongodb, mosquitto, zookeeper)
2. **Docker Swarm assigns VIPs** to each service automatically
3. **Services fail to connect** because DNS doesn't resolve properly
4. **Wait for VIPs to stabilize** (30-60 seconds)

### Phase 2: VIP Discovery and Update
1. **Query actual VIPs** from running services:
   ```bash
   docker service inspect plant-monitoring_kafka \
     --format '{{range .Endpoint.VirtualIPs}}{{.Addr}}{{end}}' | head -1 | cut -d'/' -f1
   ```

2. **Update docker-compose.yml** with actual IPs:
   - Replace `KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'` with actual VIP
   - Replace `KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://kafka:9092'` with actual VIP
   - Replace all other connection strings with VIPs

3. **Redeploy stack** with correct IPs
4. **Services connect successfully** using actual VIPs

### Implementation Files

**ansible/update-service-vips.yml** - Automates Phase 2:
- Queries VIPs from deployed services
- Updates docker-compose.yml with actual IPs
- Recreates MongoDB connection string secret with correct IP
- Redeploys stack with updated configuration

**deploy.sh** - Orchestrates both phases:
```bash
# Phase 1: Initial deployment
ansible-playbook ansible/deploy-stack.yml

# Wait for VIPs
sleep 45

# Phase 2: Update with actual VIPs
ansible-playbook ansible/update-service-vips.yml

# Wait for services to stabilize
sleep 30
```

## Benefits

✅ **Idempotent**: Can run multiple times safely
✅ **Dynamic**: VIPs discovered automatically each deployment
✅ **Reliable**: Uses actual IPs instead of broken DNS
✅ **One Command**: `./deploy.sh` handles everything
✅ **Scalable**: Works across multiple nodes

## Trade-offs

⚠️ **Two-phase deployment**: Takes longer (~2-3 minutes extra)
⚠️ **Temporary failures**: Services fail briefly during Phase 1
⚠️ **Complexity**: More moving parts than simple DNS approach

## Example VIP Assignment

After deployment, services get VIPs like:
```
ZooKeeper:  10.10.0.13
Kafka:      10.10.0.15
MongoDB:    10.10.0.18
Mosquitto:  10.10.0.20
```

These IPs remain stable until stack is removed and redeployed.

## Future Improvements

1. **Health checks**: Wait for actual service health instead of sleep timers
2. **Retry logic**: Automatically retry if VIP discovery fails
3. **DNS fallback**: Try DNS first, fall back to VIPs if needed
4. **External DNS**: Use Consul or CoreDNS for better service discovery
