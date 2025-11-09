# Service Level Indicators, Objectives, and Agreements
## Plant Monitoring System - CA3

> **Purpose**: This document defines the measurable service levels for our distributed plant monitoring system, aligning with SRE best practices and user expectations.

---

## 📊 Overview

Our plant monitoring system is a real-time IoT data pipeline that collects sensor data, processes plant health metrics, and delivers alerts to users. The following SLI/SLO/SLAs ensure reliable, performant operation.

**System Architecture Tiers**:
- **Ingestion Tier**: Sensor → Kafka (sensor service producing to Kafka)
- **Processing Tier**: Kafka → Processor → MongoDB
- **Presentation Tier**: MongoDB → Home Assistant Dashboard

---

## 1️⃣ Service Level Indicators (SLIs)

SLIs are **quantifiable measurements** of system behavior that matter to users.

### 1.1 Data Pipeline SLIs

| SLI Name | Metric | Prometheus Query | Description |
|----------|--------|------------------|-------------|
| **Pipeline Latency (p95)** | Time from sensor reading to database storage | `histogram_quantile(0.95, rate(plant_data_pipeline_latency_seconds_bucket[5m]))` | 95th percentile end-to-end latency |
| **Pipeline Latency (p99)** | Time from sensor reading to database storage | `histogram_quantile(0.99, rate(plant_data_pipeline_latency_seconds_bucket[5m]))` | 99th percentile end-to-end latency |
| **Message Processing Success Rate** | Percentage of messages successfully processed | `sum(rate(plant_processor_messages_processed_total{status="success"}[5m])) / sum(rate(plant_processor_messages_processed_total[5m])) * 100` | Success rate for Kafka message processing |
| **Data Ingestion Rate** | Messages ingested per second | `rate(plant_processor_messages_processed_total[5m])` | Throughput of data pipeline |

### 1.2 System Availability SLIs

| SLI Name | Metric | Prometheus Query | Description |
|----------|--------|------------------|-------------|
| **Service Availability** | Percentage of time services are up | `avg_over_time(up{job=~"kafka\|mongodb\|processor"}[5m]) * 100` | Uptime of critical services |
| **Kafka Broker Health** | Kafka broker reachability | `up{job="kafka"}` | 1 = healthy, 0 = down |
| **MongoDB Health** | MongoDB database reachability | `up{job="mongodb"}` | 1 = healthy, 0 = down |
| **Home Assistant Availability** | Dashboard accessibility | `up{job="homeassistant"}` | 1 = accessible, 0 = down |

### 1.3 Data Quality SLIs

| SLI Name | Metric | Prometheus Query | Description |
|----------|--------|------------------|-------------|
| **Data Quality Error Rate** | Percentage of malformed messages | `rate(plant_processor_data_quality_errors_total[5m]) / rate(plant_processor_messages_processed_total[5m]) * 100` | Rate of messages with missing/invalid fields |
| **Database Write Success Rate** | Percentage of successful MongoDB inserts | `100 - (rate(plant_mongodb_connection_errors_total[5m]) / rate(plant_processor_messages_processed_total[5m]) * 100)` | Success rate for database operations |
| **Processing Duration (p50)** | Median message processing time | `histogram_quantile(0.50, rate(plant_processor_processing_duration_seconds_bucket[5m]))` | Typical processing time per message |

### 1.4 Alerting SLIs

| SLI Name | Metric | Prometheus Query | Description |
|----------|--------|------------------|-------------|
| **Alert Delivery Latency** | Time from threshold breach to alert | Manual timing (MQTT publish to HA notification) | Time to detect and notify plant health issues |
| **False Positive Rate** | Incorrect alerts / total alerts | `sum(plant_alerts_generated_total{severity="false_positive"}) / sum(plant_alerts_generated_total)` | Quality of alerting logic |

---

## 2️⃣ Service Level Objectives (SLOs)

SLOs are **targets for SLIs** that define acceptable system performance.

### 2.1 Latency SLOs

| Objective | Target | Measurement Window | Rationale |
|-----------|--------|-------------------|-----------|
| **Pipeline Latency (p95)** | < 5 seconds | Rolling 5-minute window | Users expect near-real-time updates; 5s allows for network delays and processing |
| **Pipeline Latency (p99)** | < 10 seconds | Rolling 5-minute window | Even slow messages should arrive within reasonable time |
| **Processing Duration (p50)** | < 100 milliseconds | Rolling 5-minute window | Median processing should be fast to maintain throughput |
| **Processing Duration (p95)** | < 500 milliseconds | Rolling 5-minute window | Slow messages shouldn't exceed half a second |

