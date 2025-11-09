#!/bin/bash

# CA3 Observability Stack Deployment
# Deploys Loki, Promtail, Prometheus, and Grafana to the Docker Swarm cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="monitoring"

echo "=========================================="
echo "CA3 Observability Stack Deployment"
echo "=========================================="
echo ""

# Function to check if Docker Swarm is active
check_swarm() {
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        echo "❌ Error: Docker Swarm is not active on this node"
        echo "Please run this script on the Swarm manager node"
        exit 1
    fi
    echo "✅ Docker Swarm is active"
}

# Function to check if plant-monitor networks exist
check_network() {
    local networks=("frontnet" "messagenet" "datanet")
    local all_exist=true
    
    for net in "${networks[@]}"; do
        if ! docker network ls | grep -q "$net"; then
            echo "❌ Error: $net network does not exist"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = false ]; then
        echo "Please deploy the main application stack first"
        exit 1
    fi
    echo "✅ All required networks exist (frontnet, messagenet, datanet)"
}

# Function to validate config files
check_configs() {
    local configs=(
        "${SCRIPT_DIR}/configs/loki-config.yaml"
        "${SCRIPT_DIR}/configs/promtail-config.yml"
        "${SCRIPT_DIR}/configs/prometheus.yml"
        "${SCRIPT_DIR}/configs/grafana-datasources.yml"
        "${SCRIPT_DIR}/configs/grafana-dashboards.yml"
    )
    
    echo "Checking configuration files..."
    for config in "${configs[@]}"; do
        if [ ! -f "$config" ]; then
            echo "❌ Error: Configuration file not found: $config"
            exit 1
        fi
        echo "  ✓ $(basename "$config")"
    done
    echo "✅ All configuration files found"
}

# Function to deploy the stack
deploy_stack() {
    echo ""
    echo "Deploying observability stack..."
    docker stack deploy -c "${SCRIPT_DIR}/observability-stack.yml" "$STACK_NAME"
    echo "✅ Stack deployment initiated"
}

# Function to wait for services to be ready
wait_for_services() {
    echo ""
    echo "Waiting for services to start..."
    sleep 5
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local running=$(docker service ls --filter "label=com.docker.stack.namespace=$STACK_NAME" --format "{{.Name}}: {{.Replicas}}" | grep -c "1/1" || true)
        local total=$(docker service ls --filter "label=com.docker.stack.namespace=$STACK_NAME" | tail -n +2 | wc -l)
        
        echo "  Services ready: $running/$total"
        
        if [ "$running" -eq "$total" ] && [ "$total" -gt 0 ]; then
            echo "✅ All services are running"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 5
    done
    
    echo "⚠️  Warning: Not all services are ready after ${max_attempts} attempts"
    echo "Check service status with: docker service ls"
}

# Function to display service status
show_services() {
    echo ""
    echo "=========================================="
    echo "Service Status"
    echo "=========================================="
    docker service ls --filter "label=com.docker.stack.namespace=$STACK_NAME"
}

# Function to display access information
show_access_info() {
    local manager_ip=$(docker node inspect self --format '{{.Status.Addr}}')
    
    echo ""
    echo "=========================================="
    echo "Observability Stack Access Information"
    echo "=========================================="
    echo ""
    echo "📊 Grafana (Dashboards & Logs):"
    echo "   URL: http://${manager_ip}:3000"
    echo "   Username: admin"
    echo "   Password: admin"
    echo "   (Change password on first login)"
    echo ""
    echo "📈 Prometheus (Metrics):"
    echo "   URL: http://${manager_ip}:9090"
    echo ""
    echo "📝 Loki (Log API):"
    echo "   URL: http://${manager_ip}:3100"
    echo ""
    echo "=========================================="
    echo "Next Steps:"
    echo "=========================================="
    echo "1. Access Grafana and verify data sources"
    echo "2. Create dashboards for CA3 metrics:"
    echo "   - Sensor data rate"
    echo "   - Kafka consumer lag"
    echo "   - Processing throughput"
    echo "   - Database performance"
    echo "   - End-to-end latency"
    echo "   - Service availability"
    echo ""
    echo "3. Instrument applications with Prometheus metrics"
    echo "4. Test log aggregation with LogQL queries"
    echo ""
}

# Function to show example queries
show_example_queries() {
    echo "=========================================="
    echo "Example Queries"
    echo "=========================================="
    echo ""
    echo "Prometheus (PromQL):"
    echo "  # Service availability"
    echo "  up{job=~\"plant-sensor|plant-processor\"}"
    echo ""
    echo "  # Kafka consumer lag"
    echo "  kafka_consumergroup_lag{topic=\"plant-sensor-data\"}"
    echo ""
    echo "  # CPU usage by service"
    echo "  rate(process_cpu_seconds_total[5m])"
    echo ""
    echo "Loki (LogQL):"
    echo "  # All logs from sensor service"
    echo "  {service=\"plant-sensor\"}"
    echo ""
    echo "  # Error logs across all services"
    echo "  {stack=\"plant-monitor\"} |~ \"(?i)error\""
    echo ""
    echo "  # Logs from specific container"
    echo "  {container=~\"plant-processor.*\"} | json"
    echo ""
}

# Main execution
main() {
    check_swarm
    check_network
    check_configs
    deploy_stack
    wait_for_services
    show_services
    show_access_info
    show_example_queries
    
    echo "✅ Observability stack deployment complete!"
}

# Run main function
main
