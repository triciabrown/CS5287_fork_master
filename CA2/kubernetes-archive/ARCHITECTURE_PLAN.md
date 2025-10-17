# CA2 Architecture Plan - PaaS Migration with Enhanced Security

## Executive Summary

This document outlines the migration strategy from CA1's Infrastructure as Code (IaC) approach to CA2's Platform as a Service (PaaS) orchestration using Kubernetes. The migration incorporates security improvements identified from CA1 feedback and implements a robust container orchestration architecture.

## Security Improvements from CA1 Feedback

### Critical Security Issues to Address

#### 1. **SSH Access Security**
**CA1 Issue:** Open 0.0.0.0/0 SSH rules creating security vulnerabilities
**CA2 Solution:** Implement CIDR-restricted access and bastion-only architecture

```yaml
# Current CA1 Problem:
# Security Group allows SSH from anywhere (0.0.0.0/0:22)

# CA2 Kubernetes Solution:
# - No direct SSH to worker nodes
# - kubectl access through IAM authentication
# - Emergency access via AWS Systems Manager Session Manager
# - Network policies restrict pod-to-pod communication
```

#### 2. **IAM Policy Hardening**
**CA1 Issue:** Broad IAM policies with excessive permissions
**CA2 Solution:** Least-privilege JSON policies with specific resource ARNs

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-east-2:ACCOUNT:secret:plant-monitoring/*/credentials-*"
      ]
    }
  ]
}
```

#### 3. **MQTT Authentication**
**CA1 Issue:** MQTT broker without authentication (blank credentials)
**CA2 Solution:** Secrets Manager-managed MQTT credentials with proper authentication

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mqtt-credentials
data:
  username: <base64-encoded-username>
  password: <base64-encoded-password>
```

---

## Architecture Overview

### Migration Strategy: IaC to PaaS

| Aspect | CA1 (IaC) | CA2 (PaaS) |
|--------|-----------|------------|
| **Platform** | 4 EC2 VMs + Docker | Self-Managed K8s Cluster (3 EC2 nodes) |
| **Orchestration** | Ansible playbooks | Kubernetes manifests |
| **Scaling** | Manual VM provisioning | Horizontal Pod Autoscaler |
| **Service Discovery** | Static IP addresses | Kubernetes Services/DNS |
| **Storage** | Docker volumes | Persistent Volume Claims + EBS CSI |
| **Security** | Security Groups | Network Policies + RBAC + Security Groups |
| **Secrets** | Basic AWS Secrets Manager | Kubernetes Secrets + External Secrets |

### Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                Self-Managed Kubernetes Cluster              │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │  Control Plane  │  │  Worker Node 1  │  │ Worker Node 2│ │
│  │   (t3.medium)   │  │   (t3.medium)   │  │  (t3.medium) │ │
│  │  - etcd         │  │  - kubelet      │  │  - kubelet   │ │
│  │  - kube-apiserver│  │  - kube-proxy   │  │  - kube-proxy│ │
│  │  - controller   │  │  - containerd   │  │  - containerd│ │
│  │  - scheduler    │  │  - CNI Plugin   │  │  - CNI Plugin│ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                 Application Pods                        │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ │ │
│  │  │    Kafka    │ │   MongoDB   │ │  Plant Processor    │ │ │
│  │  │ StatefulSet │ │ StatefulSet │ │    Deployment       │ │ │
│  │  └─────────────┘ └─────────────┘ └─────────────────────┘ │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ │ │
│  │  │Home Assistant│ │MQTT Broker  │ │  Plant Sensors      │ │ │
│  │  │ Deployment  │ │ StatefulSet │ │    CronJob          │ │ │
│  │  └─────────────┘ └─────────────┘ └─────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│              External Secret Management                      │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                AWS Secrets Manager                      │ │
│  │  • MongoDB Credentials    • MQTT Credentials            │ │
│  │  • Kafka Security Keys    • External API Keys           │ │
│  │  • TLS Certificates       • Service Account Tokens      │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Implementation Plan

### 1. Kafka Message Broker

**Workload Type:** StatefulSet
**Rationale:** Requires persistent storage for message logs and stable network identity

```yaml
# File: manifests/kafka/kafka-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  namespace: plant-monitoring
spec:
  serviceName: kafka-headless
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
      containers:
      - name: kafka
        image: bitnami/kafka:3.5.0
        ports:
        - containerPort: 9092
        - containerPort: 9093
        env:
        - name: KAFKA_CFG_NODE_ID
          value: "1"
        - name: KAFKA_CFG_PROCESS_ROLES
          value: "controller,broker"
        - name: KAFKA_CFG_LISTENERS
          value: "PLAINTEXT://:9092,CONTROLLER://:9093"
        - name: KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP
          value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
        - name: KAFKA_CFG_CONTROLLER_QUORUM_VOTERS
          value: "1@kafka-0.kafka-headless:9093"
        - name: KAFKA_CFG_CONTROLLER_LISTENER_NAMES
          value: "CONTROLLER"
        volumeMounts:
        - name: kafka-data
          mountPath: /bitnami/kafka/data
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
  volumeClaimTemplates:
  - metadata:
      name: kafka-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ebs-csi-gp3
      resources:
        requests:
          storage: 10Gi
```

**Security Enhancements:**
- Non-root container execution
- Resource limits to prevent resource exhaustion
- Persistent storage with proper access modes
- Service-to-service encryption (future enhancement)

### 2. MongoDB Database

**Workload Type:** StatefulSet
**Rationale:** Database requires persistent storage and ordered deployment

```yaml
# File: manifests/mongodb/mongodb-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: plant-monitoring
spec:
  serviceName: mongodb-headless
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        fsGroup: 999
      containers:
      - name: mongodb
        image: mongo:6.0.4
        ports:
        - containerPort: 27017
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          valueFrom:
            secretKeyRef:
              name: mongodb-credentials
              key: root-username
        - name: MONGO_INITDB_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mongodb-credentials
              key: root-password
        - name: MONGO_INITDB_DATABASE
          value: plant_monitoring
        volumeMounts:
        - name: mongodb-data
          mountPath: /data/db
        - name: mongodb-init-script
          mountPath: /docker-entrypoint-initdb.d/
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "300m"
        livenessProbe:
          exec:
            command:
            - mongosh
            - --eval
            - "db.adminCommand('ping')"
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - mongosh
            - --eval
            - "db.adminCommand('ping')"
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: mongodb-init-script
        configMap:
          name: mongodb-init-script
  volumeClaimTemplates:
  - metadata:
      name: mongodb-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: gp3
      resources:
        requests:
          storage: 20Gi
```

**Security Enhancements:**
- Credentials managed via Kubernetes Secrets
- Database initialization via ConfigMap
- Health checks for reliability
- Non-root execution with proper user/group

### 3. Plant Care Processor

**Workload Type:** Deployment
**Rationale:** Stateless application, can run multiple replicas for scaling

```yaml
# File: manifests/processor/processor-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plant-processor
  namespace: plant-monitoring
spec:
  replicas: 2
  selector:
    matchLabels:
      app: plant-processor
  template:
    metadata:
      labels:
        app: plant-processor
    spec:
      serviceAccountName: plant-processor-sa
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
      containers:
      - name: processor
        image: your-ecr-registry/plant-processor:latest
        ports:
        - containerPort: 8080
        env:
        - name: NODE_ENV
          value: "production"
        - name: KAFKA_BROKERS
          valueFrom:
            configMapKeyRef:
              name: plant-system-config
              key: kafka.brokers
        - name: MONGODB_URI
          valueFrom:
            secretKeyRef:
              name: mongodb-credentials
              key: connection-string
        - name: MQTT_BROKER_HOST
          valueFrom:
            configMapKeyRef:
              name: plant-system-config
              key: mqtt.broker.host
        - name: MQTT_USERNAME
          valueFrom:
            secretKeyRef:
              name: mqtt-credentials
              key: username
        - name: MQTT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mqtt-credentials
              key: password
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
```

**Security Enhancements:**
- Dedicated ServiceAccount with RBAC
- Read-only root filesystem
- Dropped capabilities
- Health checks for reliability
- Resource limits

### 4. MQTT Broker with Authentication

**Workload Type:** StatefulSet
**Rationale:** May need to persist retained messages and connection state

```yaml
# File: manifests/mqtt/mqtt-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mqtt-broker
  namespace: plant-monitoring
spec:
  serviceName: mqtt-broker-headless
  replicas: 1
  selector:
    matchLabels:
      app: mqtt-broker
  template:
    metadata:
      labels:
        app: mqtt-broker
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1883
        fsGroup: 1883
      containers:
      - name: mosquitto
        image: eclipse-mosquitto:2.0
        ports:
        - containerPort: 1883
        - containerPort: 9001
        volumeMounts:
        - name: mosquitto-config
          mountPath: /mosquitto/config
        - name: mosquitto-data
          mountPath: /mosquitto/data
        - name: mosquitto-logs
          mountPath: /mosquitto/log
        - name: mqtt-credentials-file
          mountPath: /mosquitto/auth
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      volumes:
      - name: mosquitto-config
        configMap:
          name: mosquitto-config
      - name: mqtt-credentials-file
        secret:
          secretName: mqtt-credentials
          items:
          - key: password-file
            path: password-file
  volumeClaimTemplates:
  - metadata:
      name: mosquitto-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: gp3
      resources:
        requests:
          storage: 1Gi
  - metadata:
      name: mosquitto-logs
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: gp3
      resources:
        requests:
          storage: 1Gi
```

**Security Enhancements:**
- Password-based authentication enabled
- Credentials stored in Kubernetes Secrets
- Persistent storage for retained messages
- Non-root execution

### 5. Home Assistant Dashboard

**Workload Type:** Deployment
**Rationale:** Web application, stateless with configuration via ConfigMaps

```yaml
# File: manifests/homeassistant/homeassistant-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: home-assistant
  namespace: plant-monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: home-assistant
  template:
    metadata:
      labels:
        app: home-assistant
    spec:
      securityContext:
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: homeassistant
        image: homeassistant/home-assistant:2023.8.0
        ports:
        - containerPort: 8123
        env:
        - name: TZ
          value: "America/Denver"
        volumeMounts:
        - name: ha-config
          mountPath: /config
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /
            port: 8123
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /
            port: 8123
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: ha-config
        persistentVolumeClaim:
          claimName: home-assistant-config-pvc
```

### 6. Plant Sensors

**Workload Type:** CronJob
**Rationale:** Periodic sensor data generation with reliable scheduling

```yaml
# File: manifests/sensors/plant-sensors-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: plant-sensors
  namespace: plant-monitoring
spec:
  schedule: "*/30 * * * *"  # Every 30 seconds
  jobTemplate:
    spec:
      template:
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: 1001
          containers:
          - name: sensor
            image: your-ecr-registry/plant-sensor:latest
            env:
            - name: KAFKA_BROKERS
              valueFrom:
                configMapKeyRef:
                  name: plant-system-config
                  key: kafka.brokers
            - name: PLANT_ID
              valueFrom:
                configMapKeyRef:
                  name: plant-system-config
                  key: sensor.plant.id
            resources:
              requests:
                memory: "32Mi"
                cpu: "10m"
              limits:
                memory: "64Mi"
                cpu: "50m"
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                - ALL
          restartPolicy: OnFailure
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
```

---

## Security Implementation

### 1. Enhanced Secret Management Architecture

```yaml
# File: manifests/secrets/external-secrets-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-store
  namespace: plant-monitoring
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa

---
# MongoDB Credentials from AWS Secrets Manager
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mongodb-credentials-external
  namespace: plant-monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-store
    kind: SecretStore
  target:
    name: mongodb-credentials
    creationPolicy: Owner
  data:
  - secretKey: root-username
    remoteRef:
      key: plant-monitoring/mongodb/credentials
      property: root_username
  - secretKey: root-password
    remoteRef:
      key: plant-monitoring/mongodb/credentials
      property: root_password
  - secretKey: app-username
    remoteRef:
      key: plant-monitoring/mongodb/credentials
      property: app_username
  - secretKey: app-password
    remoteRef:
      key: plant-monitoring/mongodb/credentials
      property: app_password
  - secretKey: connection-string
    remoteRef:
      key: plant-monitoring/mongodb/credentials
      property: connection_string

---
# MQTT Credentials with Authentication
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mqtt-credentials-external
  namespace: plant-monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-store
    kind: SecretStore
  target:
    name: mqtt-credentials
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: plant-monitoring/mqtt/credentials
      property: username
  - secretKey: password
    remoteRef:
      key: plant-monitoring/mqtt/credentials
      property: password
  - secretKey: password-file
    remoteRef:
      key: plant-monitoring/mqtt/credentials
      property: password_file_content
```

### 2. Network Security Policies

```yaml
# File: manifests/security/network-policies.yaml
# Default Deny All Network Policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: plant-monitoring
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