**Error Budget**: 5% of measurements can exceed targets (95% must meet SLO)

### 2.2 Availability SLOs

| Objective | Target | Measurement Window | Rationale |
|-----------|--------|-------------------|-----------|
| **System Availability** | ≥ 99.0% (2 nines) | 30-day rolling window | Allows ~7.2 hours downtime/month for maintenance and incidents |
| **Data Pipeline Uptime** | ≥ 99.5% | 30-day rolling window | Core functionality should be highly available (~3.6 hrs downtime/month) |
| **Kafka Broker Availability** | ≥ 99.9% | 30-day rolling window | Message queue is critical; allows ~43 minutes downtime/month |
| **MongoDB Availability** | ≥ 99.5% | 30-day rolling window | Database should match pipeline availability |
| **Home Assistant Dashboard** | ≥ 98.0% | 30-day rolling window | Read-only UI can tolerate more downtime (~14.4 hrs/month) |

**Error Budget**: 
- **System**: 7.2 hours/month
- **Pipeline**: 3.6 hours/month
- **Kafka**: 43 minutes/month

### 2.3 Throughput SLOs

| Objective | Target | Measurement Window | Rationale |
|-----------|--------|-------------------|-----------|
| **Data Ingestion Rate** | ≥ 10 messages/second | Rolling 5-minute window | Support 2 sensors × 5 plants at 1Hz sampling |
| **MongoDB Insert Rate** | ≥ 10 inserts/second | Rolling 5-minute window | Match ingestion rate |
| **Peak Throughput Capacity** | ≥ 100 messages/second | Load test validation | Handle 10x normal load for growth/bursts |

### 2.4 Reliability SLOs

| Objective | Target | Measurement Window | Rationale |
|-----------|--------|-------------------|-----------|
| **Message Processing Success Rate** | ≥ 99.9% | Rolling 5-minute window | Critical: Lost sensor data cannot be recovered |
| **Data Quality Error Rate** | < 1.0% | Rolling 5-minute window | Malformed data should be rare (sensor firmware quality) |
| **Database Write Success Rate** | ≥ 99.5% | Rolling 5-minute window | Writes should succeed unless database is down |
| **Kafka Connection Errors** | < 5 errors/hour | Rolling 1-hour window | Connection pool should be stable |

**Error Budget**: 0.1% = ~43 failed messages per 43,000 processed

### 2.5 Alerting SLOs

| Objective | Target | Measurement Window | Rationale |
|-----------|--------|-------------------|-----------|
| **Alert Delivery Latency** | < 30 seconds | Per-alert measurement | Users should be notified quickly of plant issues |
| **False Positive Rate** | < 5% | 24-hour window | Too many false alerts cause alert fatigue |
| **Critical Alert Uptime** | ≥ 99.0% | 30-day rolling window | Alert system should be highly available |

---

## 3️⃣ Service Level Agreements (SLAs)

SLAs are **contractual commitments** to users with consequences for breach.

### 3.1 Production SLA (Hypothetical Customer Contract)

> **Note**: These are example SLAs for a production plant monitoring service. For CA3, these serve as design targets.

#### Tier 1: Premium Service (Home Users)

| Service Component | SLA | Measurement | Consequence |
|-------------------|-----|-------------|-------------|
| **System Availability** | 99.0% monthly uptime | Automated Prometheus monitoring | 10% service credit if < 99.0% |
| **Data Delivery Latency** | 95% of readings within 5 seconds | Pipeline latency p95 metric | 5% credit if > 5s for > 10% of readings |
| **Alert Delivery** | Critical alerts within 60 seconds | Manual end-to-end test monthly | No additional charge for that month if missed |
| **Data Retention** | 90 days minimum | MongoDB backup verification | Full refund if data loss occurs |
| **Support Response** | 4-hour response time | Ticket system tracking | No charge for incident month |

**Annual Cost**: $120/year per plant location  
**Error Budget**: 87.6 hours downtime per year

#### Tier 2: Basic Service (Free Tier)

| Service Component | SLA | Measurement | Consequence |
|-------------------|-----|-------------|-------------|
| **System Availability** | 95.0% monthly uptime | Best effort | No guarantees |
| **Data Delivery Latency** | Best effort | N/A | No guarantees |
| **Alert Delivery** | Best effort | N/A | No guarantees |
| **Data Retention** | 30 days minimum | No backup | Data may be lost |
| **Support Response** | Community forum only | N/A | No dedicated support |

**Annual Cost**: Free  
**Error Budget**: 36 hours downtime per month

