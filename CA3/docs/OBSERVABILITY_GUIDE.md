# CA3 Observability Setup Guide

Complete guide for deploying and using the observability stack (Loki, Promtail, Prometheus, Grafana) for the Plant Monitoring System.

---

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Deployment](#deployment)
4. [Configuration](#configuration)
5. [Metrics Reference](#metrics-reference)
6. [Dashboard Guide](#dashboard-guide)
7. [Log Queries](#log-queries)
8. [Troubleshooting](#troubleshooting)

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Observability Layer                          │
│                                                                   │
│  ┌──────────┐  ┌───────────┐  ┌────────────┐  ┌──────────┐    │
│  │  Grafana │  │Prometheus │  │    Loki    │  │ Promtail │    │
│  │  :3000   │  │   :9090   │  │   :3100    │  │ DaemonSet│    │
│  │          │  │           │  │            │  │          │    │
│  │ Dashboard│◄─┤  Metrics  │◄─┤    Logs    │◄─┤  Agent   │    │
│  └──────────┘  └───────────┘  └────────────┘  └──────────┘    │
│                       ▲              ▲              ▲            │
└───────────────────────┼──────────────┼──────────────┼───────────┘
                        │              │              │
┌───────────────────────┼──────────────┼──────────────┼───────────┐
│                 Application Services                              │
│                                                                   │
│  ┌──────────┐  ┌───────────┐  ┌────────────┐  ┌──────────┐    │
│  │  Sensor  │  │ Processor │  │   Kafka    │  │ MongoDB  │    │
│  │ :9091/   │  │ :9091/    │  │ Exporter   │  │ Exporter │    │
│  │ metrics  │  │ metrics   │  │  :9308     │  │  :9216   │    │
│  └──────────┘  └───────────┘  └────────────┘  └──────────┘    │
└───────────────────────────────────────────────────────────────────┘
```

### Components

1. **Loki** (Log Aggregation)
   - Collects and indexes logs from all services
   - Retention: 15 days
   - Query language: LogQL
   - Port: 3100

2. **Promtail** (Log Collection)
   - Runs on every node (DaemonSet)
   - Discovers Docker containers automatically
   - Parses JSON logs and extracts labels
   - Sends logs to Loki

3. **Prometheus** (Metrics Collection)
   - Scrapes metrics from instrumented services
   - Service discovery via DNS
   - Retention: 15 days
   - Port: 9090

4. **Grafana** (Visualization)
   - Unified dashboard for logs and metrics
   - Pre-configured data sources
   - 6 key metrics panels
   - Port: 3000
   - Default credentials: admin/admin

---

## ✅ Prerequisites

1. **Operational CA2 Docker Swarm Cluster**
   ```bash
   docker node ls
   # Should show 1 manager + 4 workers
   ```

2. **Plant Monitor Stack Deployed**
   ```bash
   docker stack ls
   # Should show 'plant-monitor' stack
   ```

3. **plant-monitor-net Network**
   ```bash
   docker network ls | grep plant-monitor-net
   # Should exist
   ```

---

## 🚀 Deployment

### Step 1: Rebuild Application Images

The sensor and processor applications have been instrumented with Prometheus metrics. Rebuild the images:

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/applications

# Build sensor image
cd sensor
docker build -t triciab221/plant-sensor:v1.1.0-ca3 .
docker push triciab221/plant-sensor:v1.1.0-ca3

# Build processor image
cd ../processor
docker build -t triciab221/plant-processor:v1.1.0-ca3 .
docker push triciab221/plant-processor:v1.1.0-ca3
```

### Step 2: Update Application Stack

Update the docker-compose.yml image tags to use the new versions:

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC

# Edit docker-compose.yml
# Change:
#   sensor: image: ${DOCKER_REGISTRY:-docker.io/triciab221}/plant-sensor:v1.0.0
#   processor: image: ${DOCKER_REGISTRY:-docker.io/triciab221}/plant-processor:v1.0.0
# To:
#   sensor: image: ${DOCKER_REGISTRY:-docker.io/triciab221}/plant-sensor:v1.1.0-ca3
#   processor: image: ${DOCKER_REGISTRY:-docker.io/triciab221}/plant-processor:v1.1.0-ca3

# Redeploy the application stack
docker stack deploy -c docker-compose.yml plant-monitor
```

### Step 3: Deploy Observability Stack

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC

# Run the deployment script
bash deploy-observability.sh
```

The script will:
- ✅ Check Docker Swarm is active
- ✅ Verify plant-monitor-net network exists
- ✅ Validate all configuration files
- ✅ Deploy the monitoring stack
- ✅ Wait for services to be ready
- ✅ Display access information

### Step 4: Verify Deployment

```bash
# Check all services are running
docker service ls --filter "label=com.docker.stack.namespace=monitoring"

# Expected output:
# NAME                    REPLICAS  IMAGE
# monitoring_grafana      1/1       grafana/grafana:10.2.2
# monitoring_kafka-exporter 1/1     danielqsj/kafka-exporter:v1.7.0
# monitoring_loki         1/1       grafana/loki:2.9.3
# monitoring_mongodb-exporter 1/1   percona/mongodb_exporter:0.40.0
# monitoring_node-exporter 5/5      prom/node-exporter:v1.7.0
# monitoring_prometheus   1/1       prom/prometheus:v2.48.0
# monitoring_promtail     5/5       grafana/promtail:2.9.3

# Check service logs
docker service logs monitoring_grafana --tail 20
docker service logs monitoring_prometheus --tail 20
docker service logs monitoring_loki --tail 20
```

---

## ⚙️ Configuration

### Prometheus Targets

Verify Prometheus is scraping all targets:

1. Open Prometheus: `http://<MANAGER_IP>:9090`
2. Navigate to **Status → Targets**
3. Should see:
   - `prometheus` (self)
   - `plant-sensor` (2 replicas)
   - `plant-processor` (1 replica)
   - `kafka` (kafka-exporter)
   - `mongodb` (mongodb-exporter)
   - `node` (5 nodes)

### Loki Data Source

Grafana should auto-configure Loki, but verify:

1. Open Grafana: `http://<MANAGER_IP>:3000`
2. Go to **Configuration → Data Sources**
3. Should see:
   - **Prometheus** (default) - `http://prometheus:9090`
   - **Loki** - `http://loki:3100`

### Import Dashboard

1. In Grafana, go to **Dashboards → Import**
2. Upload: `/home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC/configs/grafana-plant-monitoring-dashboard.json`
3. Select data source: **Prometheus**
4. Click **Import**

---

## 📊 Metrics Reference

### Sensor Application Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `plant_sensor_readings_total` | Counter | Total sensor readings sent | `plant_id`, `plant_type`, `location` |
| `plant_sensor_readings_per_second` | Gauge | Current reading rate | `plant_id`, `plant_type` |
| `plant_sensor_kafka_errors_total` | Counter | Kafka publish errors | `plant_id`, `error_type` |
| `plant_sensor_soil_moisture` | Gauge | Current soil moisture (%) | `plant_id`, `plant_type` |
| `plant_sensor_light_level` | Gauge | Current light level (lux) | `plant_id`, `plant_type` |
| `plant_sensor_temperature_celsius` | Gauge | Current temperature (°C) | `plant_id`, `plant_type` |
| `plant_sensor_humidity_percent` | Gauge | Current humidity (%) | `plant_id`, `plant_type` |

### Processor Application Metrics

| Metric Name | Type | Description | Labels |
|-------------|------|-------------|--------|
| `plant_processor_messages_processed_total` | Counter | Total messages processed | `plant_id`, `plant_type`, `status` |
| `plant_processor_processing_duration_seconds` | Histogram | Processing time per message | `plant_id`, `operation` |
| `plant_data_pipeline_latency_seconds` | Histogram | End-to-end latency | `plant_id` |
| `plant_kafka_connection_errors_total` | Counter | Kafka connection errors | `error_type` |
| `plant_mongodb_connection_errors_total` | Counter | MongoDB connection errors | `error_type` |
| `plant_mongodb_inserts_per_second` | Gauge | MongoDB insert rate | - |
| `plant_health_score` | Gauge | Plant health score (0-100) | `plant_id`, `plant_type` |
| `plant_alerts_generated_total` | Counter | Alerts generated | `plant_id`, `alert_type`, `severity` |

### Infrastructure Metrics

| Metric Name | Source | Description |
|-------------|--------|-------------|
| `kafka_consumergroup_lag` | kafka-exporter | Consumer lag per topic |
| `mongodb_connections` | mongodb-exporter | Active MongoDB connections |
| `node_cpu_seconds_total` | node-exporter | CPU usage per node |
| `node_memory_MemAvailable_bytes` | node-exporter | Available memory per node |

---

## 📈 Dashboard Guide

### Panel 1: Sensor Data Rate

**Query**: `rate(plant_sensor_readings_total[1m])`

**Purpose**: Monitor sensor data generation rate

**Expected Values**:
- Normal: 0.033 readings/sec (30-second interval)
- With 2 sensors: 0.066 readings/sec total

**Alert Threshold**: < 0.01 (sensors not working)

---

### Panel 2: Kafka Consumer Lag ⭐

**Query**: `kafka_consumergroup_lag{topic="plant-sensors"}`

**Purpose**: **Critical for autoscaling decisions**

**Expected Values**:
- Healthy: 0-10 messages
- Warning: 50-100 messages (yellow)
- Critical: > 100 messages (red, trigger scaling)

**Alert**: Scale up processor when lag > 100 for 2 minutes

---

### Panel 3: Processing Throughput

**Query**: `rate(plant_processor_messages_processed_total{status="success"}[1m])`

**Purpose**: Messages successfully processed per second

**Expected Values**:
- Normal: Should match sensor rate (0.033-0.066 msg/sec)
- High load: Up to 10 msg/sec with scaled sensors

---

### Panel 4: Database Performance

**Queries**:
- `plant_mongodb_inserts_per_second`
- `histogram_quantile(0.95, rate(plant_processor_processing_duration_seconds_bucket{operation="mongodb_insert"}[1m]))`

**Purpose**: MongoDB write performance

**Expected Values**:
- Insert rate: Should match processing throughput
- P95 latency: < 50ms (healthy), > 200ms (overloaded)

---

### Panel 5: End-to-End Pipeline Latency

**Queries**:
- P50: `histogram_quantile(0.50, rate(plant_data_pipeline_latency_seconds_bucket[1m]))`
- P95: `histogram_quantile(0.95, rate(plant_data_pipeline_latency_seconds_bucket[1m]))`
- P99: `histogram_quantile(0.99, rate(plant_data_pipeline_latency_seconds_bucket[1m]))`

**Purpose**: Time from sensor timestamp to processing completion

**Expected Values**:
- P50: 1-3 seconds (normal)
- P95: 5-10 seconds (acceptable)
- P99: < 30 seconds (warning if higher)

---

### Panel 6: Service Availability

**Query**: `up{job=~"plant-sensor|plant-processor|kafka|mongodb|node"}`

**Purpose**: Service health monitoring

**Expected Values**:
- 1 = Service UP (green)
- 0 = Service DOWN (red)

**Alert**: Any service down for > 1 minute

---

## 🔍 Log Queries

### LogQL Query Examples

#### 1. View All Sensor Logs
```logql
{service="plant-sensor"}
```

#### 2. View All Processor Logs
```logql
{service="plant-processor"}
```

#### 3. Filter Errors Across All Services
```logql
{stack="plant-monitor"} |~ "(?i)error"
```

#### 4. Kafka Connection Errors
```logql
{service=~"plant-sensor|plant-processor"} |~ "kafka" |~ "(?i)error"
```

#### 5. MongoDB Errors
```logql
{service="plant-processor"} |~ "mongo" |~ "(?i)error"
```

#### 6. Logs from Specific Plant
```logql
{service="plant-sensor"} |= "plant-001"
```

#### 7. Log Count Rate (Errors/sec)
```logql
sum(rate({stack="plant-monitor"} |~ "(?i)error" [1m]))
```

#### 8. JSON Field Extraction
```logql
{service="plant-processor"} | json | plantId="plant-001"
```

---

## 🛠️ Troubleshooting

### Issue: Prometheus Not Scraping Targets

**Symptoms**: Targets show as "DOWN" in Prometheus

**Solutions**:

1. Check service is running and healthy:
   ```bash
   docker service ps monitoring_prometheus
   docker service logs monitoring_prometheus
   ```

2. Verify DNS resolution:
   ```bash
   docker exec $(docker ps -q -f name=monitoring_prometheus) nslookup tasks.plant-sensor
   ```

3. Test metrics endpoint manually:
   ```bash
   # From manager node
   curl http://$(docker service inspect plant-monitor_sensor -f '{{.Endpoint.VirtualIPs}}' | cut -d'[' -f2 | cut -d']' -f1):9091/metrics
   ```

4. Check Prometheus config:
   ```bash
   docker config inspect monitoring_prometheus-config --pretty
   ```

---

### Issue: Loki Not Receiving Logs

**Symptoms**: No logs in Grafana Explore

**Solutions**:

1. Check Promtail is running on all nodes:
   ```bash
   docker service ps monitoring_promtail
   # Should show 5/5 replicas
   ```

2. Check Promtail logs:
   ```bash
   docker service logs monitoring_promtail --tail 50
   ```

3. Verify Docker socket is accessible:
   ```bash
   docker exec $(docker ps -q -f name=monitoring_promtail) ls -la /var/run/docker.sock
   ```

4. Test Loki API:
   ```bash
   curl http://<MANAGER_IP>:3100/ready
   # Should return "ready"
   ```

---

### Issue: Grafana Dashboard Shows No Data

**Symptoms**: Panels empty or "No data"

**Solutions**:

1. Verify data sources are working:
   - Grafana → Configuration → Data Sources
   - Click "Test" on Prometheus and Loki

2. Check Prometheus has targets:
   - http://<MANAGER_IP>:9090/targets
   - All should be "UP"

3. Run queries directly in Prometheus:
   - http://<MANAGER_IP>:9090/graph
   - Try: `up`
   - Try: `plant_sensor_readings_total`

4. Check time range in dashboard:
   - Top right corner
   - Try "Last 1 hour"

---

### Issue: High Memory Usage

**Symptoms**: Node running out of memory

**Solutions**:

1. Check resource usage:
   ```bash
   docker stats --no-stream
   ```

2. Reduce retention periods (configs/loki-config.yaml):
   ```yaml
   limits_config:
     retention_period: 168h  # 7 days instead of 15
   ```

3. Reduce Prometheus retention (configs/prometheus.yml):
   ```bash
   # In observability-stack.yml, update Prometheus command:
   - '--storage.tsdb.retention.time=7d'
   ```

4. Limit log ingestion rate (configs/promtail-config.yml):
   ```yaml
   limits_config:
     ingestion_rate_mb: 5  # Reduce from 10
   ```

---

## 📝 Next Steps

After observability is working:

1. ✅ **Verify all metrics are being collected**
   - Check Prometheus targets
   - Run sample queries
   - Verify dashboard displays data

2. ✅ **Take screenshots for CA3 submission**
   - Grafana dashboard with live metrics
   - Loki log search filtering errors
   - Service availability panel

3. ✅ **Set up autoscaling**
   - Create load test script
   - Configure scaling rules based on Kafka lag
   - Test scale up/down scenarios

4. ✅ **Implement security hardening**
   - Generate TLS certificates
   - Configure encrypted communication
   - Update network policies

5. ✅ **Perform resilience testing**
   - Container failure (verify 10s restart)
   - Node failure (verify 30-60s migration)
   - Network partition (verify reconnection)
   - Resource exhaustion (verify throttling)

---

## 📚 References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [PromQL Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)
- [LogQL Examples](https://grafana.com/docs/loki/latest/logql/log_queries/)
