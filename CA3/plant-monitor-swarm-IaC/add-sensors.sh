#!/bin/bash
#
# add-sensors.sh - Add additional plant sensors for scaling demonstrations
#
# Usage:
#   ./add-sensors.sh <number_of_sensors>
#   ./add-sensors.sh 5          # Add 5 sensors (total will be 7)
#   ./add-sensors.sh reset      # Reset to default 2 sensors
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SENSOR_CONFIG_FILE="${SCRIPT_DIR}/sensor-config.json"

# Plant types and locations for variety
PLANT_TYPES=("monstera" "sansevieria" "pothos" "fern" "succulent" "orchid" "cactus" "aloe" "spider-plant" "peace-lily")
LOCATIONS=("Living Room" "Bedroom" "Kitchen" "Bathroom" "Office" "Balcony" "Hallway" "Dining Room" "Study" "Greenhouse")

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}  Plant Sensor Scaling Script${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# Function to generate sensor config
generate_config() {
    local num_sensors=$1
    local config_json='{"sensors":[],"kafka":{"topic":"plant-sensors","producerConfig":{"acks":1,"compression":"snappy"}}}'
    
    echo -e "${YELLOW}Generating config for $num_sensors sensors...${NC}"
    
    # Build JSON array of sensors
    local sensors_json="["
    for i in $(seq 1 $num_sensors); do
        local plant_id=$(printf "plant-%03d" $i)
        local plant_type=${PLANT_TYPES[$((i % ${#PLANT_TYPES[@]}))]}
        local location=${LOCATIONS[$((i % ${#LOCATIONS[@]}))]}
        local interval=$((30 + (i % 3) * 15))  # Vary intervals: 30, 45, 60
        
        if [ $i -gt 1 ]; then
            sensors_json+=","
        fi
        
        sensors_json+="{\"plantId\":\"$plant_id\",\"plantType\":\"$plant_type\",\"location\":\"$location\",\"sensorInterval\":$interval}"
    done
    sensors_json+="]"
    
    # Create complete JSON
    echo "{\"sensors\":$sensors_json,\"kafka\":{\"topic\":\"plant-sensors\",\"producerConfig\":{\"acks\":1,\"compression\":\"snappy\"}}}" | jq '.' > "$SENSOR_CONFIG_FILE"
    
    echo -e "${GREEN}✓ Generated config with $num_sensors sensors${NC}"
    echo ""
    echo -e "${BLUE}Plant IDs created:${NC}"
    jq -r '.sensors[] | "  - \(.plantId) (\(.plantType)) in \(.location) - every \(.sensorInterval)s"' "$SENSOR_CONFIG_FILE"
}

# Function to update Docker config
update_docker_config() {
    local num_sensors=$1
    
    echo ""
    echo -e "${YELLOW}Updating Docker Swarm sensor config...${NC}"
    
    # Remove old config
    docker config rm sensor_config 2>/dev/null || true
    
    # Create new config
    docker config create sensor_config "$SENSOR_CONFIG_FILE"
    
    echo -e "${GREEN}✓ Docker config updated${NC}"
}

# Function to scale sensor service
scale_sensors() {
    local num_sensors=$1
    
    echo ""
    echo -e "${YELLOW}Scaling sensor service to $num_sensors replicas...${NC}"
    
    docker service scale plant-monitoring_sensor=$num_sensors
    
    echo ""
    echo -e "${YELLOW}Waiting for sensors to start...${NC}"
    sleep 10
    
    # Check service status
    echo ""
    docker service ps plant-monitoring_sensor --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}" | head -$((num_sensors + 1))
}

# Function to verify sensors are working
verify_sensors() {
    echo ""
    echo -e "${YELLOW}Verifying sensor data production...${NC}"
    sleep 15  # Give sensors time to start producing
    
    echo ""
    echo -e "${BLUE}Recent sensor logs (checking for different plant IDs):${NC}"
    docker service logs plant-monitoring_sensor --tail 50 2>&1 | \
        grep -E "plant-[0-9]+" | \
        grep -oE "plant-[0-9]+" | \
        sort -u | \
        awk '{print "  ✓ " $0 " is active"}'
    
    echo ""
    echo -e "${BLUE}Prometheus metrics (sensor targets):${NC}"
    curl -s http://localhost:9090/api/v1/targets 2>/dev/null | \
        jq -r '.data.activeTargets[] | select(.labels.job=="plant-sensor") | "  ✓ \(.labels.instance) - \(.health)"' | \
        head -20 || echo "  (Run this on the manager node to see metrics)"
}

# Main script logic
case "$1" in
    reset)
        echo -e "${YELLOW}Resetting to default 2 sensors...${NC}"
        generate_config 2
        update_docker_config 2
        scale_sensors 2
        verify_sensors
        echo ""
        echo -e "${GREEN}✓ Reset complete - 2 sensors deployed${NC}"
        ;;
    [0-9]*)
        NUM_SENSORS=$1
        if [ $NUM_SENSORS -lt 1 ] || [ $NUM_SENSORS -gt 50 ]; then
            echo -e "${RED}Error: Number of sensors must be between 1 and 50${NC}"
            exit 1
        fi
        
        echo -e "${BLUE}Adding $NUM_SENSORS sensors for scaling demonstration${NC}"
        echo ""
        
        generate_config $NUM_SENSORS
        update_docker_config $NUM_SENSORS
        scale_sensors $NUM_SENSORS
        verify_sensors
        
        echo ""
        echo -e "${GREEN}===========================================${NC}"
        echo -e "${GREEN}✓ Successfully deployed $NUM_SENSORS sensors!${NC}"
        echo -e "${GREEN}===========================================${NC}"
        echo ""
        echo -e "${BLUE}Next steps for demo:${NC}"
        echo "  1. Check Grafana: http://<manager-ip>:3000"
        echo "  2. Watch metrics: docker service logs plant-monitoring_processor -f"
        echo "  3. View plant health: Open Grafana dashboard"
        echo "  4. Run load test: bash load-test-processor.sh"
        echo ""
        echo -e "${BLUE}To scale down:${NC}"
        echo "  ./add-sensors.sh reset    # Back to 2 sensors"
        echo "  docker service scale plant-monitoring_sensor=<N>"
        ;;
    *)
        echo "Usage: $0 <number_of_sensors>"
        echo ""
        echo "Examples:"
        echo "  $0 5       # Deploy 5 sensors (plant-001 through plant-005)"
        echo "  $0 10      # Deploy 10 sensors for load testing"
        echo "  $0 20      # Deploy 20 sensors for scaling demo"
        echo "  $0 reset   # Reset to default 2 sensors"
        echo ""
        echo "Current configuration:"
        if [ -f "$SENSOR_CONFIG_FILE" ]; then
            echo "  Sensors: $(jq -r '.sensors | length' "$SENSOR_CONFIG_FILE")"
            echo "  Plant IDs:"
            jq -r '.sensors[] | "    - \(.plantId) (\(.plantType))"' "$SENSOR_CONFIG_FILE"
        else
            echo "  No config file found"
        fi
        exit 1
        ;;
esac