### 3.2 Internal SLA (Operations Team)

| Incident Severity | Response Time SLA | Resolution Time SLA | On-Call Escalation |
|-------------------|-------------------|---------------------|-------------------|
| **SEV1 - Critical** (Pipeline down, all alerts failing) | 15 minutes | 4 hours | Immediate page |
| **SEV2 - High** (Single component down, degraded service) | 30 minutes | 8 hours | Page during business hours |
| **SEV3 - Medium** (Performance degradation, non-critical errors) | 2 hours | 48 hours | Email alert |
| **SEV4 - Low** (Cosmetic issues, feature requests) | 24 hours | 1 week | Ticket queue |

---

## 4️⃣ Monitoring & Alerting Rules

### 4.1 Prometheus Alerting Rules

Create these in `/configs/prometheus-alerts.yml`:

```yaml
groups:
  - name: plant_monitoring_slos
    interval: 30s
    rules:
      # Latency SLO: p95 < 5 seconds
      - alert: PipelineLatencyExceedsSLO
        expr: histogram_quantile(0.95, rate(plant_data_pipeline_latency_seconds_bucket[5m])) > 5
        for: 5m
        labels:
          severity: warning
          slo: latency
        annotations:
          summary: "Pipeline p95 latency exceeds 5s SLO"
          description: "95th percentile latency is {{ $value | humanizeDuration }}, exceeding 5s target for 5 minutes"
      
      # Availability SLO: 99.5% uptime
      - alert: PipelineAvailabilityBelowSLO
        expr: avg_over_time(up{job=~"kafka|mongodb|processor"}[5m]) < 0.995
        for: 5m
        labels:
          severity: critical
          slo: availability
        annotations:
          summary: "Pipeline availability below 99.5% SLO"
          description: "Average service availability is {{ $value | humanizePercentage }}, below 99.5% target"
      
      # Success Rate SLO: 99.9% success
      - alert: MessageProcessingSuccessRateBelowSLO
        expr: |
          (
            sum(rate(plant_processor_messages_processed_total{status="success"}[5m])) 
            / 
            sum(rate(plant_processor_messages_processed_total[5m]))
          ) < 0.999
        for: 5m
        labels:
          severity: critical
          slo: reliability
        annotations:
          summary: "Message processing success rate below 99.9% SLO"
          description: "Success rate is {{ $value | humanizePercentage }}, below 99.9% target"
      
      # Throughput SLO: 10 msgs/sec minimum
      - alert: DataIngestionRateBelowSLO
        expr: sum(rate(plant_processor_messages_processed_total[5m])) < 10
        for: 5m
        labels:
          severity: warning
          slo: throughput
        annotations:
          summary: "Data ingestion rate below 10 msgs/sec SLO"
          description: "Current ingestion rate is {{ $value | humanize }} msgs/sec, below 10 msgs/sec target"
      
      # Error Budget Burn Rate
      - alert: HighErrorBudgetBurnRate
        expr: |
          (
            1 - (
              sum(rate(plant_processor_messages_processed_total{status="success"}[1h])) 
              / 
              sum(rate(plant_processor_messages_processed_total[1h]))
            )
          ) > 0.001  # Burning > 0.1% per hour
        for: 15m
        labels:
          severity: warning
          slo: error_budget
        annotations:
          summary: "High error budget burn rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}/hour, will exhaust monthly budget in {{ 100 | divideBy $value | humanizeDuration }}"
```

### 4.2 Grafana Dashboard Panels

Add these panels to your Grafana dashboard:

**Panel 1: SLO Compliance Summary**
```promql
# Latency SLO Compliance (% of measurements < 5s)
sum(
  rate(plant_data_pipeline_latency_seconds_bucket{le="5"}[5m])
) 
/ 
sum(
  rate(plant_data_pipeline_latency_seconds_count[5m])
) * 100
```

**Panel 2: Error Budget Remaining**
```promql
# Monthly error budget remaining (%)
100 - (
  (
    1 - (
      sum(increase(plant_processor_messages_processed_total{status="success"}[30d])) 
      / 
      sum(increase(plant_processor_messages_processed_total[30d]))
    )
  ) / 0.001 * 100  # 0.1% allowed failure rate
)
```

**Panel 3: Availability by Component**
```promql
# Component availability (%)
avg_over_time(up{job=~"kafka|mongodb|processor|homeassistant"}[30d]) * 100
```

---

## 5️⃣ Error Budget Policy

### Monthly Error Budget Allocation

Based on **99.5% availability SLO** for data pipeline:

