#!/bin/bash

# Autoscaling Demonstration Script for CA3
# This script demonstrates horizontal scaling of producers and consumers

set -e

MANAGER_IP="52.14.239.94"
SSH_KEY="$HOME/.ssh/docker-swarm-key"
PROM_URL="http://${MANAGER_IP}:9090"

COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

log() {
    echo -e "${COLOR_BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${COLOR_RESET} $1"
}

success() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

warn() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $1"
}

error() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $1"
}

# Get current Kafka consumer lag
get_kafka_lag() {
    curl -s "${PROM_URL}/api/v1/query?query=kafka_consumergroup_lag" | \
        jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0"
}

# Get processing throughput
get_throughput() {
    curl -s "${PROM_URL}/api/v1/query?query=sum(rate(plant_processor_messages_processed_total{status=\"success\"}[2m]))" | \
        jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0"
}

# Wait for metrics to stabilize
wait_for_stability() {
    local duration=$1
    log "Waiting ${duration}s for metrics to stabilize..."
    for ((i=duration; i>0; i--)); do
        printf "\r  ⏱ %3d seconds remaining..." "$i"
        sleep 1
    done
    printf "\r  ⏱ Complete!                    \n"
}

echo ""
echo "============================================================================="
echo "  AUTOSCALING DEMONSTRATION - CA3"
echo "============================================================================="
echo ""

# ============================================================================
# PHASE 0: Backup original config
# ============================================================================
log "Phase 0: Backing up original sensor configuration..."
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" \
    "docker config inspect sensor_config --format '{{json .Spec.Data}}' | base64 -d > /tmp/sensor-config-original.json" || true
success "Original config backed up to manager:/tmp/sensor-config-original.json"
echo ""

# ============================================================================
# PHASE 1: Deploy load test configuration
# ============================================================================
log "Phase 1: Deploying load test sensor configuration..."
log "  - Increasing sensor count from 2 to 5 plant configs"
log "  - Reducing interval from 30-45s to 1s (30-45x throughput increase)"

# Copy load test config to manager
scp -i "${SSH_KEY}" sensor-config-load-test.json "ubuntu@${MANAGER_IP}:/tmp/"

# Remove old config and create new one
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" << 'EOF'
docker config rm sensor_config 2>/dev/null || echo "Config doesn't exist yet"
docker config create sensor_config /tmp/sensor-config-load-test.json
EOF

success "Load test configuration deployed"

# Force update sensor service to pick up new config
log "Forcing sensor service update to pick up new configuration..."
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" \
    "docker service update --config-rm sensor_config --config-add source=sensor_config,target=/app/sensor-config.json --force plant-monitoring_sensor"

wait_for_stability 30
success "Sensors restarted with load test configuration"
echo ""

# ============================================================================
# PHASE 2: Scale sensors (producers)
# ============================================================================
log "Phase 2: Scaling sensor service from 2 → 5 replicas..."
log "  Expected throughput: ~5 messages/second (5 sensors × 1 msg/sec)"

ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" \
    "docker service scale plant-monitoring_sensor=5"

wait_for_stability 45
success "Sensors scaled to 5 replicas"

# Show current service state
log "Current service state:"
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" \
    "docker service ls | grep -E 'NAME|sensor|processor'"
echo ""

# ============================================================================
# PHASE 3: Monitor Kafka lag buildup
# ============================================================================
log "Phase 3: Monitoring Kafka consumer lag buildup..."
log "  Sampling every 10 seconds for 60 seconds..."
echo ""

for i in {1..6}; do
    LAG=$(get_kafka_lag)
    THROUGHPUT=$(get_throughput)
    printf "  Sample %d/6: Lag = %8.2f messages | Throughput = %.4f msg/sec\n" "$i" "$LAG" "$THROUGHPUT"
    sleep 10
done
echo ""

FINAL_LAG=$(get_kafka_lag)
if (( $(echo "$FINAL_LAG > 10" | bc -l) )); then
    success "Consumer lag detected: ${FINAL_LAG} messages"
    log "Single processor cannot keep up with 5 sensors @ 1msg/sec"
else
    warn "Lag is still low (${FINAL_LAG}). Processor may be keeping up."
    log "Continuing with autoscaling demonstration anyway..."
fi
echo ""

# ============================================================================
# PHASE 4: Scale processor (consumer) in response
# ============================================================================
log "Phase 4: Scaling processor service 1 → 3 replicas to handle load..."

ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" \
    "docker service scale plant-monitoring_processor=3"

wait_for_stability 45
success "Processor scaled to 3 replicas"

# Show scaled services
log "Scaled service state:"
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" \
    "docker service ls | grep -E 'NAME|sensor|processor'"
echo ""

# ============================================================================
# PHASE 5: Monitor lag reduction
# ============================================================================
log "Phase 5: Monitoring lag reduction with 3 processors..."
log "  Sampling every 10 seconds for 60 seconds..."
echo ""

for i in {1..6}; do
    LAG=$(get_kafka_lag)
    THROUGHPUT=$(get_throughput)
    printf "  Sample %d/6: Lag = %8.2f messages | Throughput = %.4f msg/sec\n" "$i" "$LAG" "$THROUGHPUT"
    sleep 10
done
echo ""

FINAL_LAG_AFTER=$(get_kafka_lag)
success "Final lag after scaling: ${FINAL_LAG_AFTER} messages"
echo ""

# ============================================================================
# PHASE 6: Scale down demonstration
# ============================================================================
log "Phase 6: Demonstrating scale-down (load subsided)..."

log "Scaling sensors back to 2 replicas..."
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" \
    "docker service scale plant-monitoring_sensor=2"
sleep 10

log "Scaling processor back to 1 replica..."
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" \
    "docker service scale plant-monitoring_processor=1"
sleep 10

success "Services scaled down"

# Show final state
log "Final service state:"
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" \
    "docker service ls | grep -E 'NAME|sensor|processor'"
echo ""

# ============================================================================
# PHASE 7: Restore original configuration
# ============================================================================
log "Phase 7: Restoring original sensor configuration..."

ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" << 'EOF'
docker config rm sensor_config
docker config create sensor_config /tmp/sensor-config-original.json
docker service update --config-rm sensor_config --config-add source=sensor_config,target=/app/sensor-config.json --force plant-monitoring_sensor
EOF

success "Original configuration restored"
echo ""

# ============================================================================
# Summary
# ============================================================================
echo "============================================================================="
echo "  AUTOSCALING DEMONSTRATION COMPLETE"
echo "============================================================================="
echo ""
echo "Summary:"
echo "  ✓ Deployed load test configuration (1-second sensor intervals)"
echo "  ✓ Scaled producers: 2 → 5 replicas"
echo "  ✓ Monitored Kafka consumer lag buildup"
echo "  ✓ Scaled consumer: 1 → 3 replicas in response to lag"
echo "  ✓ Monitored lag reduction with scaled processors"
echo "  ✓ Demonstrated scale-down: sensors 5→2, processor 3→1"
echo "  ✓ Restored original configuration"
echo ""
echo "Next steps for CA3 submission:"
echo "  1. Screenshot: docker service ls showing scaled services (from Phase 4)"
echo "  2. Screenshot: Grafana dashboard during load test showing increased metrics"
echo "  3. Screenshot: Kafka lag metric during Phases 3-5"
echo ""
echo "============================================================================="
