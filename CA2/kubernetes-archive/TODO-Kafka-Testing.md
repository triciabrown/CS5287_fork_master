# Kafka Testing TODO - October 16, 2025

## Summary of Today's Progress
- ✅ Fixed Kafka service name from `kafka-service` to `kafka-headless` for proper DNS resolution
- ✅ Created separate `kafka-init-storage.sh` script to handle storage initialization
- ✅ Moved init container logic to ConfigMap for cleaner YAML configuration
- ✅ Fixed `lost+found` directory issue that was causing Kafka crashes
- ✅ Increased Kafka memory from 180Mi→256Mi and heap from 96M→160M due to OutOfMemoryError
- ⚠️ Kafka was redeploying when we stopped for the night

## Current State
- **MongoDB**: ✅ Running (1/1 READY)
- **Kafka**: ⚠️ Just redeployed with increased memory, needs verification
- **Sensors**: ✅ Both running (waiting for Kafka)
- **Processor**: ❌ CrashLoopBackOff (needs Kafka + possible image fix)
- **HomeAssistant**: ⏸️ Pending (waiting for dependencies)

## Tomorrow's Testing Checklist

### 1. Verify Kafka Startup (15-20 minutes)
```bash
# Wait for Kafka to stabilize
kubectl get pods -n plant-monitoring -w

# Check if Kafka becomes READY and stays READY
kubectl get pods kafka-0 -n plant-monitoring

# Verify init container successfully cleaned lost+found
kubectl logs kafka-0 -n plant-monitoring -c kafka-format-storage

# Check main Kafka logs for successful startup
kubectl logs kafka-0 -n plant-monitoring --tail=100

# Look for these success indicators:
# - "Kafka Server started"
# - No OutOfMemoryError
# - Broker registered successfully
# - No crash loops after 5+ minutes
```

### 2. Validate Kafka Functionality
```bash
# Test DNS resolution
kubectl exec -it kafka-0 -n plant-monitoring -- /bin/bash
# (inside pod if nslookup available, or use curl/telnet)

# Check Kafka headless service
kubectl get svc kafka-headless -n plant-monitoring
kubectl describe svc kafka-headless -n plant-monitoring

# Verify Kafka is listening on ports
kubectl exec kafka-0 -n plant-monitoring -- netstat -tuln | grep -E "9092|9093"
```

### 3. Test Kafka Topics and Connectivity
```bash
# List topics (should auto-create plant_monitoring_data)
kubectl exec kafka-0 -n plant-monitoring -- kafka-topics --bootstrap-server localhost:9092 --list

# Test producer/consumer from within pod
kubectl exec kafka-0 -n plant-monitoring -- kafka-console-producer --bootstrap-server localhost:9092 --topic test-topic
# Type a test message and Ctrl+C

kubectl exec kafka-0 -n plant-monitoring -- kafka-console-consumer --bootstrap-server localhost:9092 --topic test-topic --from-beginning --timeout-ms 5000
```

### 4. Fix Plant Processor Image Issue
The processor has an error: `python: can't open file '/app/plant-monitor-processor.py': [Errno 2] No such file or directory`

**Investigate:**
```bash
# Check processor deployment
kubectl describe pod -l app=plant-processor -n plant-monitoring

# Check the processor image and entrypoint
kubectl get deployment plant-processor -n plant-monitoring -o yaml | grep -A10 "image:"

# May need to:
# 1. Rebuild processor Docker image with correct file paths
# 2. Update Dockerfile WORKDIR and COPY instructions
# 3. Fix entrypoint/command in deployment YAML
```

**Files to check:**
- `CA2/applications/processor/Dockerfile`
- `CA2/applications/processor/` (verify Python script name)
- `deploy-applications.yml` processor deployment section

### 5. Monitor Sensor to Kafka Connection
```bash
# Once Kafka is stable, check sensor logs
kubectl logs -l app=plant-sensor-plant-001 -n plant-monitoring --tail=50
kubectl logs -l app=plant-sensor-plant-002 -n plant-monitoring --tail=50

# Should see successful connections to Kafka
# Look for "Connected to Kafka" or similar messages
```