- **Total Allowed Downtime**: 3.6 hours/month (0.5% of 720 hours)
- **Planned Maintenance**: 1 hour/month (27.8% of budget)
- **Incident Response**: 2.6 hours/month (72.2% of budget)

### Error Budget Actions

| Budget Remaining | Action | Responsible Team |
|------------------|--------|------------------|
| **> 50%** | ✅ Normal operations; can deploy new features | Development |
| **25-50%** | ⚠️ Slow down deployments; focus on reliability | Dev + Ops |
| **10-25%** | 🚨 Feature freeze; only critical fixes | Ops leads |
| **< 10%** | 🔥 Emergency response; all hands on deck | All teams |

### Budget Burn Rate Alerts

- **Fast Burn**: Losing > 2% budget/hour → Page on-call immediately
- **Medium Burn**: Losing > 0.5% budget/hour → Email team leads
- **Slow Burn**: Losing > 0.1% budget/hour → Log for review

---

## 6️⃣ Implementation in CA3

### Current Metrics Coverage

✅ **Already Instrumented**:
- Pipeline latency histogram (`plant_data_pipeline_latency_seconds`)
- Message processing counters (`plant_processor_messages_processed_total`)
- Connection error counters (`plant_kafka_connection_errors_total`, `plant_mongodb_connection_errors_total`)
- Processing duration histogram (`plant_processor_processing_duration_seconds`)
- Health scores gauge (`plant_health_score`)
- Alert counters (`plant_alerts_generated_total`)

✅ **Already Monitoring**:
- Prometheus scraping all exporters (Node, Kafka, MongoDB, custom app metrics)
- Grafana dashboard with 11 panels
- Loki log aggregation for troubleshooting

### Gaps to Fill (Optional Enhancements)

❌ **Missing Metrics**:
- Alert delivery end-to-end latency (requires timing MQTT → HA notification)
- False positive tracking (requires alert validation labels)
- Kafka consumer lag per partition (kafka_exporter provides this)

❌ **Missing Dashboards**:
- SLO compliance dashboard (show % meeting targets)
- Error budget burn rate visualization
- Monthly SLA report

### Quick Setup Commands

**1. Add Prometheus alerting rules:**
```bash
# Create alerts file
cat > configs/prometheus-alerts.yml << 'EOF'
# (Use the rules from section 4.1 above)
EOF

# Update prometheus.yml to include alerts
# Add to prometheus.yml under rule_files:
#   - /etc/prometheus/alerts.yml
```

**2. Query SLIs in Prometheus:**
```bash
# Access Prometheus
open http://18.219.157.100:9090

# Run queries from section 1 above
```

**3. Verify SLO compliance:**
```bash
# Check pipeline latency p95 over last hour
curl -s 'http://18.219.157.100:9090/api/v1/query?query=histogram_quantile(0.95,%20rate(plant_data_pipeline_latency_seconds_bucket[1h]))' | jq '.data.result[0].value[1]'

# Check success rate over last hour
curl -s 'http://18.219.157.100:9090/api/v1/query?query=sum(rate(plant_processor_messages_processed_total{status=%22success%22}[1h]))%20/%20sum(rate(plant_processor_messages_processed_total[1h]))' | jq '.data.result[0].value[1]'
```

---

## 7️⃣ Reporting & Review Cadence

### Weekly SLO Review (15 min)
- Review SLO compliance dashboard
- Identify any SLO violations
- Check error budget burn rate
- Quick triage of issues

### Monthly SLA Review (1 hour)
- Generate SLA compliance report
- Calculate uptime percentage
- Review incident postmortems
- Update SLO targets if needed
- Communicate to stakeholders

### Quarterly SLO Refinement (2 hours)
- Analyze user feedback
- Adjust SLO targets based on business needs
- Add new SLIs for new features
- Review cost vs. reliability tradeoffs

---

## 8️⃣ References

- **Google SRE Book**: [Chapter 4 - Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- **Prometheus Best Practices**: [Alerting Rules](https://prometheus.io/docs/practices/alerting/)
- **Site Reliability Workbook**: [Implementing SLOs](https://sre.google/workbook/implementing-slos/)
- **CS5287 Course Materials**: Week 7 - Observability & SRE Components

---

## 📝 Document Maintenance

- **Owner**: DevOps Team
- **Last Updated**: November 2, 2025
- **Review Frequency**: Quarterly
- **Next Review**: February 1, 2026

---

*This document defines the service levels for the Plant Monitoring System developed for CS5287 - Cloud Systems course, demonstrating understanding of SRE principles and production-ready observability.*
