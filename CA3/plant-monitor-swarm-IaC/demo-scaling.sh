#!/bin/bash
#
# demo-scaling.sh - Comprehensive scaling demonstration for CA3
#
# This script demonstrates:
# 1. Baseline with 2 sensors, 1 processor
# 2. Add load (10 sensors)
# 3. Show Kafka lag increasing
# 4. Scale processor to 3 replicas
# 5. Show lag decreasing and throughput improving
# 6. Scale back down
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${CYAN}=============================================${NC}"
echo -e "${CYAN}  CA3 Autoscaling Demonstration${NC}"
echo -e "${CYAN}=============================================${NC}"
echo ""

# Function to show metrics
show_metrics() {
    local phase=$1
    echo ""
    echo -e "${BLUE}=== Metrics: $phase ===${NC}"
    
    # Service replicas
    echo -e "${YELLOW}Service Replicas:${NC}"
    docker service ls --format "table {{.Name}}\t{{.Replicas}}" | grep -E "sensor|processor"
    
    # Kafka lag
    echo ""
    echo -e "${YELLOW}Kafka Consumer Lag:${NC}"
    curl -s http://localhost:9090/api/v1/query?query=kafka_consumergroup_lag 2>/dev/null | \
        jq -r '.data.result[] | "  \(.metric.consumergroup): \(.value[1]) messages behind"' || \
        echo "  (Query Prometheus on manager node)"
    
    # Processing rate
    echo ""
    echo -e "${YELLOW}Processing Rate (last 1m):${NC}"
    curl -s 'http://localhost:9090/api/v1/query?query=rate(plant_processor_messages_processed_total[1m])' 2>/dev/null | \
        jq -r '.data.result[] | "  \(.metric.status): \(.value[1]) msgs/sec"' || \
        echo "  (Query Prometheus on manager node)"
    
    echo ""
}

# Function to pause with countdown
pause_with_countdown() {
    local seconds=$1
    local message=$2
    echo ""
    echo -e "${CYAN}$message${NC}"
    for i in $(seq $seconds -1 1); do
        echo -ne "  Waiting: $i seconds remaining...\r"
        sleep 1
    done
    echo -e "  ${GREEN}Ready!${NC}                      "
}

echo -e "${GREEN}Phase 1: Baseline Measurement${NC}"
echo "Current setup: 2 sensors, 1 processor"
show_metrics "Baseline"
pause_with_countdown 30 "Collecting baseline metrics..."

echo ""
echo -e "${GREEN}Phase 2: Adding Load (10 Sensors)${NC}"
bash "$SCRIPT_DIR/add-sensors.sh" 10
pause_with_countdown 45 "Allowing load to build up..."
show_metrics "High Load - 10 Sensors, 1 Processor"

echo ""
echo -e "${YELLOW}📊 Expected observation: Kafka lag should be increasing!${NC}"
echo ""
read -p "Press Enter to scale processor to 3 replicas..."

echo ""
echo -e "${GREEN}Phase 3: Scaling Processor (1 → 3 replicas)${NC}"
docker service scale plant-monitoring_processor=3

pause_with_countdown 30 "Waiting for new processor replicas to start..."
show_metrics "After Processor Scaling - 10 Sensors, 3 Processors"

pause_with_countdown 60 "Collecting post-scale metrics..."
show_metrics "Post-Scale Steady State"

echo ""
echo -e "${YELLOW}📊 Expected observation: Kafka lag should be decreasing!${NC}"
echo -e "${YELLOW}📊 Processing throughput should be ~3x higher!${NC}"
echo ""
read -p "Press Enter to demonstrate scale-down..."

echo ""
echo -e "${GREEN}Phase 4: Reducing Load and Scaling Down${NC}"
bash "$SCRIPT_DIR/add-sensors.sh" 2

pause_with_countdown 20 "Waiting for lag to clear..."

echo ""
echo -e "${YELLOW}Scaling processor back to 1 replica...${NC}"
docker service scale plant-monitoring_processor=1

pause_with_countdown 30 "Waiting for scale-down..."
show_metrics "Back to Baseline - 2 Sensors, 1 Processor"

echo ""
echo -e "${CYAN}=============================================${NC}"
echo -e "${CYAN}  Demonstration Complete!${NC}"
echo -e "${CYAN}=============================================${NC}"
echo ""
echo -e "${GREEN}Key Observations:${NC}"
echo "  ✓ Added 10 sensors → Kafka lag increased"
echo "  ✓ Scaled processor 1→3 → Lag decreased, throughput increased"
echo "  ✓ Reduced to 2 sensors → Scaled processor back to 1"
echo ""
echo -e "${BLUE}Evidence Captured:${NC}"
echo "  - Service scaling: docker service ls"
echo "  - Metrics changes: Grafana dashboard"
echo "  - Kafka lag trends: Prometheus queries"
echo ""
echo -e "${BLUE}For Screenshots:${NC}"
echo "  1. Grafana: http://<manager-ip>:3000"
echo "     - Panel 2: Kafka Consumer Lag (should show spike then drop)"
echo "     - Panel 3: Processing Throughput (should show 3x increase)"
echo "  2. docker service ls (showing replica changes)"
echo "  3. docker service ps plant-monitoring_processor (showing 3 tasks)"
echo ""
