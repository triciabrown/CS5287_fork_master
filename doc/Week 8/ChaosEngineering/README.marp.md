---
marp: true
theme: default
paginate: true
---

# Chaos Engineering
## For Cloud Architecture

Video: https://youtu.be/TLvi73dfgJw

---

# Introduction & Motivation
- Opening scenario: Regional outage at cloud provider
- Learning objectives:
    1. Why chaos experiments matter
    2. Methodology for safe experiments
    3. Tools & real-world applications

---

# What Is Chaos Engineering?
> “A discipline of experimenting on a system to build confidence in its ability to withstand turbulent conditions in production.”

**Key Insights**
- Controlled, data-driven experiments
- Hypotheses validated against SLAs, latency, error rates
- Continuous feedback loop

---

# Why Chaos in the Cloud?
- **Dynamic environments** (autoscaling, containers, serverless)
- **Hidden coupling** across services
- **Cost of downtime** (~\$5,600/min unplanned outage)

---

# Four-Step Chaos Engineering Process
1. Define Steady State
2. Form Hypothesis
3. Run Controlled Experiments
4. Observe, Learn, Improve

---

# Failure Modes & Mitigations

| Failure Mode           | Real-World Impact                        | Mitigation Pattern               |
|------------------------|------------------------------------------|----------------------------------|
| VM / Container Kill    | Abrupt capacity drop, in-flight aborts   | Graceful shutdown, retries       |
| Network Latency / Loss | Timeouts, request blocking               | Circuit breakers, timeouts       |
| Resource Exhaustion    | OOM kills, CPU spikes                    | Autoscaling, quotas              |
| Dependency Downtime    | Cascading failures                       | Bulkheads, async comms           |
| Zone / Region Outage   | Entire region unavailable                | Multi-region failover            |

---
# Auto Recovery

![Auto Recovery](autorecovery.png)

---

# Blast Radius

![Blast Radius](blastRadius.png)

---

# Circuit Breaker

![Circuit Breaker](circuitBreaker.png)

---
 
# Observability

![Monitoring](monitoring.png)

---

# Multi-region Resilience

![Multi-region](multi-region.png)

---

# Tools & Ecosystem Deep Dive
- **Chaos Monkey** (Netflix)
- **Gremlin** (fault library + RBAC)
- **LitmusChaos** (K8s native CRDs)
- **Cloud Offerings**: AWS FIS, Azure Chaos Studio, GCP Resilience Toolkit

---

# Designing Effective Experiments

![Blast Readius](blastRadius.png)

1. Select Environment (Dev → Prod Canary)
2. Scope & Blast Radius (1% → 100%)
3. Instrumentation & Monitoring
4. Safety Mechanisms (abort switches, timeouts)
5. Documentation & Communication

---

# Real-World Case Study: E-Commerce
- **Challenge:** Slow checkout at peak
- **Experiment:** 200 ms latency to Inventory via Toxiproxy
- **Outcome:**
    - 95% fallback to cache
    - Added circuit breaker & retry logic

---

# Real-World Case Study: Video Streaming
- **Challenge:** DB failover causing buffering
- **Experiment:** Master DB crash in staging
- **Outcome:**
    - Tuned HikariCP pool settings
    - Failover time ↓ from 2 min → 30 s

---

# Organizational & Cultural Considerations
- Cross-functional collaboration (SRE, Dev, Security)
- Blameless postmortems
- Resilience hackathons / game days
- Governance & policy for experiments

---

# Measuring Impact & ROI
- **Quantitative**:
    - ↓ Incident count & severity
    - ↓ MTTD & MTTR
- **Qualitative**:
    - ↑ Deployment confidence
    - Stronger dev-ops collaboration
- **Business Value**: Uptime → Revenue protection
