# Service Level Objectives & Monitoring

## Overview

This plant monitoring system is instrumented with comprehensive observability following SRE best practices. We define clear Service Level Indicators (SLIs), Objectives (SLOs), and Agreements (SLAs) to ensure reliable, performant operation.

📊 **Full Documentation**: See [SLI_SLO_SLA_DEFINITIONS.md](./SLI_SLO_SLA_DEFINITIONS.md) for complete details.

## Key Service Level Objectives

### 🚀 Performance SLOs

| Metric | Target | Current Status |
|--------|--------|----------------|
| **Pipeline Latency (p95)** | < 5 seconds | ✅ Query: `histogram_quantile(0.95, rate(plant_data_pipeline_latency_seconds_bucket[5m]))` |
| **Processing Duration (p95)** | < 500ms | ✅ Query: `histogram_quantile(0.95, rate(plant_processor_processing_duration_seconds_bucket[5m]))` |
| **Data Ingestion Rate** | ≥ 10 msgs/sec | ✅ Query: `sum(rate(plant_processor_messages_processed_total[5m]))` |

### ⚡ Availability SLOs

| Component | Target | Monthly Downtime Budget |
|-----------|--------|-------------------------|
| **Overall System** | 99.0% | 7.2 hours |
| **Data Pipeline** | 99.5% | 3.6 hours |
| **Kafka Broker** | 99.9% | 43 minutes |
| **MongoDB** | 99.5% | 3.6 hours |
| **Home Assistant** | 98.0% | 14.4 hours |

### 🎯 Reliability SLOs

| Metric | Target | Error Budget |
|--------|--------|--------------|
| **Message Processing Success Rate** | ≥ 99.9% | 0.1% failures allowed |
| **Database Write Success Rate** | ≥ 99.5% | 0.5% failures allowed |
| **Data Quality Error Rate** | < 1.0% | 1% malformed messages |

## Monitoring Implementation

### Available Metrics (Prometheus)

Our system exposes **15+ custom metrics** for comprehensive observability:

**Pipeline Metrics**:
- `plant_data_pipeline_latency_seconds` - End-to-end latency histogram
- `plant_processor_messages_processed_total` - Messages processed counter (by status)
- `plant_processor_processing_duration_seconds` - Processing time histogram

**System Health Metrics**:
- `plant_kafka_connection_errors_total` - Kafka connection failures
- `plant_mongodb_connection_errors_total` - MongoDB connection failures
- `plant_mongodb_inserts_per_second` - Database write throughput

**Application Metrics**:
- `plant_health_score` - Plant health scores (0-100)
- `plant_alerts_generated_total` - Alert generation counter
- `plant_processor_data_quality_errors_total` - Data validation failures

**Infrastructure Metrics** (via exporters):
- Node Exporter: CPU, memory, disk, network per node
- Kafka Exporter: Broker health, consumer lag, partition metrics
- MongoDB Exporter: Database operations, connections, replication status

### Accessing Metrics

**Prometheus UI**: `http://<MANAGER_IP>:9090`
```bash
# Query Examples
# 1. Check pipeline latency (p95)
histogram_quantile(0.95, rate(plant_data_pipeline_latency_seconds_bucket[5m]))

# 2. Check success rate
sum(rate(plant_processor_messages_processed_total{status="success"}[5m])) / sum(rate(plant_processor_messages_processed_total[5m])) * 100

# 3. Check current throughput
sum(rate(plant_processor_messages_processed_total[5m]))
```

**Grafana Dashboards**: `http://<MANAGER_IP>:3000`
- Username: `admin` / Password: `admin` (change on first login)
- Pre-configured datasources: Prometheus + Loki
- Import dashboard: `configs/grafana-plant-monitoring-dashboard.json`

**Loki Logs**: Access via Grafana → Explore
```logql
# Search for errors across all services
{job=~"plant-monitoring.*"} |= "error" | json

# Filter by service
{job="plant-monitoring_processor"} | json | line_format "{{.timestamp}} {{.level}} {{.message}}"

# Search for specific plant
{job=~"plant-monitoring.*"} |~ "plant-001"
```

## SLO Verification Commands

### 1. Verify Pipeline Latency SLO (< 5s)

```bash
# Get p95 latency for last 5 minutes
curl -s "http://${MANAGER_IP}:9090/api/v1/query?query=histogram_quantile(0.95,%20rate(plant_data_pipeline_latency_seconds_bucket[5m]))" \
  | jq '.data.result[0].value[1]' \
  | awk '{print ($1 < 5) ? "✅ SLO MET: " $1 "s" : "❌ SLO VIOLATED: " $1 "s"}'
```

### 2. Verify Success Rate SLO (≥ 99.9%)