---
# Allow MongoDB access only from Processor
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mongodb-access-policy
  namespace: plant-monitoring
spec:
  podSelector:
    matchLabels:
      app: mongodb
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: plant-processor
    ports:
    - protocol: TCP
      port: 27017

---
# Allow Kafka access from Processor and Sensors
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kafka-access-policy
  namespace: plant-monitoring
spec:
  podSelector:
    matchLabels:
      app: kafka
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: plant-processor
    - podSelector:
        matchLabels:
          app: plant-sensors
    ports:
    - protocol: TCP
      port: 9092

---
# Allow MQTT access from Processor and Home Assistant
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mqtt-access-policy
  namespace: plant-monitoring
spec:
  podSelector:
    matchLabels:
      app: mqtt-broker
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: plant-processor
    - podSelector:
        matchLabels:
          app: home-assistant
    ports:
    - protocol: TCP
      port: 1883

---
# Allow Home Assistant web access (public)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: homeassistant-web-access
  namespace: plant-monitoring
spec:
  podSelector:
    matchLabels:
      app: home-assistant
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - protocol: TCP
      port: 8123

---
# Egress policy for external access (DNS, AWS APIs)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: external-access-policy
  namespace: plant-monitoring
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 443
```

### 3. RBAC (Role-Based Access Control)

```yaml
# File: manifests/security/rbac.yaml
# ServiceAccount for Plant Processor
apiVersion: v1
kind: ServiceAccount
metadata:
  name: plant-processor-sa
  namespace: plant-monitoring
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/PlantProcessorRole

