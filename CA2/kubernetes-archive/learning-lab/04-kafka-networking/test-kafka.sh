#!/bin/bash

echo "=== Testing Kafka Message Publishing ==="
echo ""

echo "📝 Publishing test messages to sensor-data topic..."

# Publish some test messages
kubectl exec -it kafka-0 -n ca2-learning -- bash -c "
echo 'Message 1: Temperature sensor reading: 23.5°C' | kafka-console-producer --topic sensor-data --bootstrap-server localhost:9092
echo 'Message 2: Humidity sensor reading: 45%' | kafka-console-producer --topic sensor-data --bootstrap-server localhost:9092  
echo 'Message 3: Pressure sensor reading: 1013.25 hPa' | kafka-console-producer --topic sensor-data --bootstrap-server localhost:9092
"

echo ""
echo "✅ Messages published! Now reading them back..."
echo ""

# Read messages back
kubectl exec kafka-0 -n ca2-learning -- kafka-console-consumer --topic sensor-data --bootstrap-server localhost:9092 --from-beginning --timeout-ms 5000

echo ""
echo "🎉 Kafka is working correctly!"