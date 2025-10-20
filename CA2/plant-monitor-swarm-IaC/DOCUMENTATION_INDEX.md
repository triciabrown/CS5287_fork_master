# Documentation Index - Network Troubleshooting

## Quick Navigation

### 🔴 Start Here If You Have Connection Issues

**README.md** → Troubleshooting section  
Look for: "⚠️ CRITICAL ISSUE: Overlay Network IP Conflict"  
Quick fix and checklist.

---

## Detailed Documentation

### 1. **OVERLAY_NETWORK_IP_CONFLICT.md** 📖 **READ THIS FIRST**

**What it covers**:
- What are Docker overlay networks?
- How they work with cloud infrastructure (AWS/Azure/GCP)
- Why IP conflicts happen
- Detailed routing analysis
- Complete solution with examples
- Best practices for production

**When to read**: 
- Before deploying to any cloud provider
- When debugging cross-node connectivity issues
- To understand Docker Swarm networking fundamentals

**Key sections**:
- "Understanding Docker Overlay Networks" - Core concepts
- "The IP Conflict Problem" - What went wrong
- "How It Works" - Visual diagrams
- "Best Practices" - Prevention strategies

---

### 2. **KAFKA_DNS_TROUBLESHOOTING.md** 🔍

**What it covers**:
- DNS resolution issues with Docker Swarm
- VIP vs DNSRR endpoint modes
- Step-by-step diagnosis process
- **UPDATE**: Explains how this was secondary to overlay network issue

**When to read**:
- After reading OVERLAY_NETWORK_IP_CONFLICT.md
- If you still have DNS-specific issues
- To understand VIP vs DNSRR trade-offs

**Key sections**:
- "Diagnosis Steps" - How to check DNS
- "The Real Issue" - Connects to overlay network problem
- "Lessons Learned" - What we got wrong initially

---

### 3. **TROUBLESHOOTING_SUMMARY.md** 📝

**What it covers**:
- Complete timeline of our investigation
- What we tried and why it didn't work
- How we found the root cause
- Lessons learned
- Prevention checklist

**When to read**:
- To understand the full debugging journey
- To learn systematic troubleshooting approach
- For lessons learned and prevention strategies

**Key sections**:
- "Troubleshooting Journey" - Phase-by-phase analysis
- "Lessons Learned" - What to do differently
- "Prevention Strategy" - Checklist for future deployments

---

### 4. **SCALING-SCRIPT-FIXES.md** 🛠️

**What it covers**:
- Issues with the scaling-test.sh script
- SSH banner pollution
- Variable parsing problems
- Service name filter errors

**When to read**:
- If scaling test script produces errors
- When debugging automation scripts
- To understand SSH quirks with Docker Swarm

---

## Reading Order by Scenario

### 🆕 First-Time Deployment

1. **README.md** - Overview and deployment steps
2. **OVERLAY_NETWORK_IP_CONFLICT.md** - Understand networking before deploying
3. Deploy your infrastructure
4. Run verification checklist from TROUBLESHOOTING_SUMMARY.md

### 🐛 Services Can't Connect

1. **README.md** → Troubleshooting section (quick checks)
2. **OVERLAY_NETWORK_IP_CONFLICT.md** (likely your issue)
3. **KAFKA_DNS_TROUBLESHOOTING.md** (if overlay network is correct)
4. **TROUBLESHOOTING_SUMMARY.md** (systematic approach)

### 📚 Learning Docker Swarm Networking

1. **OVERLAY_NETWORK_IP_CONFLICT.md** - Core concepts
2. **KAFKA_DNS_TROUBLESHOOTING.md** - Service discovery
3. **TROUBLESHOOTING_SUMMARY.md** - Real-world example

### 🧪 Running Scaling Tests

1. **README.md** → Testing & Validation section
2. **SCALING-SCRIPT-FIXES.md** - Known script issues
3. Run `./scaling-test.sh`

---

## Quick Reference: Common Issues

### Services timeout connecting to Kafka/MongoDB

