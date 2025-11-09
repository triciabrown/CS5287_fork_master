# CA3 Deployment - Start Here

**Status**: ✅ Ready to Deploy with CA2 Feedback Improvements  
**Time Required**: 45-60 minutes total

---

## 🎯 What's New in CA3

✅ **3 isolated networks** (frontnet, messagenet, datanet) - addresses CA2 feedback  
✅ **Minimal published ports** (only UI + observability) - addresses CA2 feedback  
✅ **Instrumented applications** (15 custom metrics for observability)  
✅ **Processor scaling test** (1→3 replicas with performance metrics) - addresses CA2 feedback  
✅ **Complete observability stack** (Loki, Promtail, Prometheus, Grafana)  

---

## 🚀 Deployment Steps

### Step 1: Build New Docker Images (10 minutes)

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/applications

# Build sensor with Prometheus metrics
cd sensor
docker build -t triciab221/plant-sensor:v1.1.0-ca3 .
docker push triciab221/plant-sensor:v1.1.0-ca3

# Build processor with Prometheus metrics
cd ../processor
docker build -t triciab221/plant-processor:v1.1.0-ca3 .
docker push triciab221/plant-processor:v1.1.0-ca3

# Verify images
docker images | grep v1.1.0-ca3
```

**Expected output**:
```
triciab221/plant-sensor     v1.1.0-ca3
triciab221/plant-processor  v1.1.0-ca3
```

---

### Step 2: Deploy CA3 Infrastructure (15-20 minutes)

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC

# Run the deployment script
bash deploy.sh
```

**What happens**:
1. Provisions AWS infrastructure (if needed)
2. Initializes Docker Swarm (1 manager + 4 workers)
3. Creates 3 encrypted overlay networks:
   - **frontnet** (Home Assistant + MQTT)
   - **messagenet** (Kafka + Sensors)
   - **datanet** (MongoDB + Processor)
4. Deploys 7 application services
5. Runs smoke tests

**Wait for**: All services to show `X/X` in `docker service ls`

---

### Step 3: Deploy Observability Stack (5-10 minutes)

```bash
# Still in plant-monitor-swarm-IaC directory
bash deploy-observability.sh
```

**What happens**:
1. Validates prerequisites (Swarm active, networks exist)
2. Deploys 7 monitoring services:
   - Loki (log aggregation)
   - Promtail (log collection)
   - Prometheus (metrics)
   - Grafana (dashboards)
   - Kafka Exporter
   - MongoDB Exporter
   - Node Exporter
3. Waits for services to be ready
4. Displays access URLs

**Expected output**:
```
✅ All services are running

Grafana: http://<MANAGER_IP>:3000
  Username: admin
  Password: admin

Prometheus: http://<MANAGER_IP>:9090
Loki: http://<MANAGER_IP>:3100
```

---

### Step 4: Configure Grafana (5 minutes)

1. **Access Grafana**: http://<MANAGER_IP>:3000
2. **Login**: admin / admin (change password)
3. **Import Dashboard**:
   - Click **+** → **Import**
   - Upload: `/home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC/configs/grafana-plant-monitoring-dashboard.json`
   - Select data source: **Prometheus**
   - Click **Import**

4. **Verify Data Flowing**:
   - Panel 1: Sensor data rate > 0
   - Panel 2: Kafka consumer lag visible
   - Panel 6: All services = 1 (green)

---

### Step 5: Run Processor Scaling Test (5 minutes)

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC

# Run the scaling test (addresses CA2 feedback!)
bash load-test-processor.sh
```

**What happens**:
1. Measures baseline (1 replica):
   - Kafka consumer lag
   - Processing throughput
   - Pipeline latency P95
   - MongoDB insert rate

2. Scales to 3 replicas

3. Measures scaled performance

4. Calculates improvements

5. Generates report: `processor-scaling-results-ca3.txt`

**Expected improvements**:
- ✅ Kafka consumer lag: -60% to -80% (lower is better)
- ✅ Processing throughput: +150% to +200% (higher is better)
- ✅ Pipeline latency: -40% to -60% (lower is better)

---

### Step 6: Verification (5 minutes)

#### Verify Network Isolation ✨ NEW

```bash
# List networks (should see 3 encrypted overlays)
docker network ls --filter driver=overlay

