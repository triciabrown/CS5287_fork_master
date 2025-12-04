# CA4: Edge-to-Cloud Multi-Hybrid Deployment - Quick Start

**Status**: 📋 Planning Complete - Ready for Implementation  
**Assignment**: CA4 - Multi-Hybrid Cloud (Final Project)  
**Topology**: Edge → Cloud (Sensors local, Processing in AWS)

---

## 📖 Read This First

### What is CA4?

CA4 extends your existing CA2 plant monitoring system to a **multi-site edge-to-cloud architecture**:

- **Edge Site** (Local): Plant sensor containers running on your laptop/VM
- **Cloud Site** (AWS): Kafka, MongoDB, processor, and Home Assistant dashboard
- **Secure Connectivity**: WireGuard VPN tunnel connecting the two sites

### Why This Architecture?

✅ **Realistic IoT Deployment**: Sensors at the edge (where data originates)  
✅ **Cloud Processing**: Heavy lifting (Kafka, databases) in cloud with better resources  
✅ **Secure Communication**: Encrypted VPN tunnel (no public Kafka endpoint)  
✅ **Resilience Testing**: Demonstrate failure scenarios and recovery  

---

## 🎯 Key Documents

### 1. **CA4_IMPLEMENTATION_PLAN.md** ⭐ **START HERE**
   - Complete implementation plan (40+ pages)
   - Architecture design with diagrams
   - VPN setup (WireGuard recommended)
   - Edge and cloud site designs
   - Failure scenarios and recovery procedures
   - Week-by-week timeline

### 2. **Assignment README** (`doc/assignments/CA4/README.md`)
   - Official requirements
   - Grading rubric
   - Deliverables checklist

---

## 🏗️ Architecture Overview

```
┌─────────────────────┐         VPN Tunnel        ┌─────────────────────┐
│   EDGE SITE         │      (WireGuard/          │   CLOUD SITE        │
│   (Your Laptop/VM)  │       Encrypted)          │   (AWS us-east-2)   │
│                     │                            │                     │
│  🌱 Sensors (3x)    ├──────────────────────────→│  📊 Kafka           │
│    - Monstera       │   10.20.0.0/24            │  🗄️  MongoDB         │
│    - Sansevieria    │                            │  ⚙️  Processor       │
│    - Monstera       │                            │  🏠 Home Assistant  │
│                     │                            │  📡 Mosquitto       │
│  Docker Compose     │                            │  Docker Swarm       │
└─────────────────────┘                            └─────────────────────┘
```

**Data Flow**: Sensors (Edge) → VPN → Kafka (Cloud) → Processor → MongoDB → MQTT → Home Assistant

---

## 📋 Implementation Checklist

### Phase 1: Cloud Site (Modify CA2) ⏱️ 2-3 days

- [ ] Copy CA2 infrastructure to CA4/cloud-site
- [ ] Update Terraform: Add WireGuard security group rules
- [ ] Modify docker-compose.yml: Remove sensors, update Kafka config
- [ ] Test cloud deployment in isolation
- [ ] Install WireGuard on AWS manager node

### Phase 2: VPN Setup ⏱️ 1-2 days

- [ ] Install WireGuard on edge (local laptop/VM)
- [ ] Generate VPN keys (cloud + edge)
- [ ] Configure WireGuard on cloud gateway (10.20.0.1)
- [ ] Configure WireGuard on edge client (10.20.0.2)
- [ ] Test VPN connectivity: `ping 10.20.0.1`
- [ ] Verify Kafka access over VPN: `telnet 10.20.0.1 9092`

### Phase 3: Edge Site ⏱️ 1 day

- [ ] Create edge-site/docker-compose.yml (sensors only)
- [ ] Update sensor environment: `KAFKA_BROKERS=10.20.0.1:9092`
- [ ] Write deploy-edge.sh script
- [ ] Test edge deployment locally
- [ ] Verify sensor → Kafka connectivity

### Phase 4: Automation ⏱️ 2 days

- [ ] Write cloud-site/deploy-cloud.sh
- [ ] Write edge-site/deploy-edge.sh
- [ ] Write CA4/deploy-all.sh (master script)
- [ ] Write CA4/verify-deployment.sh
- [ ] Test end-to-end deployment from scratch

### Phase 5: Documentation ⏱️ 2 days

- [ ] Create architecture diagram (PlantUML or draw.io)
- [ ] Write CA4/README.md
- [ ] Write CA4/RUNBOOK.md (operations guide)
- [ ] Document failure scenarios
- [ ] Take screenshots of deployments

### Phase 6: Testing & Demo ⏱️ 1-2 days

- [ ] Perform full deployment test
- [ ] Test VPN failure drill (stop WireGuard, recover)
- [ ] Test Kafka failure drill (scale down, recover)
- [ ] Record demo video (≤4 minutes)
- [ ] Final submission review

**Total Estimated Time**: 10-12 days (leveraging 70-80% reuse from CA2)

---

## 🚀 Quick Commands Reference

### Cloud Site Deployment
```bash
cd CA4/cloud-site
./deploy-cloud.sh              # Deploy Kafka, MongoDB, etc. to AWS
```

