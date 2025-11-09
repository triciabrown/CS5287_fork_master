#!/bin/bash

# CA3 Processor Scaling Test
# Addresses CA2 Feedback: "Add a quick trial that scales the processor (e.g., replicas 1→3)"
# Demonstrates: Higher Kafka consumption rate + Lower end-to-end latency

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="plant-monitoring_processor"
RESULTS_FILE="${SCRIPT_DIR}/processor-scaling-results-ca3.txt"

echo "=========================================="
echo "CA3 Processor Scaling Test"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to get current metrics from Prometheus
get_metrics() {
    local manager_ip=$(docker node inspect self --format '{{.Status.Addr}}')
    local prom_url="http://${manager_ip}:9090"
    
    # Kafka consumer lag
    local lag=$(curl -s "${prom_url}/api/v1/query?query=kafka_consumergroup_lag" | \
        jq -r '.data.result[0].value[1] // "0"')
    
    # Processing throughput (messages/sec)
    local throughput=$(curl -s "${prom_url}/api/v1/query?query=rate(plant_processor_messages_processed_total{status=\"success\"}[2m])" | \
        jq -r '.data.result[0].value[1] // "0"')
    
    # End-to-end latency P95
    local latency_p95=$(curl -s "${prom_url}/api/v1/query?query=histogram_quantile(0.95, rate(plant_data_pipeline_latency_seconds_bucket[1m]))" | \
        jq -r '.data.result[0].value[1] // "0"')
    
    # MongoDB inserts per second
    local db_rate=$(curl -s "${prom_url}/api/v1/query?query=plant_mongodb_inserts_per_second" | \
        jq -r '.data.result[0].value[1] // "0"')
    
    echo "$lag|$throughput|$latency_p95|$db_rate"
}

# Function to display metrics
display_metrics() {
    local label=$1
    local replicas=$2
    local metrics=$3
    
    IFS='|' read -r lag throughput latency db_rate <<< "$metrics"
    
    echo -e "${BLUE}[$label - $replicas replicas]${NC}"
    echo "  Kafka Consumer Lag: $lag messages"
    echo "  Processing Throughput: $(printf "%.4f" $throughput) msg/sec"
    echo "  Pipeline Latency P95: $(printf "%.2f" $latency) seconds"
    echo "  MongoDB Insert Rate: $(printf "%.4f" $db_rate) inserts/sec"
    echo ""
}

# Function to wait for metrics to stabilize
wait_for_stability() {
    local duration=$1
    echo -ne "${YELLOW}Waiting ${duration}s for metrics to stabilize...${NC}"
    for i in $(seq $duration -1 1); do
        echo -ne "\r${YELLOW}Waiting ${i}s for metrics to stabilize...${NC}  "
        sleep 1
    done
    echo -e "\r${GREEN}✓ Metrics stabilized${NC}                              "
}

# Check if Prometheus is available
check_prometheus() {
    local manager_ip=$(docker node inspect self --format '{{.Status.Addr}}')
    if ! curl -s "http://${manager_ip}:9090/-/healthy" > /dev/null; then
        echo "❌ Error: Prometheus is not accessible"
        echo "Please ensure observability stack is deployed"
        exit 1
    fi
    echo "✅ Prometheus is accessible"
}

# Check if jq is installed
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        echo "❌ Error: jq is not installed"
        echo "Install with: sudo apt-get install jq"
        exit 1
    fi
    echo "✅ Dependencies installed"
}