**Check**: Is overlay network using same IP range as AWS subnet?
```bash
docker network inspect plant-monitoring_plant-network --format '{{.IPAM.Config}}'
```

**Read**: OVERLAY_NETWORK_IP_CONFLICT.md → "The IP Conflict Problem"

---

### DNS errors: "ENOTFOUND kafka"

**Check**: Is service using VIP or DNSRR endpoint mode?
```bash
docker service inspect plant-monitoring_kafka --format '{{.Spec.EndpointSpec.Mode}}'
```

**Read**: KAFKA_DNS_TROUBLESHOOTING.md → "Solution"

---

### Works on manager, fails on workers

**This is THE classic symptom of overlay network IP conflict!**

**Read immediately**: OVERLAY_NETWORK_IP_CONFLICT.md → "The IP Conflict Problem"

---

### Scaling script errors

**Check**: Are you getting SSH banner pollution or parsing errors?

**Read**: SCALING-SCRIPT-FIXES.md

---

## Documentation Structure

```
plant-monitor-swarm-IaC/
│
├── README.md                           # Main documentation
│   ├── Deployment instructions
│   ├── ⚠️ Critical warning about overlay network
│   └── Troubleshooting quick reference
│
├── OVERLAY_NETWORK_IP_CONFLICT.md      # ★ PRIMARY TECHNICAL DOC
│   ├── What are overlay networks?
│   ├── Why conflicts happen
│   ├── Detailed routing analysis
│   └── Best practices
│
├── KAFKA_DNS_TROUBLESHOOTING.md        # DNS-specific issues
│   ├── VIP vs DNSRR modes
│   ├── Diagnosis steps
│   └── Connection to overlay issue
│
├── TROUBLESHOOTING_SUMMARY.md          # Our debugging journey
│   ├── Timeline of investigation
│   ├── What we got wrong
│   ├── Lessons learned
│   └── Prevention checklist
│
├── SCALING-SCRIPT-FIXES.md             # Script-specific issues
│   └── SSH and parsing problems
│
└── DOCUMENTATION_INDEX.md              # This file
    └── Navigation guide
```

---

## Key Takeaways (TL;DR)

### The Problem
Docker overlay network IP range (10.0.1.0/24) conflicted with AWS public subnet (10.0.1.0/24), causing routing failures.

### The Solution
```yaml
networks:
  plant-network:
    driver: overlay
    ipam:
      config:
        - subnet: 10.10.0.0/24  # Different from AWS 10.0.x.x
```

### The Lesson
**Always** explicitly configure overlay network subnets in production. **Never** rely on Docker's auto-assignment when deploying to cloud infrastructure.

### Essential Reading
1. OVERLAY_NETWORK_IP_CONFLICT.md (15 min)
2. README.md troubleshooting section (5 min)
3. TROUBLESHOOTING_SUMMARY.md (10 min)

**Total time investment**: 30 minutes  
**Time saved on future deployments**: Hours!

---

## Updates and Maintenance

### Last Updated
October 18, 2025

### Version History
- **v1.0** (Oct 18, 2025): Initial documentation after discovering overlay network issue
  - Created OVERLAY_NETWORK_IP_CONFLICT.md
  - Updated KAFKA_DNS_TROUBLESHOOTING.md with root cause
  - Added critical warning to README.md
  - Created TROUBLESHOOTING_SUMMARY.md
  - Created this index

### Future Additions
- [ ] Add Azure/GCP-specific networking guidance
- [ ] Include Terraform validation scripts
- [ ] Add automated network conflict checker
- [ ] Include more visual diagrams

---

## Contributing

If you discover additional issues or have suggestions:
1. Document the issue clearly
2. Include diagnosis steps
3. Provide solution with examples
4. Update this index

---

## Contact

**Tricia Brown**  
CS5287 - Cloud Computing  
October 2024

For questions about this documentation or the deployment:
- See README.md for deployment help
- See individual docs for technical details
- See TROUBLESHOOTING_SUMMARY.md for systematic approach