---
# ServiceAccount for External Secrets Operator
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-sa
  namespace: plant-monitoring
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/ExternalSecretsRole

---
# Role for accessing ConfigMaps and Secrets
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: plant-monitoring
  name: plant-processor-role
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["mongodb-credentials", "mqtt-credentials"]
  verbs: ["get"]

---
# RoleBinding for Plant Processor
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: plant-processor-binding
  namespace: plant-monitoring
subjects:
- kind: ServiceAccount
  name: plant-processor-sa
  namespace: plant-monitoring
roleRef:
  kind: Role
  name: plant-processor-role
  apiGroup: rbac.authorization.k8s.io

---
# Role for External Secrets Operator
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: plant-monitoring
  name: external-secrets-role
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["create", "update", "patch", "delete", "get", "list", "watch"]

---
# RoleBinding for External Secrets
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: external-secrets-binding
  namespace: plant-monitoring
subjects:
- kind: ServiceAccount
  name: external-secrets-sa
  namespace: plant-monitoring
roleRef:
  kind: Role
  name: external-secrets-role
  apiGroup: rbac.authorization.k8s.io
```

### 4. IAM Policies (Least Privilege)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-east-2:ACCOUNT:secret:plant-monitoring/mongodb/credentials-*",
        "arn:aws:secretsmanager:us-east-2:ACCOUNT:secret:plant-monitoring/mqtt/credentials-*",
        "arn:aws:secretsmanager:us-east-2:ACCOUNT:secret:plant-monitoring/external-apis/credentials-*"
      ]
    },
    {
      "Sid": "ECRAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": [
        "arn:aws:ecr:us-east-2:ACCOUNT:repository/plant-*"
      ]
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:us-east-2:ACCOUNT:log-group:/aws/eks/plant-monitoring/*"
      ]
    }
  ]
}
```