### VPN Setup
```bash
cd CA4/vpn-config
./setup-vpn.sh <CLOUD_IP>      # Automated WireGuard setup
sudo wg-quick up wg0           # Start VPN tunnel
ping 10.20.0.1                 # Test connectivity
```

### Edge Site Deployment
```bash
cd CA4/edge-site
./deploy-edge.sh               # Deploy sensors locally
docker-compose logs -f         # Watch sensor logs
```

### Master Deployment (All Sites)
```bash
cd CA4
./deploy-all.sh                # Deploy cloud + VPN + edge
./verify-deployment.sh         # Verify end-to-end flow
```

### Failure Drills
```bash
cd CA4/failure-drills
./vpn-failure.sh               # Test VPN failure/recovery
./kafka-failure.sh             # Test Kafka failure/recovery
```

---

## 📊 CA4 vs CA2 Comparison

| Aspect | CA2 | CA4 |
|--------|-----|-----|
| **Sites** | 1 (AWS only) | 2 (Edge + Cloud) |
| **Sensors** | AWS workers | Local edge |
| **Kafka** | AWS internal | AWS via VPN |
| **Network** | Single overlay | VPN + overlay |
| **Complexity** | Medium | High |
| **Realism** | Lab deployment | Production-like IoT |

---

## 🎓 Learning Objectives (CA4 Assignment)

✅ **Design & Architecture** (25%)
- Multi-site topology selection and rationale
- Clear architecture diagram with CIDR blocks and VPN tunnels

✅ **Connectivity & Security** (20%)
- VPN tunnel configuration (WireGuard/OpenVPN)
- Encrypted traffic between sites
- Minimal port exposure (no public Kafka)

✅ **Deployment Automation** (20%)
- Single-command deployment for both sites
- Parameterized configurations (site-specific settings)
- Idempotent scripts

✅ **Resilience & Runbooks** (25%)
- Failure drill (VPN/Kafka/network partition)
- Documented recovery procedures
- Clear incident response steps

✅ **Documentation & Usability** (10%)
- Complete README with instructions
- Architecture diagram
- Demo video (≤4 minutes)

---

## 💡 Key Design Decisions

### 1. WireGuard vs OpenVPN
**Chosen**: WireGuard  
**Why**: Simpler config, faster, built into modern Linux kernels, perfect for site-to-site VPN

### 2. Edge Environment
**Chosen**: Local laptop/VM (Ubuntu 22.04)  
**Why**: Easy to test, no additional cloud costs, realistic edge deployment

### 3. Kafka Access Pattern
**Chosen**: VPN tunnel only (no public endpoint)  
**Why**: Security best practice, demonstrates secure connectivity requirement

### 4. Cloud Resource Optimization
**Chosen**: Reduce workers from 4 to 2  
**Why**: No sensors in cloud anymore, lower cost, still demonstrates multi-node Swarm

---

## 🆘 Need Help?

### Common Questions

**Q: Can I use a different VPN technology?**  
A: Yes! OpenVPN, Tailscale, or ZeroTier are acceptable. Document your choice in README.

**Q: Do I need a separate edge machine?**  
A: No, your laptop/desktop is fine. Can also use a local VM or Raspberry Pi.

**Q: How do I access Home Assistant from edge site?**  
A: Via public IP: `http://<AWS_MANAGER_IP>:8123` (already exposed in CA2)

**Q: What if VPN setup fails?**  
A: See troubleshooting in CA4_IMPLEMENTATION_PLAN.md, section 3 (VPN Connectivity Design)

**Q: Can I reuse CA2 scripts?**  
A: Yes! 70-80% is reusable. Main changes: split docker-compose, add VPN, update Kafka config.

---

## 📚 Additional Resources

### From CA2 (Reusable)
- `CA2/plant-monitor-swarm-IaC/docker-compose.yml` - Base stack definition
- `CA2/plant-monitor-swarm-IaC/terraform/main.tf` - AWS infrastructure
- `CA2/applications/sensor/sensor.js` - Sensor code (unchanged)
- `CA2/applications/processor/app.js` - Processor code (unchanged)

### CA4 Documentation
- `CA4_IMPLEMENTATION_PLAN.md` - Complete implementation guide
- `doc/assignments/CA4/README.md` - Assignment requirements

### External References
- [WireGuard Quick Start](https://www.wireguard.com/quickstart/)
- [Docker Multi-Host Networking](https://docs.docker.com/network/network-tutorial-overlay/)
- [Kafka External Listeners](https://www.confluent.io/blog/kafka-listeners-explained/)

---

## 🎬 Next Steps

1. **Read the full implementation plan**: `CA4_IMPLEMENTATION_PLAN.md`
2. **Set up your project structure**:
   ```bash
   cd CA4
   mkdir -p edge-site cloud-site vpn-config failure-drills scripts docs demo
   ```
3. **Start with cloud site modifications** (easiest to test first)
4. **Then add VPN** (incremental validation)
5. **Finally add edge site** (complete the architecture)

---

**Good luck with CA4!** 🚀

You've already built a solid foundation with CA2. This is about extending it to a realistic multi-site deployment. Take it step-by-step, test incrementally, and you'll have an impressive final project.

---

**Questions?** Review the implementation plan or refer to CA2 documentation for proven patterns.
