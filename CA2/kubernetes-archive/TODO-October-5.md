# TODO - October 5, 2025

## 🚨 PRIORITY: Fix EBS CSI Driver Issue

### Current Status
- ✅ **Cluster**: 5-node cluster (1 control + 4 workers) deployed successfully
- ✅ **Topology Labels**: Added to all Kubernetes nodes (`topology.kubernetes.io/region=us-east-2`, `topology.kubernetes.io/zone=us-east-2a`)
- ✅ **EBS CSI Controller**: Running (2/2 containers)
- ❌ **CSI Node Registration**: EBS CSI node pods not registering with CSI Node API
- ❌ **Volume Provisioning**: PVCs stuck in Pending due to CSI registration failure

### Root Issue
**CSI nodes have no drivers registered** - this prevents volume provisioning even though topology labels are correct.

```bash
# Check CSI nodes (should show ebs.csi.aws.com driver but shows empty):
kubectl get csinodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.drivers[*].name}{"\n"}{end}'
```

### Action Plan for Tomorrow

#### 1. **Investigate CSI Node Registration Issue** 🔍
- [ ] Check EBS CSI node pod logs for registration errors:
  ```bash
  kubectl logs -n kube-system -l app=ebs-csi-node --follow
  ```
- [ ] Verify kubelet CSI plugin registration:
  ```bash
  # On each worker node
  ls -la /var/lib/kubelet/plugins_registry/
  ls -la /var/lib/kubelet/plugins/ebs.csi.aws.com/
  ```
- [ ] Check if CSI socket is created:
  ```bash
  # On worker nodes
  ls -la /var/lib/kubelet/plugins/ebs.csi.aws.com/csi.sock
  ```

#### 2. **Try Alternative EBS CSI Driver Setup** 🔧
- [ ] Option A: Use official AWS EBS CSI driver manifest instead of custom one:
  ```bash
  kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.33"
  ```
- [ ] Option B: Check IAM permissions for EBS CSI driver
- [ ] Option C: Verify worker nodes have proper IAM roles for EBS operations

#### 3. **Test Volume Provisioning** ✅
Once CSI registration is fixed:
- [ ] Create test PVC to verify provisioning works
- [ ] Deploy MongoDB StatefulSet and verify it gets scheduled
- [ ] Deploy Kafka StatefulSet and verify it gets scheduled
- [ ] Deploy Home Assistant and complete the application stack

#### 4. **Complete Scaling Demo for Assignment** 📊
- [ ] Run scaling demonstration: `./applications/scaling-demo.sh`
- [ ] Document scaling behavior for assignment submission
- [ ] Run smoke test: `./applications/smoke-test.sh`

### Key Files Updated Today
- ✅ **`plant-monitor-k8s-IaC/deploy.sh`**: Added topology labeling for all nodes
- ✅ **Cleanup**: Removed unused files (deploy-cluster.sh, applications-from-ca1/, etc.)
- ✅ **Restored**: smoke-test.sh, build-images.sh, scaling-demo.sh for assignment needs

### Emergency Fallback Options
If CSI issues persist:
1. **Use hostPath volumes** (not production-ready but functional for demo)
2. **Deploy without persistent storage** (StatefulSets as Deployments with emptyDir)
3. **Use EKS** (if free tier allows) for native EBS CSI support

### Context for Tomorrow
- **Region**: us-east-2 (Ohio)
- **AZ**: us-east-2a (single AZ deployment)
- **Instance Type**: t2.micro (5 instances within free tier)
- **Resource Constraints**: ~357MB allocatable memory per worker node
- **Applications**: Optimized resource requests (MongoDB: 64Mi, Home Assistant: 128Mi)

### Commands to Remember
```bash
# Check cluster status
kubectl get nodes -o wide
kubectl get pods -A

# Check EBS CSI status
kubectl get pods -n kube-system | grep ebs-csi
kubectl get csinodes
kubectl get pvc -n plant-monitoring

# Apply topology labels (already done but for reference)
kubectl label nodes --all topology.kubernetes.io/region=us-east-2 topology.kubernetes.io/zone=us-east-2a --overwrite
```

---
**Started**: October 4, 2025  
**Status**: EBS CSI driver registration issue blocking application deployment  
**Next**: Fix CSI registration → Complete application stack → Scaling demo → Assignment submission