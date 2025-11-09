# Docker Swarm Autoscaling Configuration

## Overview

This implements Horizontal Pod Autoscaler (HPA) equivalent functionality for Docker Swarm. Since Docker Swarm lacks native HPA, we use a custom autoscaler service that:

1. **Monitors Prometheus metrics** - Queries Kafka consumer lag every 30 seconds
2. **Makes scaling decisions** - Compares lag against thresholds
3. **Executes via Docker API** - Scales the processor service automatically

## Architecture

```
┌─────────────┐      ┌──────────────┐      ┌─────────────────┐
│  Kafka      │─────▶│  Prometheus  │◀─────│  Autoscaler     │
│  Exporter   │      │              │      │  Service        │
└─────────────┘      └──────────────┘      └────────┬────────┘
                                                     │
                                                     │ Docker API
                                                     ▼
                                            ┌─────────────────┐
                                            │  Processor      │
                                            │  Service        │
                                            │  (1-5 replicas) │
                                            └─────────────────┘
```

## Autoscaling Policy

### Target Service
- **Service**: `plant-monitoring_processor`
- **Metric**: `kafka_consumergroup_lag{consumergroup="plant-care-processor"}`

### Scaling Thresholds
```yaml
Scale Up:
  - Condition: lag > 100 messages
  - Action: Add 1 replica (up to max 5)
  - Cooldown: 60 seconds

Scale Down:
  - Condition: lag < 20 messages  
  - Action: Remove 1 replica (down to min 1)
  - Cooldown: 60 seconds
```

### Replica Limits
- **Minimum**: 1 replica
- **Maximum**: 5 replicas
- **Evaluation Period**: 2 checks (1 minute)

## Deployment

### Prerequisites
1. Monitoring stack deployed (`docker stack ls | grep monitoring`)
2. Prometheus accessible and scraping Kafka exporter
3. Running on manager node

### Deploy Autoscaler
```bash
bash deploy-autoscaler.sh
```

This creates the `autoscaler` stack with a service that:
- Runs on manager node (needs Docker API access)
- Queries Prometheus every 30 seconds
- Logs scaling decisions
- Persists across manager node restarts

### Verify Deployment
```bash
# Check autoscaler service
docker service ls | grep autoscaler

# Watch autoscaler logs
docker service logs -f autoscaler_simple-autoscaler

# Expected output:
# === Autoscaler Check Thu Nov  7 21:00:00 UTC 2025 ===
# Current lag: 45 messages, Current replicas: 1
# ✓ No scaling needed
```

## Load Testing

### Generate Load (Trigger Scale-Up)
```bash
# Add 10 sensors to create load
bash add-sensors.sh 10

# Monitor the autoscaler response
docker service logs -f autoscaler_simple-autoscaler

# Expected:
# Current lag: 150 messages, Current replicas: 1
# ⬆️  Scaling UP: 1 → 2 (lag: 150)
# ...
# Current lag: 120 messages, Current replicas: 2  
# ⬆️  Scaling UP: 2 → 3 (lag: 120)
```

### Watch Scaling Events
```bash
# Terminal 1: Watch service replicas
watch -n 2 'docker service ls | grep processor'

# Terminal 2: Watch autoscaler logs
docker service logs -f autoscaler_simple-autoscaler --since 5m

# Terminal 3: Query Kafka lag
watch -n 5 'curl -s "http://localhost:9090/api/v1/query?query=kafka_consumergroup_lag" | jq -r ".data.result[0].value[1]"'
```

### Reduce Load (Trigger Scale-Down)
```bash
# Remove sensors
bash add-sensors.sh 2

# Wait for lag to clear
sleep 60

# Autoscaler should scale down
# Expected:
# Current lag: 5 messages, Current replicas: 3
# ⬇️  Scaling DOWN: 3 → 2 (lag: 5)
# ...
# Current lag: 0 messages, Current replicas: 2
# ⬇️  Scaling DOWN: 2 → 1 (lag: 0)
```

## Validation & Screenshots

### Evidence for Assignment

1. **Autoscaler Configuration** (`autoscaler-stack.yml`):
   - Equivalent to K8s HPA manifest
   - Shows metric query, thresholds, min/max replicas

2. **Service Scaling Events** (screenshot):
   ```bash
   docker service ls
   # Show processor replicas changing over time
   ```

3. **Autoscaler Logs** (screenshot/text):
   ```bash
   docker service logs autoscaler_simple-autoscaler --tail 100
   # Shows scaling decisions with timestamps
   ```

4. **Grafana Dashboard** (screenshot):
   - Panel 2: Kafka Consumer Lag (spike then drop)
   - Panel 3: Processing Throughput (increase with replicas)
   - Show correlation between lag and replica count

5. **Timeline Demonstration**:
   ```
   Time    | Sensors | Lag    | Replicas | Action
   --------|---------|--------|----------|------------------
   00:00   | 2       | 0      | 1        | Baseline
   01:00   | 10      | 150    | 1        | Load added
   02:00   | 10      | 120    | 2        | Scaled up +1
   03:00   | 10      | 80     | 3        | Scaled up +1
   04:00   | 10      | 30     | 3        | Processing lag
   10:00   | 2       | 5      | 3        | Load removed
   11:00   | 2       | 0      | 2        | Scaled down -1
   12:00   | 2       | 0      | 1        | Scaled down -1
   ```

## Comparison to Kubernetes HPA

### Kubernetes HPA (Reference)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: processor-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: plant-processor
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: External
    external:
      metric:
        name: kafka_consumergroup_lag
        selector:
          matchLabels:
            consumergroup: plant-care-processor
      target:
        type: Value
        value: "100"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 60
```

### Docker Swarm Equivalent (Our Implementation)
```yaml
# autoscaler-stack.yml
services:
  simple-autoscaler:
    image: alpine:latest
    command:
      - Query Prometheus for kafka_consumergroup_lag
      - If lag > 100 and replicas < 5: scale up
      - If lag < 20 and replicas > 1: scale down
      - Sleep 30 seconds, repeat
```

## Troubleshooting

### Autoscaler Not Scaling

1. **Check autoscaler logs**:
   ```bash
   docker service logs autoscaler_simple-autoscaler --tail 50
   ```

2. **Verify Prometheus access**:
   ```bash
   docker exec $(docker ps -q -f name=autoscaler) \
     curl -s http://prometheus:9090/api/v1/query?query=up
   ```

3. **Check Kafka lag metric exists**:
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=kafka_consumergroup_lag'
   ```

4. **Verify Docker socket access**:
   ```bash
   docker service ps autoscaler_simple-autoscaler
   # Should be running on manager node
   ```

### Manual Scaling Override
```bash
# Pause autoscaler
docker service scale autoscaler_simple-autoscaler=0

# Manual scale
docker service scale plant-monitoring_processor=3

# Resume autoscaler
docker service scale autoscaler_simple-autoscaler=1
```

## Cleanup
```bash
# Remove autoscaler
docker stack rm autoscaler

# Reset processor to 1 replica
docker service scale plant-monitoring_processor=1
```

## References

- [Docker Swarm Autoscaling Patterns](https://docs.docker.com/engine/swarm/)
- [Orbiter Autoscaler](https://github.com/gianarb/orbiter)
- [Kubernetes HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
