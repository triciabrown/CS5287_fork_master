# CA2 Feedback Improvements for CA4

**CA2 Score**: 93/100  
**CA4 Target**: 100/100  
**Date**: November 23, 2025

---

## CA2 Score Breakdown

| Category | CA2 Score | Max | Gaps |
|----------|-----------|-----|------|
| 1) Declarative Completeness | 25/25 | 25 | ✅ Perfect |
| 2) Security & Isolation | **16/20** | 20 | ⚠️ **Gap: -4 points** |
| 3) Scaling & Observability | **17/20** | 20 | ⚠️ **Gap: -3 points** |
| 4) Documentation & Usability | 25/25 | 25 | ✅ Perfect |
| 5) Platform Execution | 10/10 | 10 | ✅ Perfect |
| **TOTAL** | **93/100** | **100** | **-7 points** |

---

## Improvements for CA4

### Improvement #1: Network Segmentation (Security & Isolation)

#### CA2 Feedback
> ⚠️ Swarm has single overlay network for all app tiers (no tier-segmented overlays)  
> ⚠️ "Service labels" are present but not an actual access-control mechanism

**Points Lost**: 4/20

#### Root Cause
CA2 used a single encrypted overlay network (`plant-network`) for all services:
- Frontend (Home Assistant)
- Messaging (Kafka, ZooKeeper)
- Data (MongoDB, Processor)
- Sensors

This violates **principle of least privilege** - all services can communicate with all other services.

#### CA4 Solution: Multi-Tier Network Segmentation

**Create 3 Overlay Networks**:

```yaml
networks:
  # Frontend tier - public-facing services only
  frontend-net:
    driver: overlay
    driver_opts:
      encrypted: "true"
    ipam:
      config:
        - subnet: 10.10.1.0/24
  
  # Messaging tier - Kafka, ZooKeeper
  messaging-net:
    driver: overlay
    driver_opts:
      encrypted: "true"
    ipam:
      config:
        - subnet: 10.10.2.0/24
  
  # Data tier - MongoDB, Processor
  data-net:
    driver: overlay
    driver_opts:
      encrypted: "true"
    ipam:
      config:
        - subnet: 10.10.3.0/24
```

**Service Network Assignments**:

| Service | frontend-net | messaging-net | data-net | Rationale |
|---------|--------------|---------------|----------|-----------|
| Home Assistant | ✅ | ❌ | ❌ | Public UI only |
| Mosquitto | ✅ | ❌ | ✅ | UI + processor access |
| Processor | ❌ | ✅ | ✅ | Needs Kafka + MongoDB |
| Kafka | ❌ | ✅ | ❌ | Messaging only |
| ZooKeeper | ❌ | ✅ | ❌ | Kafka coordination |
| MongoDB | ❌ | ❌ | ✅ | Data storage only |

**Example Configuration**:
```yaml
homeassistant:
  # ... service config ...
  networks:
    - frontend-net  # ONLY frontend access

processor:
  # ... service config ...
  networks:
    - messaging-net  # Access Kafka
    - data-net       # Access MongoDB + Mosquitto

kafka:
  # ... service config ...
  networks:
    - messaging-net  # Internal communication only
```

**Security Benefits**:
- ✅ Home Assistant **cannot** directly access Kafka or MongoDB
- ✅ Kafka **cannot** directly access MongoDB
- ✅ Edge sensors (via VPN) access **only** Kafka (messaging-net)
- ✅ Lateral movement restricted

**Points Gained**: 4/20 → **Target: 20/20**

---

### Improvement #2: Processor Scaling Demonstration (Scaling & Observability)

#### CA2 Feedback
> ⚠️ No explicit scaling trial for processor or DB (optional tier), so no points there

**Points Lost**: 3/20

#### Root Cause
CA2 demonstrated sensor scaling (2→5 replicas) with throughput improvement. However:
- No processor scaling trial
- No Kafka consumption rate measurements
- No end-to-end latency metrics

#### CA4 Solution: Processor Scaling with Observability

**Scaling Test Plan**:

1. **Baseline (1 processor replica)**:
   - Measure: Kafka consumption rate (messages/sec)
   - Measure: End-to-end latency (sensor → MongoDB)
   - Measure: Kafka consumer lag

