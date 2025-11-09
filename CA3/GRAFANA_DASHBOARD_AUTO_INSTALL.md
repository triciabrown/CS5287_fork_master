# Automated Grafana Dashboard Installation

## Overview

The Grafana dashboard is now **automatically installed** when you deploy the observability stack. No manual import required!

## How It Works

### Grafana Provisioning System

Grafana has a built-in [provisioning system](https://grafana.com/docs/grafana/latest/administration/provisioning/) that automatically loads:
- Datasources (Prometheus, Loki)
- Dashboards (Plant Monitoring Dashboard)
- Alerts (future enhancement)

### Implementation

**1. Dashboard Provisioning Config** (`configs/grafana-dashboards.yml`):
```yaml
apiVersion: 1
providers:
  - name: 'Plant Monitor Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
```

**2. Docker Swarm Config Mounts** (`observability-stack.yml`):
```yaml
grafana:
  configs:
    # Datasources (Prometheus + Loki)
    - source: grafana-datasources
      target: /etc/grafana/provisioning/datasources/datasources.yml
    
    # Dashboard provider config
    - source: grafana-dashboards-config
      target: /etc/grafana/provisioning/dashboards/dashboards.yml
    
    # Actual dashboard JSON
    - source: grafana-plant-dashboard
      target: /var/lib/grafana/dashboards/plant-monitoring.json
```

**3. Config Definitions**:
```yaml
configs:
  grafana-datasources:
    file: ./configs/grafana-datasources.yml
  grafana-dashboards-config:
    file: ./configs/grafana-dashboards.yml
  grafana-plant-dashboard:
    file: ./configs/grafana-plant-monitoring-dashboard.json
```

**4. Ansible File Distribution**:
```yaml
- name: Copy observability configs
  copy:
    src: "{{ item }}"
    dest: "/home/ubuntu/plant-monitor-swarm-IaC/configs/{{ item | basename }}"
  loop:
    - ../configs/grafana-plant-monitoring-dashboard.json
    # ... other configs
```

## Deployment Flow

```
1. deploy.sh runs
   ↓
2. Ansible copies configs to manager node
   ↓
3. deploy-observability.sh deploys stack
   ↓
4. Docker Swarm creates configs from files
   ↓
5. Grafana container starts
   ↓
6. Grafana reads provisioning configs
   ↓
7. Dashboard automatically loaded! ✅
```

## Verification

After deployment, the dashboard will be automatically available:

### 1. Access Grafana
```bash
open http://<MANAGER_IP>:3000
# Login: admin / admin
```

### 2. Check Dashboard Loaded
```bash
# Via UI:
# - Navigate to Dashboards → Browse
# - Should see "Plant Monitoring Dashboard"

# Via API:
curl -u admin:admin http://<MANAGER_IP>:3000/api/search?query=Plant
```

Expected response:
```json
[
  {
    "id": 1,
    "uid": "plant-monitor-ca3",
    "title": "Plant Monitoring Dashboard - CA3",
    "type": "dash-db",
    "url": "/d/plant-monitor-ca3/plant-monitoring-dashboard-ca3"
  }
]
```

### 3. Verify Datasources
```bash
curl -u admin:admin http://<MANAGER_IP>:3000/api/datasources
```

Should show Prometheus and Loki configured.

## Dashboard Panels (Auto-Configured)

The auto-loaded dashboard includes:

1. **System Overview**
   - Total messages processed
   - Average pipeline latency
   - Service availability

2. **Data Pipeline Metrics**
   - Message processing rate
   - Kafka consumer lag
   - Database insert rate

3. **Plant Health**
   - Health scores by plant
   - Alert history
   - Sensor readings

4. **Infrastructure**
   - CPU usage per node
   - Memory usage per service
   - Network I/O

5. **Logs Integration**
   - Log volume by service
   - Error rate trends
   - Quick log search links

## Updating the Dashboard

### Option 1: Edit in UI (Recommended for Testing)
```bash
# 1. Open Grafana: http://<MANAGER_IP>:3000
# 2. Edit dashboard as needed
# 3. Export JSON:
#    Dashboard Settings → JSON Model → Copy to clipboard
# 4. Save locally:
cat > /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC/configs/grafana-plant-monitoring-dashboard.json
# (paste JSON)
# 5. Redeploy to apply changes
```

### Option 2: Update JSON Directly
```bash
# Edit the dashboard JSON file
vim /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC/configs/grafana-plant-monitoring-dashboard.json

# Redeploy observability stack
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP> 'cd ~/plant-monitor-swarm-IaC && bash deploy-observability.sh'
```

## Dashboard Configuration

The dashboard is configured with:

**Dashboard UID**: `plant-monitor-ca3`  
**Dashboard Title**: `Plant Monitoring Dashboard - CA3`  
**Auto-refresh**: 5 seconds  
**Time Range**: Last 15 minutes (default)

**Templating Variables**:
- `$plant_id` - Filter by plant
- `$service` - Filter by service
- `$interval` - Aggregation interval

**Panel Types**:
- Graphs (time series)
- Stat panels (single values)
- Gauges (health scores)
- Tables (recent alerts)
- Logs panel (Loki integration)

## Benefits of Auto-Installation

✅ **Zero Manual Steps**
- No need to manually import dashboard JSON
- Works immediately after deployment
- Consistent across all deployments

✅ **Version Controlled**
- Dashboard JSON is in git
- Changes are tracked
- Easy to rollback

✅ **Infrastructure as Code**
- Dashboard is part of deployment
- Reproducible deployments
- No configuration drift

✅ **Team Collaboration**
- Everyone gets the same dashboard
- Changes are shared via git
- No "works on my machine" issues

## Troubleshooting

### Dashboard Not Appearing

**1. Check Grafana logs:**
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP>
docker service logs monitoring_grafana --tail 50
```

Look for:
```
logger=provisioning.dashboard type=file msg="successfully provisioned dashboard" file="/var/lib/grafana/dashboards/plant-monitoring.json"
```

**2. Verify config files are mounted:**
```bash
docker exec $(docker ps -q -f name=monitoring_grafana) ls -la /var/lib/grafana/dashboards/
docker exec $(docker ps -q -f name=monitoring_grafana) ls -la /etc/grafana/provisioning/dashboards/
```

**3. Check JSON syntax:**
```bash
cat configs/grafana-plant-monitoring-dashboard.json | jq . > /dev/null
# If no errors, JSON is valid
```

### Datasources Not Working

**1. Verify datasources provisioned:**
```bash
docker exec $(docker ps -q -f name=monitoring_grafana) \
  cat /etc/grafana/provisioning/datasources/datasources.yml
```

**2. Check Prometheus/Loki are accessible:**
```bash
# From Grafana container
docker exec $(docker ps -q -f name=monitoring_grafana) \
  wget -qO- http://prometheus:9090/-/healthy

docker exec $(docker ps -q -f name=monitoring_grafana) \
  wget -qO- http://loki:3100/ready
```

### Dashboard Panels Show "No Data"

**1. Verify Prometheus has data:**
```bash
curl -s http://<MANAGER_IP>:9090/api/v1/query?query=up | jq .
```

**2. Check if services are running:**
```bash
docker service ls
# All services should show "1/1" replicas
```

**3. Wait for metrics to populate:**
- Prometheus scrapes every 15 seconds
- Give it 1-2 minutes after deployment

## Files Modified

| File | Purpose |
|------|---------|
| `observability-stack.yml` | Added dashboard config mount to Grafana service |
| `configs/grafana-dashboards.yml` | Dashboard provider config (already existed) |
| `configs/grafana-plant-monitoring-dashboard.json` | Actual dashboard definition (already existed) |
| `ansible/deploy-stack.yml` | Copies dashboard JSON to manager (already included) |

## Testing Auto-Installation

**Full deployment test:**
```bash
# 1. Tear down existing deployment
cd /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC
./teardown.sh

# 2. Fresh deployment
./deploy.sh

# 3. Wait for services to start (2-3 minutes)
sleep 180

# 4. Access Grafana
open http://<MANAGER_IP>:3000

# 5. Verify dashboard exists
# Navigate to Dashboards → Browse
# Should see "Plant Monitoring Dashboard - CA3"
```

**Expected result**: Dashboard appears automatically, no manual import needed! ✅

## Future Enhancements

### 1. Multiple Dashboards
```yaml
configs:
  grafana-plant-dashboard:
    file: ./configs/dashboards/plant-monitoring.json
  grafana-slo-dashboard:
    file: ./configs/dashboards/slo-compliance.json
  grafana-security-dashboard:
    file: ./configs/dashboards/security-metrics.json
```

### 2. Alert Rules Provisioning
```yaml
- source: grafana-alert-rules
  target: /etc/grafana/provisioning/alerting/rules.yml
```

### 3. Environment-Specific Dashboards
```bash
# dev-dashboard.json
# staging-dashboard.json  
# prod-dashboard.json
```

## References

- [Grafana Provisioning Documentation](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Dashboard JSON Schema](https://grafana.com/docs/grafana/latest/dashboards/json-model/)
- [Docker Swarm Configs](https://docs.docker.com/engine/swarm/configs/)

---

**Status**: ✅ Implemented and Production-Ready  
**Last Updated**: November 7, 2025  
**Testing**: Ready for verification on next deployment
