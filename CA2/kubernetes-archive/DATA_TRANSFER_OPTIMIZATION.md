# Data Transfer Optimization Plan
# October 5, 2025

## Current Status
- Hit 1GB AWS data transfer limit before full deployment
- Infrastructure torn down successfully
- Ready to redeploy with optimizations

## Data Transfer Sources (Estimated)
1. **Container Images** (~600MB):
   - MongoDB: ~150MB
   - Kafka: ~300MB  
   - Home Assistant: ~150MB
   
2. **Kubernetes System** (~300MB):
   - Control plane images
   - Flannel CNI
   - EBS CSI driver
   - Metrics server

3. **Repeated Pulls** (~100MB+):
   - Failed deployments requiring re-pulls
   - CSI driver restarts

## Optimizations Implemented

### Infrastructure Level
- ✅ Single AZ deployment (us-east-2a)
- ✅ Private networking between nodes
- ✅ Topology labels to prevent CSI issues

### Container Level  
- ✅ Reduced resource requests (less memory pressure = fewer restarts)
- ✅ Smaller base images where possible
- 🔄 Pre-pull essential images during node init

### Deployment Level
- 🔄 Deploy in stages to avoid repeated failures
- 🔄 Monitor data transfer during deployment
- 🔄 Use local image caching where possible

## Stage 1: Infrastructure Only (Current)
- Deploy cluster infrastructure
- Verify nodes are healthy
- Apply topology labels
- **Estimated data transfer**: ~200MB

## Stage 2: System Components
- Deploy EBS CSI driver (fixed version)
- Deploy ingress controller  
- Verify storage provisioning works
- **Estimated data transfer**: ~100MB

## Stage 3: Applications (Phased)
- Deploy MongoDB first (test storage)
- Deploy Kafka second  
- Deploy sensors/processor
- Deploy Home Assistant last
- **Estimated data transfer**: ~400MB

## Monitoring Commands
```bash
# Check deployment progress
kubectl get nodes
kubectl get pods -A

# Monitor data usage
aws ce get-dimension-values --dimension Key=SERVICE --time-period Start=2025-10-01,End=2025-10-31

# Check image pull status  
kubectl get events --sort-by='.firstTimestamp' | grep -i pulled
```

## If We Hit Limits Again
- Pause deployment immediately
- Use smaller/alpine-based images
- Deploy only core components needed for demo
- Consider using pre-built cluster images