# Inspect network assignments
docker service inspect plant-monitor_processor --format '{{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}'
# Expected: messagenet datanet

docker service inspect plant-monitor_sensor --format '{{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}'
# Expected: messagenet only

docker service inspect plant-monitor_homeassistant --format '{{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}'
# Expected: frontnet only
```

#### Verify Minimal Port Exposure ✨ NEW

```bash
# Check published ports
docker service ls --format "table {{.Name}}\t{{.Ports}}"

# Should see:
# - homeassistant: *:8123->8123/tcp (user UI)
# - grafana: *:3000->3000/tcp (observability)
# - prometheus: *:9090->9090/tcp (observability)
# - sensor/processor: host mode :9091/9092 (metrics only)
# - kafka, mongodb, zookeeper: NO PUBLISHED PORTS ✅
```

#### Verify Observability

```bash
# Check Prometheus targets (all should be "UP")
curl http://<MANAGER_IP>:9090/targets

# Test metrics endpoints
curl http://<MANAGER_IP>:9091/metrics | grep plant_sensor
curl http://<MANAGER_IP>:9092/metrics | grep plant_processor

# Check Loki is receiving logs
curl http://<MANAGER_IP>:3100/ready
# Expected: "ready"
```

---

## 📸 Capture Evidence for Submission

### 1. Network Isolation (NEW - addresses CA2 feedback)

```bash
# Screenshot 1: Three networks
docker network ls --filter driver=overlay
# Save as: screenshots/network-isolation-ca3.png

# Screenshot 2: Service network assignments
for svc in processor sensor homeassistant; do
  echo "$svc:"
  docker service inspect plant-monitor_$svc --format '{{range .Spec.TaskTemplate.Networks}}  - {{.Target}}{{end}}'
done
# Save as: screenshots/service-networks-ca3.png
```

### 2. Minimal Port Exposure (NEW - addresses CA2 feedback)

```bash
# Screenshot 3: Published ports
docker service ls
# Save as: screenshots/minimal-ports-ca3.png
```

### 3. Grafana Dashboard

- Open: http://<MANAGER_IP>:3000
- Navigate to imported dashboard
- Ensure all 6 core panels show data
- Screenshot: `screenshots/grafana-dashboard-ca3.png`

### 4. Key Metrics Panels

- **Panel 2: Kafka Consumer Lag** (critical for autoscaling)
  - Screenshot: `screenshots/kafka-consumer-lag-ca3.png`

- **Panel 5: Pipeline Latency P50/P95/P99** (NEW - addresses CA2 feedback)
  - Screenshot: `screenshots/pipeline-latency-ca3.png`

### 5. Loki Log Search

- Grafana → Explore → Loki
- Query: `{stack="plant-monitor"} |~ "(?i)error"`
- Screenshot: `screenshots/loki-log-search-ca3.png`

### 6. Processor Scaling Results (NEW - addresses CA2 feedback)

```bash
# Copy results file for submission
cat processor-scaling-results-ca3.txt
# Screenshot: `screenshots/processor-scaling-results-ca3.png`
```

---

## ✅ Submission Checklist

### Required Files

- [ ] `docker-compose.yml` (with 3 networks)
- [ ] `observability-stack.yml` (monitoring services)
- [ ] `load-test-processor.sh` (scaling test)
- [ ] `processor-scaling-results-ca3.txt` (test output)
- [ ] `applications/sensor/sensor.js` (instrumented)
- [ ] `applications/processor/app.js` (instrumented)

### Required Documentation

- [ ] `README.md` (CA3 assignment overview)
- [ ] `docs/NETWORK_ISOLATION.md` (NEW - addresses CA2 feedback)
- [ ] `docs/OBSERVABILITY_GUIDE.md` (metrics reference)
- [ ] `CA3_IMPROVEMENTS_CA2_FEEDBACK.md` (NEW - shows feedback addressed)
- [ ] `CA3_OBSERVABILITY_IMPLEMENTATION.md` (technical details)

### Required Screenshots

- [ ] Network isolation (3 overlays)
- [ ] Service network assignments
- [ ] Minimal published ports
- [ ] Grafana dashboard (all 6 core panels)
- [ ] Kafka consumer lag panel
- [ ] Pipeline latency panel (P50/P95/P99)
- [ ] Loki log search (error filtering)
- [ ] Processor scaling results
- [ ] Prometheus targets (all UP)
- [ ] Service availability panel

---

## 🐛 Quick Troubleshooting

### Services Not Starting

```bash
# Check service status
docker service ps <SERVICE_NAME> --no-trunc