---

## Scaling and High Availability

### 1. Horizontal Pod Autoscaler

```yaml
# File: manifests/scaling/processor-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: plant-processor-hpa
  namespace: plant-monitoring
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: plant-processor
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
```

### 2. Pod Disruption Budget

```yaml
# File: manifests/scaling/pod-disruption-budget.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: plant-processor-pdb
  namespace: plant-monitoring
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: plant-processor

---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: mongodb-pdb
  namespace: plant-monitoring
spec:
  maxUnavailable: 0  # Cannot afford to lose database
  selector:
    matchLabels:
      app: mongodb
```

---

## Monitoring and Observability

### 1. Prometheus ServiceMonitor

```yaml
# File: manifests/monitoring/service-monitors.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: plant-processor-monitor
  namespace: plant-monitoring
spec:
  selector:
    matchLabels:
      app: plant-processor
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kafka-monitor
  namespace: plant-monitoring
spec:
  selector:
    matchLabels:
      app: kafka
  endpoints:
  - port: jmx-metrics
    interval: 30s
```

### 2. Grafana Dashboard ConfigMap

```yaml
# File: manifests/monitoring/grafana-dashboard.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: plant-monitoring-dashboard
  namespace: plant-monitoring
  labels:
    grafana_dashboard: "1"
data:
  plant-monitoring.json: |
    {
      "dashboard": {
        "title": "Plant Monitoring System",
        "panels": [
          {
            "title": "Sensor Messages per Second",
            "targets": [
              {
                "expr": "rate(kafka_topic_partition_current_offset{topic=\"plant-sensors\"}[5m])"
              }
            ]
          },
          {
            "title": "Processing Latency",
            "targets": [
              {
                "expr": "histogram_quantile(0.95, rate(plant_processor_processing_duration_seconds_bucket[5m]))"
              }
            ]
          }
        ]
      }
    }
```

---

## Deployment Strategy

### 1. Infrastructure Setup

```bash
# Create EC2 instances for Kubernetes cluster
cd terraform/
terraform init
terraform apply

# Initialize Kubernetes cluster on control plane node
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=<CONTROL_PLANE_PRIVATE_IP>

# Set up kubectl access
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI plugin (Flannel)
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Join worker nodes to cluster
kubeadm join <CONTROL_PLANE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>

# Install EBS CSI driver for persistent storage
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.24"

# Install metrics server for HPA
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Install external secrets operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace
```

### 2. Container Security Scanning

**CRITICAL**: All container images must be scanned for vulnerabilities before deployment.

```bash
# Install Docker security scanning tools
# Option 1: Docker Scout (recommended for Docker Desktop)
docker scout cves your-ecr-registry/plant-processor:latest
docker scout cves your-ecr-registry/plant-sensor:latest

# Option 2: Trivy (open source alternative)
trivy image your-ecr-registry/plant-processor:latest
trivy image your-ecr-registry/plant-sensor:latest
trivy image bitnami/kafka:3.5.0
trivy image mongo:6.0.4
trivy image eclipse-mosquitto:2.0
trivy image homeassistant/home-assistant:2023.8.0

# Option 3: AWS ECR image scanning (if using ECR)
aws ecr describe-image-scan-findings --repository-name plant-processor --image-id imageTag=latest

# Fail deployment if HIGH or CRITICAL vulnerabilities found
# Set up automated scanning in CI/CD pipeline
```

