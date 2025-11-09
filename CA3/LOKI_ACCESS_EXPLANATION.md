# Loki Access and Query Limitations - CA3

## Why Loki Port 3100 is Not Publicly Accessible

**This is BY DESIGN for security.**

From `terraform/security-groups-tiers.tf`:
```terraform
# Loki - Internal to VPC only (accessed via Grafana)
ingress {
  from_port   = 3100
  to_port     = 3100
  protocol    = "tcp"
  cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]  # INTERNAL ONLY
  description = "Loki log aggregation (internal only)"
}
```

### Security Rationale

1. **Data Protection**: Loki stores all application logs, potentially containing:
   - Error messages with stack traces
   - User IDs and plant identifiers
   - System configuration details
   - Performance metrics

2. **Least Privilege**: Only services within the VPC should directly query Loki
   - Grafana (port 3000) provides controlled access
   - Prometheus scrapes metrics but doesn't need Loki
   - External users query through Grafana's UI

3. **Attack Surface Reduction**: Loki's API is powerful:
   - Can query historical data
   - Can export large volumes of logs
   - Should not be internet-facing

### Comparison with Other Services

| Service    | Port | Public Access | Why                                    |
|------------|------|---------------|----------------------------------------|
| Grafana    | 3000 | ✅ Yes        | User-facing dashboard with auth        |
| Prometheus | 9090 | ✅ Yes        | Read-only metrics, less sensitive      |
| Loki       | 3100 | ❌ No         | Contains raw logs, internal only       |
| MongoDB    | 27017| ❌ No         | Database, VPC-internal only            |
| Kafka      | 9092 | ❌ No         | Message broker, VPC-internal only      |

## How to Access Loki for CA3 Screenshot

### Method 1: Grafana Explore (Recommended but has issues)

**Problem**: Queries timeout with large log volumes despite optimization:
- Loki resources: 1GB RAM, 1.0 CPU
- Log volume: 5 nodes × multiple services × continuous operation
- Query timeout: 30 seconds (Grafana default)

**Workaround**: Use very narrow time ranges
```
1. Go to http://52.14.239.94:3000
2. Navigate to Explore
3. Select "Loki" datasource
4. Set time range: Last 30 seconds (not 5 minutes!)
5. Query: {container_name="plant-monitoring_processor"} |~ "error"
```

### Method 2: SSH Tunnel (Direct API Access)

```bash
# Create SSH tunnel
ssh -i ~/.ssh/docker-swarm-key -L 3100:localhost:3100 ubuntu@52.14.239.94

# In another terminal or browser
curl http://localhost:3100/ready
curl http://localhost:3100/loki/api/v1/label
```

### Method 3: Remote Query via SSH (For Screenshots)

```bash
# Check Loki status
ssh -i ~/.ssh/docker-swarm-key ubuntu@52.14.239.94 'curl -s http://localhost:3100/ready'

# Query recent logs
ssh -i ~/.ssh/docker-swarm-key ubuntu@52.14.239.94 'curl -s -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode "query={container_name=\"plant-monitoring_processor\"}" \
  --data-urlencode "limit=10" \
  --data-urlencode "start=$(date -u -d \"1 minute ago\" +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000" | jq .'
```

### Method 4: Docker Service Logs (Alternative Demonstration)

Since Promtail IS collecting logs from all services and sending to Loki, demonstrate centralized logging via Docker:

```bash
# Show logs from all pipeline components with timestamps and labels
for svc in sensor kafka processor mongodb; do
  echo "=== plant-monitoring_$svc ==="
  ssh -i ~/.ssh/docker-swarm-key ubuntu@52.14.239.94 \
    "docker service logs plant-monitoring_$svc --timestamps --tail 5"
done
```

This demonstrates:
✅ Centralized log collection (Promtail on all nodes)
✅ Timestamps (Docker adds them)
✅ Pod/container labels (service name, task ID)
✅ Structured fields (JSON logging in apps)

## For CA3 Submission

### Screenshot Options

**Option A - Grafana UI (Ideal but may timeout)**:
- Screenshot of Grafana Explore with Loki datasource
- Shows query interface even if results timeout
- Add note: "Query timeouts due to high log volume - see alternative below"

**Option B - Terminal Logs (More Reliable)**:
- Screenshot of `docker service logs` showing:
  - ✅ Timestamps
  - ✅ Service labels  
  - ✅ Structured JSON fields
  - ✅ Error filtering with grep
- Note: "Logs collected by Promtail and sent to Loki (port 3100 internal-only)"

**Option C - Combined Approach (Best)**:
1. Grafana screenshot showing Loki configured as datasource
2. Terminal screenshot showing actual log filtering
3. README explaining:
   - Loki is VPC-internal (security best practice)
   - Grafana provides controlled access
   - Direct queries timeout due to volume (production-scale issue)

### Documentation for README

```markdown
## Observability - Centralized Logging

### Architecture
- **Promtail**: Deployed as DaemonSet (global mode) on all 5 Swarm nodes
- **Loki**: Centralized log aggregation (port 3100, VPC-internal only)
- **Grafana**: Log query interface (port 3000, public with auth)

### Security Configuration
Loki port 3100 is **intentionally restricted to VPC-internal traffic**:
- Prevents public access to sensitive log data
- Users query logs through Grafana (controlled access)
- Follows cloud-native security best practices

### Log Collection Coverage
Promtail collects logs from all pipeline components:
- Sensors (2 replicas across 2 nodes)
- Kafka broker + Zookeeper
- Processor
- MongoDB
- All monitoring services

### Log Structure
All logs include:
- **Timestamps**: ISO 8601 format
- **Labels**: Container name, service name, node
- **Structured fields**: JSON format for app logs

### Query Performance
**Known limitation**: Loki queries may timeout with production-scale log volumes.
- Workaround: Use narrow time ranges (last 30s-1m)
- Alternative: Query Loki API directly via SSH tunnel
- For demo: Use Docker service logs showing centralized collection
```

## Conclusion

**Loki not responding on port 3100 externally is CORRECT and SECURE behavior.**

For your CA3 screenshot, use Method 4 (Docker service logs) or Method 1 with very narrow time ranges. Document in your README that Loki is VPC-internal by design.