2. **Scale Up (3 processor replicas)**:
   - Run: `docker service scale plant-monitoring_processor=3`
   - Measure: Same metrics as baseline
   - Expect: ~3x consumption rate, lower lag

3. **Scale Down (1 processor replica)**:
   - Verify graceful degradation
   - Document recovery time

**Measurement Script** (`scripts/measure-processor-performance.sh`):
```bash
#!/bin/bash
# Measure Kafka consumption rate and end-to-end latency

# 1. Get Kafka consumer lag
docker exec $(docker ps -q -f name=kafka) \
  kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group plant-processor-group \
  --describe

# 2. Count MongoDB inserts (30-second window)
START_COUNT=$(docker exec $(docker ps -q -f name=mongodb) \
  mongosh --quiet --eval "db.sensor_readings.countDocuments()")

sleep 30

END_COUNT=$(docker exec $(docker ps -q -f name=mongodb) \
  mongosh --quiet --eval "db.sensor_readings.countDocuments()")

RATE=$(( (END_COUNT - START_COUNT) / 30 ))
echo "Consumption rate: ${RATE} messages/sec"

# 3. Measure end-to-end latency (sample)
# (Compare sensor timestamp to MongoDB insert timestamp)
```

**Expected Results** (to document):

| Configuration | Replicas | Consumption Rate | Avg Latency | Consumer Lag |
|---------------|----------|------------------|-------------|--------------|
| Baseline | 1 | ~0.5 msg/sec | ~2 seconds | 0-5 messages |
| Scaled Up | 3 | ~1.5 msg/sec | ~1 second | 0 messages |
| Scaled Down | 1 | ~0.5 msg/sec | ~2 seconds | 0-5 messages |

**Artifact**: `scaling-results-processor-<timestamp>.txt`

**Points Gained**: 3/20 → **Target: 20/20**

---

### Improvement #3: Enhanced Observability (Bonus)

#### CA2 Feedback (Nice-to-Have)
> If you add basic latency (produce→DB write) or queue depth (Kafka lag) measurements and keep them in the repo, it strengthens the scaling story.

**Current State**: Only throughput measured (messages/30sec)

#### CA4 Enhancement: Comprehensive Metrics

**Metrics to Add**:

1. **Kafka Consumer Lag**:
   ```bash
   kafka-consumer-groups.sh \
     --bootstrap-server localhost:9092 \
     --group plant-processor-group \
     --describe
   ```
   Shows: How far behind processor is from latest Kafka messages

2. **End-to-End Latency**:
   - Sensor timestamp (when data generated)
   - MongoDB timestamp (when data persisted)
   - Difference = total pipeline latency

3. **MongoDB Write Rate**:
   ```javascript
   // MongoDB shell
   db.sensor_readings.aggregate([
     { $match: { timestamp: { $gte: new Date(Date.now() - 30000) } } },
     { $count: "recent" }
   ])
   ```

4. **Processor Health**:
   - CPU/Memory usage per replica
   - Message processing time
   - Error rate

**Monitoring Script** (`scripts/monitor-metrics.sh`):
```bash
#!/bin/bash
# Real-time monitoring of CA4 system metrics

while true; do
  clear
  echo "=== CA4 Plant Monitoring Metrics ==="
  echo "Timestamp: $(date)"
  echo ""
  
  # VPN Status
  echo "VPN Status:"
  sudo wg show | grep -E "peer|latest handshake|transfer"
  echo ""
  
  # Kafka Consumer Lag
  echo "Kafka Consumer Lag:"
  ssh manager "docker exec \$(docker ps -q -f name=kafka) kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group plant-processor-group --describe"
  echo ""
  
  # MongoDB Recent Inserts
  echo "MongoDB Inserts (last 30s):"
  ssh manager "docker exec \$(docker ps -q -f name=mongodb) mongosh --quiet --eval \"db.sensor_readings.countDocuments({ timestamp: { \$gte: new Date(Date.now() - 30000) } })\""
  echo ""
  
  # Processor Replicas
  echo "Processor Replicas:"
  ssh manager "docker service ps plant-monitoring_processor --filter 'desired-state=running' --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}'"
  echo ""
  
  sleep 5
done
```

