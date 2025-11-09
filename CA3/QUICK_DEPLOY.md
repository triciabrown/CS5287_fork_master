# CA3 Observability - Quick Deployment Guide

**Status**: Ready to Deploy  
**Time Required**: 30 minutes

---

## 🚀 Deployment Steps

### 1. Build New Images (10 minutes)

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/applications

# Build and push sensor image
cd sensor
docker build -t triciab221/plant-sensor:v1.1.0-ca3 .
docker push triciab221/plant-sensor:v1.1.0-ca3

# Build and push processor image
cd ../processor
docker build -t triciab221/plant-processor:v1.1.0-ca3 .
docker push triciab221/plant-processor:v1.1.0-ca3
```

### 2. Update Image Tags (1 minute)

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC

# Edit docker-compose.yml, lines 226 and 187:
# Change: plant-sensor:v1.0.0 → plant-sensor:v1.1.0-ca3
# Change: plant-processor:v1.0.0 → plant-processor:v1.1.0-ca3
```

### 3. Redeploy Application Stack (5 minutes)

```bash
# From manager node
docker stack deploy -c docker-compose.yml plant-monitor

# Wait for services to update
watch docker service ls
# Wait until all show X/X (converged)
```

### 4. Deploy Observability Stack (5 minutes)

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC
bash deploy-observability.sh

# The script will:
# - Validate prerequisites
# - Deploy monitoring stack
# - Wait for services to be ready
# - Display access URLs
```

### 5. Access Grafana (2 minutes)

```bash
# Get manager IP
MANAGER_IP=$(docker node inspect self --format '{{.Status.Addr}}')
echo "Grafana: http://${MANAGER_IP}:3000"
```

Open in browser:
- URL: http://<MANAGER_IP>:3000
- Username: `admin`
- Password: `admin`
- (Change password on first login)

### 6. Import Dashboard (2 minutes)

In Grafana:
1. Click **+** → **Import**
2. Click **Upload JSON file**
3. Select: `/home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC/configs/grafana-plant-monitoring-dashboard.json`
4. Select data source: **Prometheus**
5. Click **Import**

### 7. Verify Metrics (5 minutes)

Check Prometheus targets:
```bash
MANAGER_IP=$(docker node inspect self --format '{{.Status.Addr}}')
echo "Prometheus: http://${MANAGER_IP}:9090/targets"
```

All should show "UP":
- ✅ prometheus
- ✅ plant-sensor (2 targets)
- ✅ plant-processor (1 target)
- ✅ kafka
- ✅ mongodb
- ✅ node (5 targets)

### 8. Test Metrics Endpoints (2 minutes)

```bash
# Get a sensor container IP
SENSOR_IP=$(docker service inspect plant-monitor_sensor \
  --format '{{range .Endpoint.VirtualIPs}}{{.Addr}}{{end}}' | cut -d'/' -f1)

# Test sensor metrics
curl http://${SENSOR_IP}:9091/metrics | grep plant_sensor

# Test processor metrics (different port externally)
PROCESSOR_IP=$(docker service inspect plant-monitor_processor \
  --format '{{range .Endpoint.VirtualIPs}}{{.Addr}}{{end}}' | cut -d'/' -f1)
