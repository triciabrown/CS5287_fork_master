#!/bin/bash
# CA3 Evidence Collection Script
# Automates screenshot capture and test execution for grading submission

set -e

MANAGER_IP="18.219.157.100"
SSH_KEY="~/.ssh/docker-swarm-key"
GRAFANA_URL="http://${MANAGER_IP}:3000"
PROMETHEUS_URL="http://${MANAGER_IP}:9090"
SCREENSHOTS_DIR="screenshots"
RESULTS_DIR="results"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  CA3 Evidence Collection Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Create directories
mkdir -p "$SCREENSHOTS_DIR" "$RESULTS_DIR"

# Function to check if Grafana is accessible
check_grafana() {
    echo -e "${YELLOW}[1/6] Checking Grafana accessibility...${NC}"
    if curl -s -o /dev/null -w "%{http_code}" "${GRAFANA_URL}/api/health" | grep -q "200"; then
        echo -e "${GREEN}✅ Grafana is accessible at ${GRAFANA_URL}${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}❌ Grafana is not accessible. Please check the service.${NC}"
        echo ""
        return 1
    fi
}

# Function to import Grafana dashboard
import_dashboard() {
    echo -e "${YELLOW}[2/6] Importing Grafana Dashboard...${NC}"
    
    # Check if dashboard file exists
    if [ ! -f "configs/grafana-plant-monitoring-dashboard.json" ]; then
        echo -e "${RED}❌ Dashboard file not found: configs/grafana-plant-monitoring-dashboard.json${NC}"
        return 1
    fi
    
    # Import dashboard via API
    DASHBOARD_JSON=$(cat configs/grafana-plant-monitoring-dashboard.json)
    
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "admin:admin" \
        -d "{\"dashboard\": ${DASHBOARD_JSON}, \"overwrite\": true}" \
        "${GRAFANA_URL}/api/dashboards/db" 2>&1)
    
    if echo "$RESPONSE" | grep -q "success"; then
        echo -e "${GREEN}✅ Dashboard imported successfully${NC}"
        echo -e "${BLUE}   Access it at: ${GRAFANA_URL}/d/plant-monitoring${NC}"
    else
        echo -e "${YELLOW}⚠️  Dashboard may already exist or import failed${NC}"
        echo -e "${BLUE}   You can import manually: Dashboard → Import → Upload JSON${NC}"
    fi
    echo ""
}

# Function to display manual screenshot instructions
manual_screenshots() {
    echo -e "${YELLOW}[3/6] Grafana & Loki Screenshots (Manual)${NC}"
    echo ""
    echo -e "${BLUE}📸 Please capture the following screenshots manually:${NC}"
    echo ""
    echo -e "${GREEN}Screenshot 1: Grafana Dashboard Overview${NC}"
    echo "  1. Open: ${GRAFANA_URL}"
    echo "  2. Login: admin / admin"
    echo "  3. Navigate to: Dashboards → Plant Monitoring Dashboard"
    echo "  4. Wait for data to load (30 seconds)"
    echo "  5. Screenshot showing all 11 panels with live metrics"
    echo "  6. Save as: ${SCREENSHOTS_DIR}/grafana-dashboard-overview-ca3.png"
    echo ""
    echo -e "${GREEN}Screenshot 2: Loki Log Search${NC}"
    echo "  1. In Grafana, click 'Explore' (compass icon)"
    echo "  2. Select 'Loki' data source"
    echo "  3. Query: {stack=\"plant-monitor\"} |~ \"(?i)(error|sensor|processor|kafka)\""
    echo "  4. Time range: Last 30 minutes"
    echo "  5. Click 'Run query'"
    echo "  6. Screenshot showing logs with timestamps and labels"
    echo "  7. Save as: ${SCREENSHOTS_DIR}/loki-logs-ca3.png"
    echo ""
    echo -e "${GREEN}Screenshot 3: Prometheus Targets${NC}"
    echo "  1. Open: ${PROMETHEUS_URL}/targets"
    echo "  2. Screenshot showing all targets UP (sensor, processor, kafka, mongodb, node exporters)"
    echo "  3. Save as: ${SCREENSHOTS_DIR}/prometheus-targets-ca3.png"
    echo ""
    echo -e "${YELLOW}Press ENTER when you've captured these screenshots...${NC}"
    read -r
    echo ""
}