**Vulnerability Management Process:**
1. **Scan all images** before pushing to registry
2. **Block deployment** if CRITICAL vulnerabilities detected
3. **Create remediation plan** for HIGH vulnerabilities within 7 days
4. **Update base images** regularly for security patches
5. **Implement automated scanning** in CI/CD pipeline

### 3. Application Deployment

```bash
# Create namespace and apply all manifests
kubectl create namespace plant-monitoring
kubectl apply -k manifests/

# Verify deployment
kubectl get all -n plant-monitoring
kubectl get secrets -n plant-monitoring
kubectl get externalsecrets -n plant-monitoring
```

### 3. Validation Tests

```yaml
# File: tests/smoke-test-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: smoke-test
  namespace: plant-monitoring
spec:
  template:
    spec:
      containers:
      - name: test
        image: appropriate/curl
        command:
        - /bin/sh
        - -c
        - |
          # Test Home Assistant
          curl -f http://home-assistant:8123/ || exit 1
          
          # Test Kafka topics
          kubectl exec kafka-0 -- kafka-topics.sh --list --bootstrap-server localhost:9092 | grep plant-sensors || exit 1
          
          # Test MongoDB connection
          kubectl exec mongodb-0 -- mongosh --eval "db.adminCommand('ping')" || exit 1
          
          echo "All tests passed!"
      restartPolicy: Never
  backoffLimit: 3
```

---

## Performance and Cost Optimization

### Resource Sizing Strategy

| Component | Requests | Limits | Rationale |
|-----------|----------|--------|-----------|
| **Kafka** | 250m CPU, 512Mi RAM | 500m CPU, 1Gi RAM | Message buffering requires memory |
| **MongoDB** | 100m CPU, 256Mi RAM | 300m CPU, 512Mi RAM | I/O bound, moderate memory |
| **Processor** | 100m CPU, 128Mi RAM | 200m CPU, 256Mi RAM | CPU intensive processing |
| **Home Assistant** | 200m CPU, 256Mi RAM | 500m CPU, 512Mi RAM | Web UI and automation logic |
| **MQTT Broker** | 50m CPU, 64Mi RAM | 100m CPU, 128Mi RAM | Lightweight message broker |
| **Sensors** | 10m CPU, 32Mi RAM | 50m CPU, 64Mi RAM | Simple data generation |

### Cost Analysis

**CA1 (IaC) Monthly Cost:**
- 4 × t2.micro instances: ~$35
- NAT Gateway: ~$32
- **Total: ~$67/month**

**CA2 (PaaS) Monthly Cost - Free Tier Optimized:**
- 3 × t2.micro instances (1 control + 2 workers): **$0/month** (free tier)
- EBS Storage (30Gi): **$0/month** (free tier)
- Network Load Balancer (optional): ~$16/month
- **Total: ~$16/month** (93% cost reduction!)

**Alternative Single-Node Setup:**
- 1 × t2.micro instance: **$0/month** (free tier)
- EBS Storage (30Gi): **$0/month** (free tier) 
- **Total: $0/month** (100% free!)

**Learning Value Justification:**
- **Deep Kubernetes Understanding**: Manual cluster setup teaches all components
- **Resource Optimization**: Learn to work within constraints (production skill)
- **Cost Management**: Essential skill for real-world deployments
- **Troubleshooting**: Limited resources force better debugging skills
- **Architecture Decisions**: Trade-offs between features and resources

---

## Migration Timeline