curl http://${PROCESSOR_IP}:9091/metrics | grep plant_processor
```

### 9. Test Log Collection (2 minutes)

In Grafana:
1. Click **Explore** (compass icon)
2. Select data source: **Loki**
3. Enter query: `{service="plant-sensor"}`
4. Click **Run query**
5. Should see sensor logs

Try filtering errors:
```logql
{stack="plant-monitor"} |~ "(?i)error"
```

---

## ✅ Verification Checklist

- [ ] Docker images built and pushed (v1.1.0-ca3)
- [ ] Application stack updated and redeployed
- [ ] Observability stack deployed (7 services)
- [ ] All services running (docker service ls)
- [ ] Grafana accessible (http://<MANAGER_IP>:3000)
- [ ] Dashboard imported and displaying data
- [ ] Prometheus targets all "UP"
- [ ] Metrics endpoints responding
- [ ] Loki receiving logs
- [ ] All 6 core panels showing data

---

## 📊 Expected Dashboard Values

### Panel 1: Sensor Data Rate
- **Expected**: 0.033 - 0.066 readings/sec (30s interval × 2 sensors)
- **Alert**: < 0.01 (sensors down)

### Panel 2: Kafka Consumer Lag ⭐
- **Expected**: 0-10 messages (healthy)
- **Warning**: 50-100 messages (yellow)
- **Critical**: > 100 messages (red, scale up)

### Panel 3: Processing Throughput
- **Expected**: 0.033 - 0.066 msg/sec (matches sensor rate)
- **Color**: Green if > 0.5 msg/sec

### Panel 4: Database Performance
- **Insert Rate**: Should match processing throughput
- **P95 Latency**: < 50ms (healthy), < 200ms (acceptable)

### Panel 5: Pipeline Latency
- **P50**: 1-3 seconds
- **P95**: 5-10 seconds
- **P99**: < 30 seconds

### Panel 6: Service Availability
- **Expected**: All services = 1 (green)
- **Alert**: Any service = 0 (red)

---

## 🐛 Quick Troubleshooting

### No Metrics in Dashboard

```bash
# Check Prometheus targets
curl http://<MANAGER_IP>:9090/targets

# Check sensor metrics endpoint
docker service ps plant-monitor_sensor
# Get a task node, SSH to it
curl localhost:9091/metrics

# Check Prometheus logs
docker service logs monitoring_prometheus --tail 50
```

### No Logs in Loki

```bash
# Check Promtail is running on all nodes
docker service ps monitoring_promtail
# Should show 5/5 replicas

# Check Promtail logs
docker service logs monitoring_promtail --tail 50

# Test Loki API
curl http://<MANAGER_IP>:3100/ready
# Should return "ready"
```

### Service Won't Start

```bash
# Check service status
docker service ps <SERVICE_NAME> --no-trunc

# Check logs
docker service logs <SERVICE_NAME> --tail 100

# Check node resources
docker node ls
ssh <NODE_IP>
free -h
df -h
```

---

## 📸 Screenshot Checklist (for CA3 submission)

Capture these after deployment:

1. **Grafana Dashboard - Full View**
   - All 6 core panels visible
   - Data flowing (not "No data")
   - Timestamp showing current time
   - Save as: `screenshots/grafana-dashboard-ca3.png`

2. **Loki Log Search - Error Filtering**
   - Query: `{stack="plant-monitor"} |~ "(?i)error"`
   - Multiple log entries visible
   - Save as: `screenshots/loki-log-search-ca3.png`

3. **Prometheus Targets - All UP**
   - Navigate to: http://<MANAGER_IP>:9090/targets
   - All targets showing "UP" status
   - Save as: `screenshots/prometheus-targets-ca3.png`

4. **Kafka Consumer Lag Panel - Close-up**
   - Panel 2 enlarged
   - Threshold lines visible
   - Save as: `screenshots/kafka-consumer-lag-ca3.png`

5. **Service Availability Panel - Close-up**
   - Panel 6 enlarged
   - All services green (UP)
   - Save as: `screenshots/service-availability-ca3.png`

---

## 📚 Next Steps After Observability

Once observability is working:

### Week 1: Complete Observability
- ✅ Deploy stack
- ✅ Verify metrics
- ✅ Capture screenshots
- ✅ Test log queries

### Week 2: Autoscaling (20%)
- Create load test script
- Monitor Kafka consumer lag
- Implement scaling triggers
- Test scale up/down

### Week 3: Security Hardening (20%)
- Generate TLS certificates
- Configure encrypted communication
- Update network policies
- Document security config

### Week 4: Resilience Testing (25%)
- Create test scenarios
- Execute failure injections
- Record recovery videos
- Write operator playbook

### Week 5: Final Documentation (10%)
- Update README
- Create submission package
- Final testing
- Submit CA3

---

## 🆘 Help Resources

- **Observability Guide**: `docs/OBSERVABILITY_GUIDE.md` (500+ lines)
- **Implementation Summary**: `CA3_OBSERVABILITY_IMPLEMENTATION.md` (800+ lines)
- **CA3 README**: `README.md` (main assignment overview)

---

**Ready to deploy!** 🚀

Start with Step 1: Build new images.