```bash
# Get success rate for last 5 minutes
curl -s "http://${MANAGER_IP}:9090/api/v1/query?query=sum(rate(plant_processor_messages_processed_total{status=%22success%22}[5m]))%20/%20sum(rate(plant_processor_messages_processed_total[5m]))" \
  | jq '.data.result[0].value[1]' \
  | awk '{rate=$1*100; print (rate >= 99.9) ? "✅ SLO MET: " rate "%" : "❌ SLO VIOLATED: " rate "%"}'
```

### 3. Verify Service Availability SLO (≥ 99.5%)

```bash
# Check all critical services are up
curl -s "http://${MANAGER_IP}:9090/api/v1/query?query=up{job=~%22kafka|mongodb|processor%22}" \
  | jq -r '.data.result[] | "\(.metric.job): \(.value[1] == "1" and "✅ UP" or "❌ DOWN")"'
```

### 4. Check Error Budget Status

```bash
# Calculate monthly error budget remaining (99.9% SLO = 0.1% allowed failures)
curl -s "http://${MANAGER_IP}:9090/api/v1/query?query=100%20-%20((1%20-%20(sum(increase(plant_processor_messages_processed_total{status=%22success%22}[30d]))%20/%20sum(increase(plant_processor_messages_processed_total[30d]))))%20/%200.001%20*%20100)" \
  | jq '.data.result[0].value[1]' \
  | awk '{print ($1 > 50) ? "✅ ERROR BUDGET HEALTHY: " $1 "% remaining" : ($1 > 0) ? "⚠️  ERROR BUDGET LOW: " $1 "% remaining" : "❌ ERROR BUDGET EXHAUSTED"}'
```

## Alerting Rules (Optional Enhancement)

To enable proactive SLO violation detection, add Prometheus alerting rules:

**Create `configs/prometheus-alerts.yml`:**
```yaml
groups:
  - name: slo_violations
    interval: 30s
    rules:
      - alert: PipelineLatencyExceedsSLO
        expr: histogram_quantile(0.95, rate(plant_data_pipeline_latency_seconds_bucket[5m])) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pipeline p95 latency exceeds 5s SLO"
          
      - alert: MessageProcessingSuccessRateBelowSLO
        expr: sum(rate(plant_processor_messages_processed_total{status="success"}[5m])) / sum(rate(plant_processor_messages_processed_total[5m])) < 0.999
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Success rate below 99.9% SLO"
```

**Update `configs/prometheus.yml`:**
```yaml
rule_files:
  - /etc/prometheus/alerts.yml
```

## Error Budget Policy

Our error budget policy balances innovation with reliability:

| Budget Remaining | Policy | Action |
|------------------|--------|--------|
| **> 50%** | 🚀 Normal operations | Deploy new features freely |
| **25-50%** | ⚠️ Cautious mode | Slow deployments, focus testing |
| **10-25%** | 🔒 Feature freeze | Only critical bug fixes |
| **< 10%** | 🚨 Emergency | All hands focus on reliability |

### Burn Rate Monitoring

Monitor how quickly we consume error budget:

```promql
# Fast burn: > 2% budget/hour = immediate page
rate(plant_processor_messages_processed_total{status!="success"}[1h]) / rate(plant_processor_messages_processed_total[1h]) > 0.02

# Medium burn: > 0.5% budget/hour = email team
rate(plant_processor_messages_processed_total{status!="success"}[1h]) / rate(plant_processor_messages_processed_total[1h]) > 0.005
```

## SLO Review Cadence

### Weekly (15 min)
- Review Grafana SLO compliance dashboard
- Check for any SLO violations
- Quick triage of issues

### Monthly (1 hour)
- Generate SLA compliance report
- Calculate actual uptime vs. targets
- Review incident postmortems
- Communicate status to stakeholders

### Quarterly (2 hours)
- Refine SLO targets based on user feedback
- Add new SLIs for new features
- Cost vs. reliability analysis

## References

- **Full SLI/SLO/SLA Documentation**: [SLI_SLO_SLA_DEFINITIONS.md](./SLI_SLO_SLA_DEFINITIONS.md)
- **Google SRE Book**: [Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- **Prometheus Querying**: [PromQL Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- **Grafana Dashboards**: [Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/)

---

**Next Steps**:
1. ✅ Review [SLI_SLO_SLA_DEFINITIONS.md](./SLI_SLO_SLA_DEFINITIONS.md)
2. ✅ Run SLO verification commands above
3. ✅ Import Grafana dashboard to visualize SLOs
4. 📊 (Optional) Add Prometheus alerting rules for proactive monitoring
5. 📊 (Optional) Create SLO compliance dashboard in Grafana