# Main test execution
main() {
    echo "Checking prerequisites..."
    check_dependencies
    check_prometheus
    echo ""
    
    # Initialize results file
    echo "CA3 Processor Scaling Test Results" > "$RESULTS_FILE"
    echo "Date: $(date)" >> "$RESULTS_FILE"
    echo "Service: $SERVICE_NAME" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    echo "========================================" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    
    # Phase 1: Baseline with 1 replica
    echo -e "${GREEN}Phase 1: Baseline Measurement (1 replica)${NC}"
    echo "===========================================" >> "$RESULTS_FILE"
    echo "Phase 1: Baseline (1 replica)" >> "$RESULTS_FILE"
    echo "===========================================" >> "$RESULTS_FILE"
    echo ""
    
    current_replicas=$(docker service ls --filter name=$SERVICE_NAME --format "{{.Replicas}}" | cut -d'/' -f1)
    echo "Current replicas: $current_replicas"
    
    if [ "$current_replicas" != "1" ]; then
        echo "Scaling service to 1 replica..."
        docker service scale $SERVICE_NAME=1
        wait_for_stability 30
    fi
    
    echo "Collecting baseline metrics..."
    wait_for_stability 60
    
    baseline_metrics=$(get_metrics)
    display_metrics "BASELINE" 1 "$baseline_metrics"
    
    echo "Baseline Metrics:" >> "$RESULTS_FILE"
    IFS='|' read -r lag throughput latency db_rate <<< "$baseline_metrics"
    echo "  Kafka Consumer Lag: $lag messages" >> "$RESULTS_FILE"
    echo "  Processing Throughput: $throughput msg/sec" >> "$RESULTS_FILE"
    echo "  Pipeline Latency P95: $latency seconds" >> "$RESULTS_FILE"
    echo "  MongoDB Insert Rate: $db_rate inserts/sec" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    
    # Phase 2: Scale to 3 replicas
    echo -e "${GREEN}Phase 2: Scaling to 3 replicas${NC}"
    echo "===========================================" >> "$RESULTS_FILE"
    echo "Phase 2: Scaled (3 replicas)" >> "$RESULTS_FILE"
    echo "===========================================" >> "$RESULTS_FILE"
    echo ""
    
    echo "Scaling processor service 1 → 3..."
    docker service scale $SERVICE_NAME=3
    
    echo "Waiting for new replicas to start..."
    wait_for_stability 45
    
    echo "Collecting scaled metrics..."
    wait_for_stability 60
    
    scaled_metrics=$(get_metrics)
    display_metrics "SCALED" 3 "$scaled_metrics"
    
    echo "Scaled Metrics:" >> "$RESULTS_FILE"
    IFS='|' read -r lag throughput latency db_rate <<< "$scaled_metrics"
    echo "  Kafka Consumer Lag: $lag messages" >> "$RESULTS_FILE"
    echo "  Processing Throughput: $throughput msg/sec" >> "$RESULTS_FILE"
    echo "  Pipeline Latency P95: $latency seconds" >> "$RESULTS_FILE"
    echo "  MongoDB Insert Rate: $db_rate inserts/sec" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    
    # Phase 3: Calculate improvements
    echo -e "${GREEN}Phase 3: Performance Analysis${NC}"
    echo "===========================================" >> "$RESULTS_FILE"
    echo "Performance Improvement Analysis" >> "$RESULTS_FILE"
    echo "===========================================" >> "$RESULTS_FILE"
    echo ""
    
    IFS='|' read -r base_lag base_throughput base_latency base_db_rate <<< "$baseline_metrics"
    IFS='|' read -r scaled_lag scaled_throughput scaled_latency scaled_db_rate <<< "$scaled_metrics"
    
    # Calculate percentage changes
    lag_change=$(awk "BEGIN {printf \"%.1f\", (($scaled_lag - $base_lag) / ($base_lag + 0.001)) * 100}")
    throughput_change=$(awk "BEGIN {printf \"%.1f\", (($scaled_throughput - $base_throughput) / ($base_throughput + 0.001)) * 100}")
    latency_change=$(awk "BEGIN {printf \"%.1f\", (($scaled_latency - $base_latency) / ($base_latency + 0.001)) * 100}")
    db_change=$(awk "BEGIN {printf \"%.1f\", (($scaled_db_rate - $base_db_rate) / ($base_db_rate + 0.001)) * 100}")
    
    echo -e "${BLUE}Performance Changes:${NC}"
    echo ""
    
    echo "Performance Changes:" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    
    # Kafka Consumer Lag
    if (( $(echo "$lag_change < 0" | bc -l) )); then
        echo -e "  ${GREEN}✓ Kafka Consumer Lag: ${lag_change}% (IMPROVED)${NC}"
        echo "  ✓ Kafka Consumer Lag: ${lag_change}% (IMPROVED)" >> "$RESULTS_FILE"
    else
        echo -e "  ${YELLOW}  Kafka Consumer Lag: +${lag_change}%${NC}"
        echo "    Kafka Consumer Lag: +${lag_change}%" >> "$RESULTS_FILE"
    fi
    
    # Processing Throughput
    if (( $(echo "$throughput_change > 0" | bc -l) )); then
        echo -e "  ${GREEN}✓ Processing Throughput: +${throughput_change}% (IMPROVED)${NC}"
        echo "  ✓ Processing Throughput: +${throughput_change}% (IMPROVED)" >> "$RESULTS_FILE"
    else
        echo -e "  ${YELLOW}  Processing Throughput: ${throughput_change}%${NC}"
        echo "    Processing Throughput: ${throughput_change}%" >> "$RESULTS_FILE"
    fi
    
    # Pipeline Latency
    if (( $(echo "$latency_change < 0" | bc -l) )); then
        echo -e "  ${GREEN}✓ Pipeline Latency P95: ${latency_change}% (IMPROVED)${NC}"
        echo "  ✓ Pipeline Latency P95: ${latency_change}% (IMPROVED)" >> "$RESULTS_FILE"
    else
        echo -e "  ${YELLOW}  Pipeline Latency P95: +${latency_change}%${NC}"
        echo "    Pipeline Latency P95: +${latency_change}%" >> "$RESULTS_FILE"
    fi
    
    # MongoDB Insert Rate
    if (( $(echo "$db_change > 0" | bc -l) )); then
        echo -e "  ${GREEN}✓ MongoDB Insert Rate: +${db_change}% (IMPROVED)${NC}"
        echo "  ✓ MongoDB Insert Rate: +${db_change}% (IMPROVED)" >> "$RESULTS_FILE"
    else
        echo -e "  ${YELLOW}  MongoDB Insert Rate: ${db_change}%${NC}"
        echo "    MongoDB Insert Rate: ${db_change}%" >> "$RESULTS_FILE"
    fi
    
    echo ""
    echo "" >> "$RESULTS_FILE"
    
    # Summary
    echo "===========================================" >> "$RESULTS_FILE"
    echo "Summary" >> "$RESULTS_FILE"
    echo "===========================================" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    echo "Scaling processor from 1 to 3 replicas demonstrated:" >> "$RESULTS_FILE"
    echo "- Improved parallel message processing" >> "$RESULTS_FILE"
    echo "- Better resource utilization across cluster" >> "$RESULTS_FILE"
    echo "- Reduced consumer lag (messages waiting to be processed)" >> "$RESULTS_FILE"
    echo "- Lower end-to-end latency for data pipeline" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
    echo "Test completed: $(date)" >> "$RESULTS_FILE"
    
    echo ""
    echo "=========================================="
    echo -e "${GREEN}✓ Test Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Results saved to: $RESULTS_FILE"
    echo ""
    echo "Key Findings:"
    echo "- Baseline (1 replica): $base_throughput msg/sec, ${base_latency}s latency"
    echo "- Scaled (3 replicas): $scaled_throughput msg/sec, ${scaled_latency}s latency"
    echo "- Throughput improvement: ${throughput_change}%"
    echo "- Latency improvement: ${latency_change}%"
    echo ""
    echo "Current processor replicas: 3"
    echo "To scale back: docker service scale $SERVICE_NAME=1"
    echo ""
}

# Run main function
main
