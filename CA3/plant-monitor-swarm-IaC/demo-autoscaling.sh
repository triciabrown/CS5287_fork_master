#!/bin/bash

# Simplified Autoscaling Demonstration for CA3
# Demonstrates horizontal scaling capability

set -e

MANAGER_IP="52.14.239.94"
SSH_KEY="$HOME/.ssh/docker-swarm-key"

echo "============================================================================="
echo "  AUTOSCALING DEMONSTRATION - CA3"
echo "============================================================================="
echo ""
echo "This demonstrates Docker Swarm's horizontal scaling capabilities."
echo "Note: The plant monitoring system is highly efficient - the processor"
echo "can handle the load from many sensors, so we won't see significant lag."
echo "However, this demonstrates the CAPABILITY to scale in response to demand."
echo ""

# Phase 1: Baseline state
echo "Phase 1: Baseline State"
echo "------------------------------------------------------------"
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" 'docker service ls | grep -E "NAME|sensor|processor"'
echo ""
read -p "Press Enter to scale producers (sensors) from 2 → 4 replicas..."
echo ""

# Phase 2: Scale producers
echo "Phase 2: Scaling Producers (Sensors) 2 → 4"
echo "------------------------------------------------------------"
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" 'docker service scale plant-monitoring_sensor=4'
echo ""
echo "Current service state:"
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" 'docker service ls | grep -E "NAME|sensor|processor"'
echo ""
read -p "Press Enter to scale consumer (processor) from 1 → 2 replicas..."
echo ""

# Phase 3: Scale consumer
echo "Phase 3: Scaling Consumer (Processor) 1 → 2"
echo "------------------------------------------------------------"
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" 'docker service scale plant-monitoring_processor=2'
echo ""
echo "Scaled service state:"
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" 'docker service ls | grep -E "NAME|sensor|processor"'
echo ""
echo "** SCREENSHOT THIS OUTPUT FOR CA3 SUBMISSION **"
echo ""
read -p "Press Enter to demonstrate scale-down..."
echo ""

# Phase 4: Scale down
echo "Phase 4: Scale-Down Demonstration"
echo "------------------------------------------------------------"
echo "Scaling sensors back to 2 replicas..."
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" 'docker service scale plant-monitoring_sensor=2'
echo ""
echo "Scaling processor back to 1 replica..."
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" 'docker service scale plant-monitoring_processor=1'
echo ""
echo "Final service state (back to baseline):"
ssh -i "${SSH_KEY}" "ubuntu@${MANAGER_IP}" 'docker service ls | grep -E "NAME|sensor|processor"'
echo ""

echo "============================================================================="
echo "  AUTOSCALING DEMONSTRATION COMPLETE"
echo "============================================================================="
echo ""
echo "What was demonstrated:"
echo "  ✓ Producer scaling: 2 → 4 replicas (docker service scale)"
echo "  ✓ Consumer scaling: 1 → 2 replicas (docker service scale)"  
echo "  ✓ Scale-down: Both services returned to baseline"
echo ""
echo "For CA3 submission:"
echo "  1. Screenshot showing scaled state (4 sensors, 2 processors)"
echo "  2. Screenshot showing baseline state (2 sensors, 1 processor)"
echo "  3. Document the scale commands used"
echo ""
echo "Note: This system is highly efficient and doesn't create lag under normal"
echo "load. In production, you would configure HPA based on CPU%, memory%, or"
echo "custom metrics (Kafka lag) to trigger automatic scaling."
echo "============================================================================="