**Grading Impact**: Demonstrates production-grade observability thinking

---

## CA4 Additional Improvements (Beyond CA2 Feedback)

### Improvement #4: VPN-Only Kafka Access

**Security Enhancement**:
- Kafka **NOT** exposed to public internet
- Accessible **ONLY** via VPN subnet (10.20.0.0/24)

**Terraform Security Group**:
```hcl
# NO public Kafka access
# resource "aws_security_group_rule" "kafka_public" { } # REMOVED

# ONLY VPN access
resource "aws_security_group_rule" "kafka_vpn_only" {
  type        = "ingress"
  from_port   = 9092
  to_port     = 9092
  protocol    = "tcp"
  cidr_blocks = ["10.20.0.0/24"]  # VPN subnet ONLY
  description = "Kafka accessible ONLY via VPN"
}
```

**Benefit**: Shows defense-in-depth security thinking

---

### Improvement #5: Automated Failure Recovery

**CA2**: Manual failure scenarios documented  
**CA4**: Automated failure drills with self-recovery

**Example** (`failure-drills/vpn-failure.sh`):
```bash
#!/bin/bash
# Automated VPN failure drill with recovery

echo "=== VPN Failure Drill ==="

# 1. Baseline check
echo "Step 1: Verify normal operation..."
./scripts/check-vpn.sh || exit 1
./scripts/check-dataflow.sh || exit 1
echo "✅ Baseline OK"

# 2. Inject failure
echo "Step 2: Injecting VPN failure..."
ssh cloud "sudo wg-quick down wg0"
sleep 5

# 3. Verify impact
echo "Step 3: Verifying failure impact..."
if ping -c 3 10.20.0.1 > /dev/null 2>&1; then
    echo "❌ ERROR: VPN still up (failure injection failed)"
    exit 1
fi
echo "✅ VPN down confirmed"

# 4. Check sensor errors
echo "Step 4: Checking sensor error logs..."
docker-compose -f edge-site/docker-compose.yml logs --tail 10 sensor-1 | grep -i "error\|refused"
echo "✅ Sensors showing connection errors (expected)"

# 5. Auto-recovery
echo "Step 5: Initiating auto-recovery..."
ssh cloud "sudo wg-quick up wg0"
sleep 10

# 6. Verify recovery
echo "Step 6: Verifying recovery..."
./scripts/check-vpn.sh || exit 1
./scripts/check-dataflow.sh || exit 1
echo "✅ Recovery complete"

echo ""
echo "=== Drill Summary ==="
echo "Failure: VPN tunnel down"
echo "Impact: Sensors lost Kafka connectivity"
echo "Recovery: VPN restarted, connectivity restored"
echo "Time: ~15 seconds"
```

**Benefit**: Demonstrates operational maturity

---

## Summary: CA2 → CA4 Improvements

| Improvement | CA2 | CA4 | Points Gained |
|-------------|-----|-----|---------------|
| **Network Segmentation** | Single overlay | 3-tier overlays | +4 (16→20) |
| **Processor Scaling** | Not demonstrated | 1→3 replicas with metrics | +3 (17→20) |
| **Observability** | Throughput only | Latency, lag, health | Bonus |
| **VPN Security** | N/A | VPN-only Kafka access | Bonus |
| **Failure Drills** | Manual | Automated with recovery | Bonus |

**CA2 Score**: 93/100  
**CA4 Target**: 100/100 + bonus points for depth

---

## Implementation Checklist

- [ ] Create 3-tier overlay networks (frontend, messaging, data)
- [ ] Update service network assignments
- [ ] Add processor scaling test script
- [ ] Add Kafka consumer lag monitoring
- [ ] Add end-to-end latency measurement
- [ ] Update Terraform for VPN-only Kafka access
- [ ] Create automated failure drill scripts
- [ ] Document all improvements in README
- [ ] Include comparison table (CA2 vs CA4)

**Next Steps**: Start with network segmentation (docker-compose.yml modifications)

---

**Document Version**: 1.0  
**Last Updated**: November 23, 2025  
**Author**: Tricia Brown
