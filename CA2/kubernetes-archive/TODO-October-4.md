# CA2 TODO List - October 4, 2025

## Priority 1: Production Networking Setup
- [ ] **Switch Home Assistant from NodePort to ClusterIP**
  - Update `homeassistant.yaml` service type from NodePort to ClusterIP
  - Remove nodePort specifications (30123, 31883)

- [ ] **Install and Configure Ingress Controller**
  - Research best ingress controller for AWS (nginx-ingress vs AWS Load Balancer Controller)
  - Install ingress controller: `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml`
  - Configure ingress rules for Home Assistant (port 8123)

- [ ] **Set up Load Balancer**
  - Configure AWS Application Load Balancer (ALB) or Network Load Balancer (NLB)
  - Update security groups to allow ingress traffic
  - Consider SSL/TLS termination at load balancer level

- [ ] **Create Ingress Resource**
  - Create `ingress.yaml` manifest for Home Assistant
  - Configure hostname/domain (if available) or use ALB DNS name
  - Test external access via ingress instead of NodePort

## Priority 2: System Reliability
- [ ] **Fix Pod Issues**
  - Investigate why MongoDB and Kafka pods are in Pending state (PVC binding issues)
  - Check if EBS CSI driver is properly installed and functioning
  - Verify storage classes are available and working

- [ ] **Application Health**
  - Fix CrashLoopBackOff issues with plant-processor and plant-sensor pods
  - Check application logs: `kubectl logs -f deployment/plant-processor -n plant-monitoring`
  - Verify ConfigMaps and Secrets are properly mounted

## Priority 3: Documentation Updates
- [ ] **Update README files**
  - Document the new modular approach (Ansible + HomeAssistant manifest)
  - Update access instructions to reflect ingress setup
  - Document troubleshooting steps for common issues

- [ ] **Clean up obsolete references**
  - Update `deploy-production.sh` to use new homeassistant.yaml instead of plant-monitoring-manifests.yaml
  - Update `PRODUCTION_README.md` references
  - Update `build-images.sh` references

## Priority 4: Testing & Validation
- [ ] **End-to-End Testing**
  - Deploy full system with new ingress setup
  - Verify Home Assistant accessible via load balancer
  - Test MQTT connectivity between plant sensors and Home Assistant
  - Verify data flow: Sensors → Kafka → Processor → MongoDB → Home Assistant

- [ ] **Load Testing**
  - Test HPA (Horizontal Pod Autoscaler) functionality
  - Scale plant sensors and verify system handles load
  - Monitor resource usage on t2.micro instances

## Priority 5: Security Enhancements
- [ ] **Network Policies**
  - Verify network-policy.yaml is working correctly
  - Test pod-to-pod communication restrictions
  - Ensure only necessary ports are exposed

- [ ] **Secrets Management**
  - Verify all credentials are properly stored in Kubernetes secrets
  - Remove any hardcoded passwords from manifests
  - Consider external secret management (AWS Secrets Manager integration)

## Optional Improvements
- [ ] **Monitoring & Observability**
  - Add Prometheus/Grafana for metrics collection
  - Set up log aggregation (ELK stack or AWS CloudWatch)
  - Create dashboards for system health monitoring

- [ ] **Backup Strategy**
  - Implement MongoDB backup to S3
  - Document disaster recovery procedures
  - Test backup/restore procedures

---

## Quick Commands for Tomorrow

**Teardown tonight:**
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-k8s-IaC
./teardown.sh
```

**Start fresh tomorrow:**
```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/plant-monitor-k8s-IaC
./deploy.sh
```

**Debug commands:**
```bash
# Check pod status
kubectl get pods -n plant-monitoring -o wide

# Check PVC status  
kubectl get pvc -n plant-monitoring

# Check ingress controller
kubectl get pods -n ingress-nginx

# View logs
kubectl logs -f deployment/plant-processor -n plant-monitoring
```

**Useful links:**
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Ingress NGINX Controller](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)

---
*Created: October 3, 2025*
*Status: Ready for tomorrow's work*