# Check logs
docker service logs <SERVICE_NAME> --tail 50

# Check node resources
docker node ls
```

### Metrics Not Showing in Grafana

```bash
# Check Prometheus targets
curl http://<MANAGER_IP>:9090/targets

# Test metrics endpoints
docker exec $(docker ps -q -f name=plant-monitor_sensor) curl localhost:9091/metrics

# Check Prometheus config
docker config inspect monitoring_prometheus-config --pretty
```

### Network Isolation Test Failing

```bash
# Test that sensor CANNOT reach MongoDB (should fail)
SENSOR_CONTAINER=$(docker ps -q -f name=plant-monitor_sensor)
docker exec $SENSOR_CONTAINER ping -c 1 mongodb
# Expected: Network unreachable

# Test that processor CAN reach both Kafka and MongoDB (should succeed)
PROC_CONTAINER=$(docker ps -q -f name=plant-monitor_processor)
docker exec $PROC_CONTAINER nc -zv kafka 9092  # Should succeed
docker exec $PROC_CONTAINER nc -zv mongodb 27017  # Should succeed
```

---

## 🎯 Success Criteria

### ✅ Deployment Successful When:

1. **Infrastructure**:
   - 5 Docker Swarm nodes (1 manager + 4 workers)
   - 3 encrypted overlay networks created
   - All 7 application services running (X/X)
   - All 7 observability services running (X/X)

2. **Network Isolation** ✨ NEW:
   - Home Assistant only on frontnet
   - Sensors only on messagenet
   - Processor bridging messagenet + datanet
   - Internal services NOT accessible externally

3. **Observability**:
   - Grafana accessible with dashboard
   - All 6 core panels showing data
   - Prometheus scraping all targets (UP)
   - Loki receiving logs from all services

4. **Scaling** ✨ NEW:
   - Processor scales 1 → 3 replicas
   - Metrics show improvement:
     * Lower Kafka lag
     * Higher throughput
     * Lower latency
   - Results saved to file

---

## 🎓 How This Addresses CA2 Feedback

| CA2 Feedback | CA3 Implementation | Evidence |
|--------------|-------------------|----------|
| "Finer network isolation" | 3 overlays (frontnet, messagenet, datanet) | `docker network ls` + `docs/NETWORK_ISOLATION.md` |
| "Internal-only services" | Kafka, MongoDB, ZooKeeper no published ports | `docker service ls` (ports column) |
| "Optional tier scaling" | Processor 1→3 with metrics | `load-test-processor.sh` + results file |
| "Latency measurements" | P50/P95/P99 pipeline latency | Panel 5 in Grafana |
| "Queue depth" | Kafka consumer lag | Panel 2 in Grafana |

---

## 📞 Next Steps After Deployment

1. **Week 1**: ✅ Complete observability + scaling test
2. **Week 2**: Security hardening (TLS encryption)
3. **Week 3**: Resilience testing (failure injection)
4. **Week 4**: Final documentation and submission

---

**Ready to deploy!** Start with Step 1: Build Docker images.

**Questions?** See:
- `QUICK_DEPLOY.md` - Observability-only deployment
- `CA3_IMPROVEMENTS_CA2_FEEDBACK.md` - Detailed feedback implementation
- `docs/OBSERVABILITY_GUIDE.md` - Metrics and queries reference
- `docs/NETWORK_ISOLATION.md` - Network architecture details

**Date**: November 2, 2024  
**Status**: ✅ Ready for Production Deployment
