# Exercise 4: Kafka Deployment & Service Networking

## **Learning Objectives**

In this exercise, you'll learn:
- How to deploy Kafka as a StatefulSet
- Kubernetes service discovery and networking
- How services connect different pods
- Port forwarding for testing
- Inter-service communication patterns

## **What We're Building**

```
┌─────────────────┐    ┌─────────────────┐
│   MongoDB Pod   │    │    Kafka Pod    │
│                 │    │                 │
│ Port: 27017     │    │ Port: 9092      │
│                 │    │                 │
└─────────────────┘    └─────────────────┘
         │                       │
         │                       │
┌─────────────────┐    ┌─────────────────┐
│ MongoDB Service │    │  Kafka Service  │
│                 │    │                 │
│ ClusterIP       │    │ ClusterIP       │
│ Port: 27017     │    │ Port: 9092      │
└─────────────────┘    └─────────────────┘
```

**Service Discovery**: Pods can reach each other using service names:
- MongoDB: `mongodb-service.ca2-learning.svc.cluster.local:27017`
- Kafka: `kafka-service.ca2-learning.svc.cluster.local:9092`
- Or short form: `mongodb-service:27017` and `kafka-service:9092`

## **Step 1: Deploy Kafka**

```bash
# Deploy Kafka StatefulSet and Service
kubectl apply -f kafka-statefulset.yaml

# Check deployment
kubectl get pods -n ca2-learning
kubectl get services -n ca2-learning
kubectl get pvc -n ca2-learning
```

## **Step 2: Test Service Discovery**

```bash
# Test from inside Kafka pod
kubectl exec -it kafka-0 -n ca2-learning -- bash

# Inside the pod, test MongoDB connection
nc -zv mongodb-service 27017

# Test Kafka is running
nc -zv localhost 9092
```

## **Step 3: Create Kafka Topics**

```bash
# Create a test topic
kubectl exec -it kafka-0 -n ca2-learning -- kafka-topics.sh \
  --create \
  --topic sensor-data \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 1

# List topics
kubectl exec -it kafka-0 -n ca2-learning -- kafka-topics.sh \
  --list \
  --bootstrap-server localhost:9092
```

## **Step 4: Test Message Publishing**

```bash
# Start a consumer in background
kubectl exec -it kafka-0 -n ca2-learning -- kafka-console-consumer.sh \
  --topic sensor-data \
  --bootstrap-server localhost:9092 \
  --from-beginning &

# Publish messages
kubectl exec -it kafka-0 -n ca2-learning -- kafka-console-producer.sh \
  --topic sensor-data \
  --bootstrap-server localhost:9092
```

## **Step 5: Port Forwarding for External Access**

```bash
# Forward Kafka port to your local machine
kubectl port-forward kafka-0 9092:9092 -n ca2-learning

# In another terminal, test with local tools (if you have kafka-clients installed)
# kafka-console-producer --topic sensor-data --bootstrap-server localhost:9092
```

## **Key Concepts Learned**

### **StatefulSets vs Deployments**
- **StatefulSets**: For stateful applications (databases, message queues)
  - Predictable pod names: kafka-0, kafka-1, kafka-2
  - Persistent storage per pod
  - Ordered startup/shutdown
  
- **Deployments**: For stateless applications (web servers, APIs)
  - Random pod names: web-app-xyz123, web-app-abc456
  - Shared storage or no persistent storage
  - Parallel startup/shutdown

### **Kubernetes Services**
- **ClusterIP**: Internal cluster communication (default)
- **NodePort**: Expose service on each node's IP
- **LoadBalancer**: Cloud provider load balancer
- **Headless**: Direct pod-to-pod communication

### **Service Discovery**
Kubernetes provides DNS for services:
- Full FQDN: `service-name.namespace.svc.cluster.local`
- Short form: `service-name` (within same namespace)

### **Networking Concepts**
- Pods get ephemeral IP addresses
- Services provide stable IP addresses and DNS names
- Port forwarding bridges cluster networking to localhost

## **What's Next?**

In Exercise 5, we'll:
- Deploy a data processor that connects MongoDB and Kafka
- Learn about ConfigMaps for application configuration
- Implement a complete data pipeline
- Monitor the flow of data between services

## **Troubleshooting**

**Pod stuck in Pending:**
```bash
kubectl describe pod kafka-0 -n ca2-learning
# Look for events and resource constraints
```

**Service not accessible:**
```bash
kubectl get endpoints -n ca2-learning
# Check if service has pod endpoints
```

**Storage issues:**
```bash
kubectl get pv
kubectl get pvc -n ca2-learning
# Check if volumes are bound correctly
```