# Function to capture service status
capture_service_status() {
    echo -e "${YELLOW}[4/6] Capturing Service Status...${NC}"
    
    echo "Capturing initial service state..."
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" 'docker service ls' > "${RESULTS_DIR}/services-initial.txt"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" 'docker service ls | grep plant-monitor' > "${RESULTS_DIR}/application-services.txt"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" 'docker service ls | grep monitoring' > "${RESULTS_DIR}/monitoring-services.txt"
    
    echo -e "${GREEN}✅ Service status saved to ${RESULTS_DIR}/services-initial.txt${NC}"
    echo ""
}

# Function to run processor scaling test
run_scaling_test() {
    echo -e "${YELLOW}[5/6] Running Processor Scaling Test...${NC}"
    echo ""
    echo -e "${BLUE}This will take approximately 5 minutes...${NC}"
    echo ""
    
    # Copy load test script to manager
    echo "Copying load test script to manager node..."
    scp -i "$SSH_KEY" load-test-processor.sh ubuntu@"$MANAGER_IP":~/
    
    # Run the test
    echo "Starting load test..."
    echo "-----------------------------------"
    ssh -i "$SSH_KEY" ubuntu@"$MANAGER_IP" 'bash ~/load-test-processor.sh' | tee "${RESULTS_DIR}/processor-scaling-results-ca3.txt"
    echo "-----------------------------------"
    
    echo ""
    echo -e "${GREEN}✅ Scaling test complete${NC}"
    echo -e "${BLUE}   Results saved to: ${RESULTS_DIR}/processor-scaling-results-ca3.txt${NC}"
    echo ""
    echo -e "${YELLOW}📸 REQUIRED: Capture screenshot of Grafana dashboard during/after test${NC}"
    echo "   - Show processor replicas scaling 1→3→1"
    echo "   - Show throughput/latency improvements"
    echo "   - Save as: ${SCREENSHOTS_DIR}/processor-scaling-grafana-ca3.png"
    echo ""
    echo -e "${YELLOW}Press ENTER when you've captured the scaling screenshot...${NC}"
    read -r
    echo ""
}

# Function to display resilience test instructions
resilience_instructions() {
    echo -e "${YELLOW}[6/6] Resilience Testing Instructions${NC}"
    echo ""
    echo -e "${BLUE}🎥 Record a 2-3 minute video demonstrating:${NC}"
    echo ""
    echo -e "${GREEN}Part 1: Initial State (30 seconds)${NC}"
    echo "  SSH to manager: ssh -i $SSH_KEY ubuntu@$MANAGER_IP"
    echo "  Run: docker service ls"
    echo "  Narrate: 'All services running normally with expected replica counts'"
    echo ""
    echo -e "${GREEN}Part 2: Failure Injection (1 minute)${NC}"
    echo "  docker service update --force plant-monitor_sensor"
    echo "  docker service update --force plant-monitor_processor"
    echo "  docker service update --force plant-monitor_kafka"
    echo "  Narrate: 'Simulating failures across all tiers of the pipeline'"
    echo ""
    echo -e "${GREEN}Part 3: Self-Healing Verification (1 minute)${NC}"
    echo "  docker service ps plant-monitor_sensor --no-trunc"
    echo "  docker service ps plant-monitor_processor --no-trunc"
    echo "  Show task states: Running → Shutdown → Starting → Running"
    echo "  Narrate: 'Swarm detected failures and automatically restarted tasks'"
    echo ""
    echo -e "${GREEN}Part 4: Operator Troubleshooting (30 seconds)${NC}"
    echo "  docker service logs plant-monitor_processor --tail 20"
    echo "  Open Grafana dashboard in browser (split screen)"
    echo "  Point out: 'Metrics show brief gap during restart, then recovery'"
    echo "  Narrate: 'Verified recovery through logs and observability dashboard'"
    echo ""
    echo -e "${BLUE}Save video as: resilience-drill-ca3.mp4${NC}"
    echo ""
    echo -e "${YELLOW}Additional screenshots for resilience:${NC}"
    echo "  1. Before failure: docker service ls → ${SCREENSHOTS_DIR}/resilience-before-ca3.png"
    echo "  2. During recovery: docker service ps plant-monitor_processor → ${SCREENSHOTS_DIR}/resilience-recovery-ca3.png"
    echo "  3. After recovery: docker service ls → ${SCREENSHOTS_DIR}/resilience-after-ca3.png"
    echo ""
}