### 6. End-to-End Data Flow Test
Once all components are running:

```bash
# Check MongoDB for sensor data
kubectl exec -it mongodb-0 -n plant-monitoring -- mongosh --eval "use plant_monitoring; db.sensor_data.find().limit(5).pretty()"

# Verify data is flowing: sensors → Kafka → processor → MongoDB
# Should see recent timestamps in MongoDB documents
```

### 7. Resource Monitoring
```bash
# Monitor resource usage on t2.micro workers
kubectl top pods -n plant-monitoring

# Check node resource allocation
kubectl top nodes

# If memory pressure issues persist, consider:
# - Reducing MongoDB cache size further (currently 0.25GB)
# - Adjusting Kafka heap down slightly (160M might still be tight)
# - Checking for memory leaks in processor/sensors
```

## Known Issues to Watch For

### Issue 1: Kafka OutOfMemoryError
- **Symptom**: Java heap space errors in logs, crash loops
- **Current Settings**: 256Mi limit, 160M heap
- **Fix**: May need to reduce heap to 140M or increase limit to 300Mi depending on stability

### Issue 2: Lost+found Directory
- **Symptom**: "Found directory /var/lib/kafka/data/lost+found" error
- **Status**: Should be fixed by init script
- **Verify**: Check init container logs show "✓ Removed lost+found directory"

### Issue 3: Processor File Not Found
- **Symptom**: `/app/plant-monitor-processor.py: [Errno 2] No such file or directory`
- **Status**: Not yet investigated
- **Action**: Check Dockerfile and image build

### Issue 4: Service Discovery
- **Symptom**: Kafka couldn't resolve kafka-0.kafka-headless
- **Status**: Fixed by renaming service
- **Verify**: DNS queries should succeed now

## Configuration Files Modified Today

1. **kafka-init-storage.sh** (NEW)
   - Removes lost+found directory
   - Checks for existing metadata before formatting
   - Uses CLUSTER_ID environment variable

2. **deploy-applications.yml**
   - Added ConfigMap for init script
   - Updated init container to use script from ConfigMap
   - Added volumes section with kafka-init-script ConfigMap mount
   - Increased Kafka heap to 160M

3. **group_vars/all.yml**
   - Increased kafka_memory_limit: 180Mi → 256Mi
   - Increased kafka_memory_request: 150Mi → 200Mi

## Success Criteria for Tomorrow

- [ ] Kafka pod reaches READY state (1/1)
- [ ] Kafka stays stable for 10+ minutes without restarts
- [ ] No OutOfMemoryError in Kafka logs
- [ ] Kafka topics can be listed
- [ ] Sensor pods successfully connect to Kafka
- [ ] Processor issue diagnosed and fixed
- [ ] Data flows through full pipeline to MongoDB
- [ ] HomeAssistant comes online once dependencies ready

## Rollback Plan (If Needed)

If 256Mi/160M is too much for t2.micro instances:

```bash
# Option A: Reduce heap but keep memory limit
# In deploy-applications.yml: KAFKA_HEAP_OPTS: "-Xmx140M -Xms140M"

# Option B: Go back to 200Mi limit with 128M heap
# In group_vars/all.yml: kafka_memory_limit: "200Mi"
# In deploy-applications.yml: KAFKA_HEAP_OPTS: "-Xmx128M -Xms128M"

# Option C: Consider upgrading worker nodes from t2.micro to t2.small
# More expensive but gives 2GB RAM instead of 1GB
```

## Notes
- Init script provides cleaner separation of concerns
- ConfigMap approach makes it easier to debug and modify init logic
- Memory tuning for Kafka in KRaft mode on t2.micro is challenging
- May need to profile actual memory usage once stable

---
**Last Updated**: October 15, 2025, 11:35 PM
**Current Branch**: master
**Next Session Goal**: Get Kafka stable and data flowing end-to-end