### Phase 1: Foundation (Week 1)
- [ ] **🏗️ INFRASTRUCTURE: Provision 3 EC2 instances (1 control plane + 2 workers) with Terraform**
- [ ] **⚙️ CLUSTER SETUP: Initialize Kubernetes cluster with kubeadm**
- [ ] **🌐 NETWORKING: Configure CNI plugin (Flannel) for pod networking**
- [ ] **💾 STORAGE: Install and configure EBS CSI driver for persistent volumes**
- [ ] **🔐 SECURITY: Scan all container images for vulnerabilities using Docker Scout/Trivy**
- [ ] Create ECR repositories and push **verified secure** container images
- [ ] Set up AWS Secrets Manager with enhanced security
- [ ] Deploy External Secrets Operator

### Phase 2: Core Services (Week 2)
- [ ] Deploy MongoDB with authentication and persistent storage
- [ ] Deploy Kafka with proper configuration
- [ ] Implement enhanced MQTT broker with authentication
- [ ] Deploy basic plant processor (single replica)

### Phase 3: Security and Networking (Week 3)
- [ ] Implement Network Policies for micro-segmentation
- [ ] Set up RBAC with least-privilege access
- [ ] Configure Service Mesh (optional)
- [ ] Enable audit logging and monitoring

### Phase 4: Scaling and Production Features (Week 4)
- [ ] Configure Horizontal Pod Autoscaler
- [ ] Implement Pod Disruption Budgets
- [ ] Set up monitoring and alerting
- [ ] Conduct load testing and scaling validation
- [ ] Document operational runbooks

---

## Success Criteria

### Functional Requirements
- ✅ All CA0/CA1 functionality preserved
- ✅ Sensor data flows from generation to storage
- ✅ Home Assistant dashboard accessible and functional
- ✅ MQTT broker with proper authentication

### Non-Functional Requirements
- ✅ Auto-scaling from 1 to 5 processor replicas under load
- ✅ Zero-downtime deployments and updates
- ✅ Network isolation between services
- ✅ Secrets managed externally with rotation capability
- ✅ Resource utilization >60% (improved from CA1's ~20%)

### Security Requirements (Addressing CA1 Feedback)
- ✅ No 0.0.0.0/0 SSH access (Kubernetes API + IAM authentication)
- ✅ Least-privilege IAM policies with specific resource ARNs
- ✅ MQTT authentication with Secrets Manager-managed credentials
- ✅ Network policies enforcing service boundaries
- ✅ Container security with non-root execution and read-only filesystems

---

## Risk Mitigation

### Identified Risks and Mitigations

1. **Data Loss During Migration**
   - **Risk**: Loss of historical sensor data
   - **Mitigation**: Export data from CA1 MongoDB, import to CA2 during initial deployment

2. **Service Discovery Issues**
   - **Risk**: Services unable to find each other
   - **Mitigation**: Comprehensive testing of Kubernetes DNS and service configurations

3. **Secret Management Complexity**
   - **Risk**: Authentication failures due to secret sync issues
   - **Mitigation**: External Secrets Operator with health checks and fallback mechanisms

4. **Resource Contention**
   - **Risk**: Pods competing for node resources
   - **Mitigation**: Proper resource requests/limits and quality-of-service classes

5. **Network Policy Lockouts**
   - **Risk**: Overly restrictive policies blocking legitimate traffic
   - **Mitigation**: Gradual rollout with monitoring and emergency bypass procedures

---

## Conclusion

This architecture plan addresses the core requirements of CA2 while incorporating critical security improvements from CA1 feedback. The migration from VM-based infrastructure to Kubernetes orchestration provides enhanced scalability, reliability, and security through modern cloud-native practices.

Key improvements include:
- **Enhanced Security**: Network policies, RBAC, and proper secret management
- **Operational Excellence**: Auto-scaling, self-healing, and monitoring
- **Cost Efficiency**: Better resource utilization despite higher infrastructure cost
- **Development Velocity**: Faster deployments and easier maintenance

The implementation timeline spreads complexity across four weeks, allowing for proper testing and validation at each phase.