# Function to display AWS screenshots instructions
aws_screenshots() {
    echo -e "${YELLOW}AWS Console Screenshots${NC}"
    echo ""
    echo -e "${BLUE}📸 Please capture these AWS Console screenshots:${NC}"
    echo ""
    echo -e "${GREEN}Screenshot 1: Security Groups${NC}"
    echo "  1. AWS Console → EC2 → Security Groups"
    echo "  2. Show all 5 security groups:"
    echo "     - frontend_tier_sg (sg-0e8c483c259cae167)"
    echo "     - messaging_tier_sg (sg-067dfb02784ef0da9)"
    echo "     - data_tier_sg (sg-03cf4062a5cd54ddf)"
    echo "     - swarm_manager_sg (sg-085b65db9a65b57a7)"
    echo "     - swarm_worker_sg (sg-063183f73fd9bad76)"
    echo "  3. Save as: ${SCREENSHOTS_DIR}/aws-security-groups-ca3.png"
    echo ""
    echo -e "${GREEN}Screenshot 2: EC2 Instances${NC}"
    echo "  1. AWS Console → EC2 → Instances"
    echo "  2. Show 5 running instances (1 manager + 4 workers)"
    echo "  3. Visible columns: Name, Instance ID, Type, State, Security Groups"
    echo "  4. Save as: ${SCREENSHOTS_DIR}/aws-ec2-instances-ca3.png"
    echo ""
    echo -e "${GREEN}Screenshot 3: Security Group Rules (Detailed)${NC}"
    echo "  1. Click on 'data_tier_sg'"
    echo "  2. Screenshot 'Inbound rules' tab showing:"
    echo "     - Port 3000 (Grafana) from 0.0.0.0/0"
    echo "     - Port 9090 (Prometheus) from 0.0.0.0/0"
    echo "     - Port 27017 (MongoDB) from VPC CIDR"
    echo "  3. Save as: ${SCREENSHOTS_DIR}/aws-security-group-rules-ca3.png"
    echo ""
}

