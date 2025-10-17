# Free Tier 3-Node Kubernetes Cluster Setup

## **Quick Start Guide**

This guide will walk you through setting up a production-like 3-node Kubernetes cluster using AWS free tier resources.

### **Prerequisites**
- AWS account with free tier eligibility
- SSH key pair (we'll generate one)
- Terraform installed locally
- kubectl installed locally

### **What We're Building**
```
Control Plane (t2.micro)     Worker-1 (t2.micro)     Worker-2 (t2.micro)
├── etcd                     ├── kubelet              ├── kubelet  
├── kube-apiserver          ├── kube-proxy           ├── kube-proxy
├── kube-controller         ├── containerd           ├── containerd
├── kube-scheduler          └── flannel CNI          └── flannel CNI
└── flannel CNI
```

**Total Cost**: $0/month (all within AWS free tier limits)

---

## **Step 1: Infrastructure Deployment**

Let's deploy the infrastructure first, then manually configure Kubernetes.

### **Deploy with Terraform**

```bash
# Navigate to the cluster setup directory
cd /home/tricia/dev/CS5287_fork_master/CA2/aws-cluster-setup

# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-cluster-key -N ""

# Initialize and apply Terraform
terraform init
terraform apply -auto-approve

# Save the output IPs for later
terraform output > cluster-ips.txt
cat cluster-ips.txt
```

### **Expected Output**
```
control_plane_ip = "3.XXX.XXX.XXX"
control_plane_private_ip = "10.0.1.XXX"
worker_ips = [
  "3.XXX.XXX.XXX",
  "3.XXX.XXX.XXX",
]
worker_private_ips = [
  "10.0.1.XXX",
  "10.0.1.XXX",
]
```

---

## **Step 2: Initialize Control Plane**

### **Connect to Control Plane**
```bash
# SSH to the control plane node
CONTROL_PLANE_IP=$(terraform output -raw control_plane_ip)
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$CONTROL_PLANE_IP
```

### **Initialize Kubernetes Cluster**
```bash
# Get the private IP for API server
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo "Control Plane Private IP: $PRIVATE_IP"

# Initialize the cluster
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=$PRIVATE_IP \
  --kubernetes-version=v1.28.2 \
  --node-name=$(hostname -s) \
  --ignore-preflight-errors=NumCPU,Mem

# Set up kubectl for ubuntu user
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Test cluster access
kubectl get nodes
kubectl get pods -A
```

### **Save Join Command**
```bash
# Generate and save the join command for worker nodes
kubeadm token create --print-join-command > ~/join-command.txt
cat ~/join-command.txt

# The output will look like:
# kubeadm join 10.0.1.100:6443 --token abc123.xyz789 --discovery-token-ca-cert-hash sha256:longhashere
```

### **Install CNI Plugin (Flannel)**
```bash
# Install Flannel for pod networking
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Wait for flannel to be ready
kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel-system --timeout=300s

# Verify control plane is ready
kubectl get nodes
# Should show: STATUS=Ready, ROLES=control-plane
```

---

## **Step 3: Join Worker Nodes**

### **Join Worker Node 1**
```bash
# Open new terminal, connect to first worker
WORKER1_IP=$(terraform output -raw worker_ips | jq -r '.[0]')
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$WORKER1_IP

# Run the join command (copy from control plane)
sudo kubeadm join 10.0.1.XXX:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>

# Should see: "This node has joined the cluster"
exit
```

### **Join Worker Node 2**
```bash
# Connect to second worker
WORKER2_IP=$(terraform output -raw worker_ips | jq -r '.[1]')
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$WORKER2_IP

# Run the same join command
sudo kubeadm join 10.0.1.XXX:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>

exit
```

### **Verify All Nodes Joined**
```bash
# Back on control plane
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$CONTROL_PLANE_IP

# Check all nodes are ready
kubectl get nodes -o wide

# Expected output:
# NAME            STATUS   ROLES           AGE   VERSION
# ip-10-0-1-100   Ready    control-plane   10m   v1.28.2
# ip-10-0-1-101   Ready    <none>          5m    v1.28.2  
# ip-10-0-1-102   Ready    <none>          5m    v1.28.2
```

---

## **Step 4: Install Storage and Metrics**

### **Install EBS CSI Driver**
```bash
# Install EBS CSI driver for persistent volumes
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.24"

# Create optimized StorageClass for free tier
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-csi-gp2-freetier
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp2
  fsType: ext4
allowVolumeExpansion: true
EOF
```

### **Install Metrics Server**
```bash
# Install metrics server for resource monitoring
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch for self-signed certificates (required for our setup)
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  }
]'

# Wait for metrics server to be ready
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=300s
```

---

## **Step 5: Set Up Local kubectl Access**

### **Copy kubeconfig to Local Machine**
```bash
# From your local machine, copy the kubeconfig
scp -i ~/.ssh/k8s-cluster-key ubuntu@$CONTROL_PLANE_IP:/home/ubuntu/.kube/config ~/.kube/config-aws-cluster

# Update the server address to use public IP
sed -i "s/10.0.1.XXX/$CONTROL_PLANE_IP/g" ~/.kube/config-aws-cluster

# Set as current context
export KUBECONFIG=~/.kube/config-aws-cluster
kubectl config current-context

# Test access from local machine
kubectl get nodes
kubectl get pods -A
```

---

## **Step 6: Deploy Free Tier Optimized Applications**

### **Create Namespace**
```bash
kubectl create namespace ca2-learning-aws
```

### **Deploy MongoDB (Free Tier Optimized)**
```bash
# Apply the free tier MongoDB configuration
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb-micro
  namespace: ca2-learning-aws
spec:
  serviceName: mongodb-micro-headless
  replicas: 1
  selector:
    matchLabels:
      app: mongodb-micro
  template:
    metadata:
      labels:
        app: mongodb-micro
    spec:
      containers:
      - name: mongodb
        image: mongo:6.0.4
        ports:
        - containerPort: 27017
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          value: "admin"
        - name: MONGO_INITDB_ROOT_PASSWORD
          value: "password123"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        volumeMounts:
        - name: mongodb-data
          mountPath: /data/db
        command:
        - mongod
        - --wiredTigerCacheSizeGB=0.1
        - --smallfiles
  volumeClaimTemplates:
  - metadata:
      name: mongodb-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ebs-csi-gp2-freetier
      resources:
        requests:
          storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-micro-service
  namespace: ca2-learning-aws
spec:
  selector:
    app: mongodb-micro
  ports:
  - port: 27017
    targetPort: 27017
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-micro-headless
  namespace: ca2-learning-aws
spec:
  clusterIP: None
  selector:
    app: mongodb-micro
  ports:
  - port: 27017
    targetPort: 27017
EOF
```

### **Deploy Kafka (Single Broker)**
```bash
# Apply the free tier Kafka configuration
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka-micro
  namespace: ca2-learning-aws
spec:
  serviceName: kafka-micro-headless
  replicas: 1
  selector:
    matchLabels:
      app: kafka-micro
  template:
    metadata:
      labels:
        app: kafka-micro
    spec:
      containers:
      - name: kafka
        image: confluentinc/cp-kafka:7.4.0
        ports:
        - containerPort: 9092
        - containerPort: 9093
        env:
        - name: KAFKA_NODE_ID
          value: "1"
        - name: KAFKA_PROCESS_ROLES
          value: "broker,controller"
        - name: KAFKA_CONTROLLER_QUORUM_VOTERS
          value: "1@kafka-micro-0.kafka-micro-headless:9093"
        - name: KAFKA_LISTENERS
          value: "PLAINTEXT://:9092,CONTROLLER://:9093"
        - name: KAFKA_ADVERTISED_LISTENERS
          value: "PLAINTEXT://kafka-micro-0.kafka-micro-headless:9092"
        - name: KAFKA_CONTROLLER_LISTENER_NAMES
          value: "CONTROLLER"
        - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
          value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
        - name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
          value: "1"
        - name: KAFKA_HEAP_OPTS
          value: "-Xmx128M -Xms128M"
        resources:
          requests:
            memory: "200Mi"
            cpu: "100m"
          limits:
            memory: "300Mi"
            cpu: "200m"
        volumeMounts:
        - name: kafka-data
          mountPath: /var/lib/kafka/data
  volumeClaimTemplates:
  - metadata:
      name: kafka-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ebs-csi-gp2-freetier
      resources:
        requests:
          storage: 3Gi
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-micro-service
  namespace: ca2-learning-aws
spec:
  selector:
    app: kafka-micro
  ports:
  - port: 9092
    targetPort: 9092
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-micro-headless
  namespace: ca2-learning-aws
spec:
  clusterIP: None
  selector:
    app: kafka-micro
  ports:
  - port: 9092
    targetPort: 9092
  - port: 9093
    targetPort: 9093
EOF
```

### **Monitor Deployment**
```bash
# Watch pods come online
kubectl get pods -n ca2-learning-aws -w

# Check resource usage
kubectl top nodes
kubectl top pods -n ca2-learning-aws

# Verify storage provisioning
kubectl get pvc -n ca2-learning-aws
```

---

## **Step 7: Test the Cluster**

### **Test MongoDB**
```bash
# Test MongoDB connection
kubectl exec -it mongodb-micro-0 -n ca2-learning-aws -- mongosh --eval "db.adminCommand('ping')"

# Insert test data
kubectl exec -it mongodb-micro-0 -n ca2-learning-aws -- mongosh -u admin -p password123 --eval "
  db = db.getSiblingDB('plantmonitoring');
  db.sensors.insertOne({
    timestamp: new Date(),
    temperature: 23.5,
    humidity: 45,
    location: 'greenhouse-1'
  });
  db.sensors.find().pretty();
"
```

### **Test Kafka**
```bash
# Create topic
kubectl exec -it kafka-micro-0 -n ca2-learning-aws -- kafka-topics --create --topic plant-sensors --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1

# List topics
kubectl exec -it kafka-micro-0 -n ca2-learning-aws -- kafka-topics --list --bootstrap-server localhost:9092

# Test message publishing
kubectl exec -it kafka-micro-0 -n ca2-learning-aws -- bash -c "
echo 'Test sensor data: {\"temperature\": 24.1, \"timestamp\": \"$(date)\"}' | 
kafka-console-producer --topic plant-sensors --bootstrap-server localhost:9092
"
```

### **Test Service Discovery**
```bash
# Test internal DNS resolution
kubectl run test-pod --image=busybox --rm -it --restart=Never -n ca2-learning-aws -- nslookup mongodb-micro-service

# Test connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never -n ca2-learning-aws -- nc -zv kafka-micro-service 9092
```

---

## **Success Verification Checklist**

- [ ] All 3 nodes showing `Ready` status
- [ ] All system pods running in `kube-system` namespace
- [ ] MongoDB pod running and accepting connections
- [ ] Kafka pod running and able to create topics
- [ ] Persistent volumes provisioned and bound
- [ ] Service discovery working between pods
- [ ] Resource usage under control (no OOMKilled pods)
- [ ] Local kubectl access working

---

## **Monitoring and Maintenance**

### **Resource Monitoring**
```bash
# Check cluster resource usage
kubectl top nodes
kubectl top pods -A

# Monitor for resource pressure
kubectl describe nodes | grep -E "(Memory|CPU).*Pressure"
```

### **Troubleshooting Common Issues**

**Pod Stuck in Pending**:
```bash
kubectl describe pod <pod-name> -n ca2-learning-aws
# Look for resource constraints or scheduling issues
```

**High Memory Usage**:
```bash
# Scale down non-essential components temporarily
kubectl scale deployment coredns --replicas=1 -n kube-system
```

**Storage Issues**:
```bash
# Check EBS volume status
kubectl get pv
kubectl describe pvc <pvc-name> -n ca2-learning-aws
```

---

## **What You've Accomplished**

✅ **Manual Kubernetes Cluster**: Built from scratch using kubeadm
✅ **Multi-Node Architecture**: Real production-like setup 
✅ **Container Networking**: Flannel CNI configuration
✅ **Persistent Storage**: EBS CSI driver integration
✅ **Resource Optimization**: Free tier constraints management
✅ **Service Discovery**: Internal DNS and networking
✅ **StatefulSet Deployments**: Database and messaging services
✅ **Cost Efficiency**: $0/month operation within free tier

You now have a fully functional Kubernetes cluster that demonstrates all the core concepts while staying completely within AWS free tier limits!