# Function to generate summary report
generate_summary() {
    echo -e "${YELLOW}Generating Evidence Summary...${NC}"
    
    cat > "${RESULTS_DIR}/evidence-checklist.md" << 'EOF'
# CA3 Evidence Checklist

## Observability (25 points)

### Screenshots Captured:
- [ ] `screenshots/grafana-dashboard-overview-ca3.png` - Shows all 11 panels with live metrics
- [ ] `screenshots/loki-logs-ca3.png` - Log search showing structured logs across services
- [ ] `screenshots/prometheus-targets-ca3.png` - All targets UP (15 custom metrics)

### Files:
- [x] `configs/grafana-plant-monitoring-dashboard.json` - Dashboard configuration
- [x] `observability-stack.yml` - Loki, Promtail, Prometheus, Grafana deployment
- [x] `docs/OBSERVABILITY_GUIDE.md` - Complete observability documentation

**Expected Points: 20/25** (missing 5 for TLS)

---

## Autoscaling (20 points)

### Screenshots Captured:
- [ ] `screenshots/processor-scaling-grafana-ca3.png` - Grafana showing scaling 1→3→1

### Files:
- [x] `load-test-processor.sh` - Load testing script
- [x] `results/processor-scaling-results-ca3.txt` - Test execution output
- [x] `results/services-initial.txt` - Initial service state
- [x] `results/application-services.txt` - Application service status

**Expected Points: 15/20** (5 points for documentation)

---

## Security Hardening (20 points)

### Screenshots Captured:
- [ ] `screenshots/aws-security-groups-ca3.png` - All 5 security groups visible
- [ ] `screenshots/aws-ec2-instances-ca3.png` - EC2 instances with security groups
- [ ] `screenshots/aws-security-group-rules-ca3.png` - Detailed inbound rules

### Files:
- [x] `terraform/security-groups-tiers.tf` - Tier-based security groups
- [x] `docker-compose.yml` - Network isolation (3 tiers) + Docker secrets
- [x] `docs/NETWORK_ISOLATION.md` - Network architecture documentation
- [x] `docs/SECURITY_GROUPS.md` - Security group documentation

**Expected Points: 14/20** (missing 6 for TLS implementation)

---

## Resilience (25 points)

### Video:
- [ ] `resilience-drill-ca3.mp4` - 2-3 min video showing failure injection and recovery

### Screenshots Captured:
- [ ] `screenshots/resilience-before-ca3.png` - Initial state
- [ ] `screenshots/resilience-recovery-ca3.png` - Service recovery in progress
- [ ] `screenshots/resilience-after-ca3.png` - Final state after recovery

### Files:
- [x] Docker Swarm configured with restart policies
- [x] Health checks implemented in docker-compose.yml

**Expected Points: 20/25** (5 points for documentation)

---

## Documentation (10 points)

### Files:
- [x] `START_HERE.md` - Comprehensive deployment guide
- [x] `CA3_IMPROVEMENTS_CA2_FEEDBACK.md` - CA2 feedback addressed
- [x] `docs/OBSERVABILITY_GUIDE.md` - Observability setup
- [x] `docs/NETWORK_ISOLATION.md` - Network architecture
- [x] `docs/SECURITY_GROUPS.md` - Security configuration
- [ ] `README.md` - Updated with CA3 sections (needs 4 sections added)

**Expected Points: 7/10** (3 points for README update)

---

## Total Expected Score

**Current State: 76/100** (C+)
**With Screenshots & Video: 94/100** (A)
**With TLS Implementation: 99/100** (A+)

---

## Next Steps

1. **Immediate (30 minutes)**:
   - [ ] Capture all screenshots listed above
   - [ ] Record resilience drill video
   - [ ] Update README.md with 4 sections

2. **Optional (1 hour)**:
   - [ ] Implement TLS for Kafka and MongoDB (+11 points)
   - [ ] Add more detailed autoscaling documentation (+5 points)

EOF

    echo -e "${GREEN}✅ Evidence checklist created: ${RESULTS_DIR}/evidence-checklist.md${NC}"
    echo ""
}

# Main execution
main() {
    check_grafana || exit 1
    import_dashboard
    manual_screenshots
    capture_service_status
    run_scaling_test
    resilience_instructions
    aws_screenshots
    generate_summary
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}  Evidence Collection Complete!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Summary:${NC}"
    echo "  - Service status captured in: ${RESULTS_DIR}/"
    echo "  - Scaling test results: ${RESULTS_DIR}/processor-scaling-results-ca3.txt"
    echo "  - Evidence checklist: ${RESULTS_DIR}/evidence-checklist.md"
    echo ""
    echo -e "${YELLOW}Still TODO:${NC}"
    echo "  - Capture 9 screenshots (Grafana, Loki, AWS Console, Resilience)"
    echo "  - Record resilience drill video (2-3 min)"
    echo "  - Update README.md with CA3 sections"
    echo ""
    echo -e "${BLUE}Estimated time to completion: 30 minutes${NC}"
    echo -e "${BLUE}Expected grade: 94/100 (A)${NC}"
    echo ""
    echo -e "${GREEN}Review checklist: cat ${RESULTS_DIR}/evidence-checklist.md${NC}"
    echo ""
}

# Run main function
main
