# Tier-Based Security Groups - CA3

## Overview

This document describes the **tier-based security group architecture** implemented for CA3, which provides **defense-in-depth** security at the AWS/host level to complement Docker Swarm's encrypted overlay networks.

**Status**: ✅ Implemented in `terraform/security-groups-tiers.tf`

---

## Architecture

### Security Layers (Defense-in-Depth)

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: AWS Security Groups (Host-level firewall)         │
│  - Frontend Tier SG                                          │
│  - Messaging Tier SG                                         │
│  - Data Tier SG                                              │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: Docker Swarm Encrypted Overlay Networks           │
│  - frontnet (10.10.1.0/24)                                   │
│  - messagenet (10.10.2.0/24)                                 │
│  - datanet (10.10.3.0/24)                                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: Service-level Access Control                      │
│  - Network assignments per service                           │
│  - Published vs. internal-only ports                         │
└─────────────────────────────────────────────────────────────┘
```

---

## Security Groups

### 1. Frontend Tier Security Group

**Purpose**: User-facing services  
**Network**: frontnet (10.10.1.0/24)  
**Services**: Home Assistant, Mosquitto MQTT

#### Inbound Rules

| Port  | Protocol | Source      | Purpose                        | Public? |
|-------|----------|-------------|--------------------------------|---------|
| 8123  | TCP      | 0.0.0.0/0   | Home Assistant web UI          | ✅ YES  |
| 1883  | TCP      | VPC only    | MQTT (unencrypted)             | ❌ NO   |
| 8883  | TCP      | VPC only    | MQTT over TLS                  | ❌ NO   |

#### Outbound Rules

- **To Messaging Tier**: All TCP (for MQTT bridge to sensors)
- **To Data Tier**: All TCP (for observability scraping)
- **To Internet**: All traffic (for updates, external APIs)

---

### 2. Messaging Tier Security Group

**Purpose**: Data ingestion and streaming  
**Network**: messagenet (10.10.2.0/24)  
**Services**: Kafka, ZooKeeper, Sensors

#### Inbound Rules

| Port  | Protocol | Source            | Purpose                      | Public? |
|-------|----------|-------------------|------------------------------|---------|
| 9092  | TCP      | VPC only          | Kafka broker                 | ❌ NO   |
| 2181  | TCP      | VPC only          | ZooKeeper client             | ❌ NO   |
| 2888  | TCP      | VPC only          | ZooKeeper peer               | ❌ NO   |
| 3888  | TCP      | VPC only          | ZooKeeper leader election    | ❌ NO   |
| 9999  | TCP      | Data Tier SG only | Kafka JMX metrics            | ❌ NO   |
| All   | TCP      | Frontend Tier SG  | MQTT bridge                  | ❌ NO   |
| All   | TCP      | Data Tier SG      | Processor consuming Kafka    | ❌ NO   |

#### Outbound Rules

- **To Data Tier**: All TCP (for metrics export, processor writes)
- **To Internet**: All traffic (for updates)

**🔒 Security Note**: Kafka and ZooKeeper are **NOT publicly accessible**. This addresses CA2 feedback to minimize attack surface.

---

### 3. Data Tier Security Group

**Purpose**: Data storage, processing, and observability  
**Network**: datanet (10.10.3.0/24)  
**Services**: MongoDB, Processor, Grafana, Prometheus, Loki, Exporters

#### Inbound Rules

| Port  | Protocol | Source            | Purpose                      | Public? |
|-------|----------|-------------------|------------------------------|---------|
| 3000  | TCP      | 0.0.0.0/0         | **Grafana dashboard**        | ✅ YES  |
| 9090  | TCP      | 0.0.0.0/0         | **Prometheus UI**            | ✅ YES  |
| 27017 | TCP      | VPC only          | MongoDB                      | ❌ NO   |
| 3100  | TCP      | VPC only          | Loki log aggregation         | ❌ NO   |
| 9091  | TCP      | VPC only          | Sensor metrics endpoint      | ❌ NO   |
| 9092  | TCP      | VPC only          | Processor metrics endpoint   | ❌ NO   |
| 9100  | TCP      | VPC only          | Node Exporter                | ❌ NO   |
| 9216  | TCP      | VPC only          | MongoDB Exporter             | ❌ NO   |
| 9308  | TCP      | VPC only          | Kafka Exporter               | ❌ NO   |
| All   | TCP      | Frontend Tier SG  | Prometheus scraping frontend | ❌ NO   |
| All   | TCP      | Messaging Tier SG | Processor consuming Kafka    | ❌ NO   |

#### Outbound Rules

- **To Messaging Tier**: All TCP (for processor reading Kafka, Prometheus scraping)
- **To Frontend Tier**: All TCP (for Prometheus scraping)
- **To Internet**: All traffic (for updates)

**🎯 Observability Access**: Grafana (3000) and Prometheus (9090) are publicly accessible for dashboard viewing and debugging.

---

## EC2 Instance Assignments

### Manager Node (Public Subnet)

**Applied Security Groups**:
1. `swarm_manager_sg` - Node-level (SSH, Swarm management)
2. `frontend_tier_sg` - Hosts Home Assistant
3. `messaging_tier_sg` - Hosts Kafka, ZooKeeper
4. `data_tier_sg` - Hosts MongoDB, Observability stack

**Rationale**: Manager node can host services from any tier due to scheduling constraints.

### Worker Nodes (Private Subnet)

**Applied Security Groups**:
1. `swarm_worker_sg` - Node-level (SSH from manager, Swarm management)
2. `frontend_tier_sg` - Can host frontend services
3. `messaging_tier_sg` - Can host messaging services
4. `data_tier_sg` - Can host data services

**Rationale**: Workers can host services from any tier. Docker Swarm's overlay networks provide the actual isolation.

---

## How This Addresses CA2 Feedback

### CA2 Instructor Feedback:
> "Consider implementing host-level firewall rules (e.g., iptables or security groups) that map to the logical network tiers, further reinforcing isolation even if a container or overlay network is misconfigured."

### CA3 Implementation:

✅ **Created 3 tier-based security groups** mapping to logical networks  
✅ **Enforced minimal public exposure**:
   - Only 8123 (Home Assistant), 3000 (Grafana), 9090 (Prometheus) are public
   - Kafka, MongoDB, ZooKeeper are internal-only
✅ **Applied to all EC2 instances** for defense-in-depth  
✅ **Cross-tier communication** explicitly defined with security group references

---

## Verification

### After Terraform Apply

```bash
# Check security groups created
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*tier-sg" \
  --query 'SecurityGroups[*].[GroupName,GroupId]' \
  --output table

# Verify manager node security groups
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=manager" \
  --query 'Reservations[*].Instances[*].[InstanceId,SecurityGroups[*].GroupName]' \
  --output table

# Verify worker node security groups
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=worker" \
  --query 'Reservations[*].Instances[*].[InstanceId,SecurityGroups[*].GroupName]' \
  --output table
```

### Test Isolation

```bash
# From external machine: Should succeed
curl http://<MANAGER_IP>:8123  # Home Assistant
curl http://<MANAGER_IP>:3000  # Grafana
curl http://<MANAGER_IP>:9090  # Prometheus

# From external machine: Should FAIL (timeout)
nc -zv <MANAGER_IP> 9092   # Kafka - should timeout
nc -zv <MANAGER_IP> 27017  # MongoDB - should timeout
nc -zv <MANAGER_IP> 2181   # ZooKeeper - should timeout

# From manager node SSH: Should succeed (VPC access)
docker exec $(docker ps -q -f name=kafka) nc -zv kafka 9092
docker exec $(docker ps -q -f name=processor) nc -zv mongodb 27017
```

---

## Security Benefits

### 1. Defense-in-Depth
- **Layer 1**: AWS security groups block traffic at host level
- **Layer 2**: Docker overlay networks isolate at container level
- **Layer 3**: Published port configuration controls external access

### 2. Blast Radius Containment
- If a container in the messaging tier is compromised, attacker CANNOT:
  - Directly access MongoDB (blocked by security groups + network isolation)
  - Access Home Assistant UI (different tier)
  - Modify data tier services

### 3. Minimal Attack Surface
- Only 3 ports publicly exposed: 8123, 3000, 9090
- Critical infrastructure (Kafka, MongoDB) completely internal
- Metrics endpoints internal-only (scraped by Prometheus internally)

### 4. Compliance Alignment
- Follows principle of least privilege
- Explicit allow-list instead of default allow
- Auditability via AWS CloudTrail

---

## Comparison: Before vs. After

| Aspect                    | Before (CA2)              | After (CA3)                          |
|---------------------------|---------------------------|--------------------------------------|
| **Security Groups**       | 2 (node-based only)       | 5 (2 node + 3 tier-based)            |
| **Public Ports**          | Multiple (~8 ports)       | 3 ports (8123, 3000, 9090)           |
| **Kafka Access**          | Published to internet     | Internal VPC only ✅                 |
| **MongoDB Access**        | Published to internet     | Internal VPC only ✅                 |
| **Observability Access**  | Not published             | Grafana + Prometheus public ✅       |
| **Cross-tier Rules**      | Implicit allow-all        | Explicit security group references   |
| **Defense Layers**        | 1 (Docker networks)       | 3 (SG + networks + ports) ✅         |

---

## Deployment

### Apply Security Groups

```bash
cd /home/tricia/dev/CS5287_fork_master/CA3/plant-monitor-swarm-IaC/terraform

# Initialize Terraform (if new file added)
terraform init

# Preview changes
terraform plan

# Apply changes
terraform apply -auto-approve
```

### Expected Output

```
+ aws_security_group.frontend_tier_sg
+ aws_security_group.messaging_tier_sg
+ aws_security_group.data_tier_sg
~ aws_instance.swarm_managers[0]
  - vpc_security_group_ids: ["sg-xxxxx"]
  + vpc_security_group_ids: ["sg-xxxxx", "sg-yyyyy", "sg-zzzzz", "sg-aaaaa"]
~ aws_instance.swarm_workers[*]
  - vpc_security_group_ids: ["sg-xxxxx"]
  + vpc_security_group_ids: ["sg-xxxxx", "sg-yyyyy", "sg-zzzzz", "sg-aaaaa"]
```

---

## Troubleshooting

### Issue: Services Can't Communicate Across Tiers

**Symptom**: Processor can't reach Kafka or MongoDB  
**Check**: Verify security group IDs are correctly referenced
```bash
terraform output | grep tier_sg
```

**Solution**: Ensure cross-tier security group rules use `security_groups` parameter, not CIDR blocks.

### Issue: Grafana Not Accessible

**Symptom**: Cannot access http://<MANAGER_IP>:3000  
**Check**: Verify data tier security group has port 3000 open to 0.0.0.0/0
```bash
aws ec2 describe-security-groups \
  --group-ids <DATA_TIER_SG_ID> \
  --query 'SecurityGroups[*].IpPermissions[?FromPort==`3000`]'
```

**Solution**: Ensure port 3000 ingress rule exists with `cidr_blocks = ["0.0.0.0/0"]`.

### Issue: Terraform Circular Dependency

**Symptom**: Error creating security groups due to cross-references  
**Solution**: Security groups are created first, then cross-references are applied in a second pass. This is normal Terraform behavior.

---

## Future Enhancements

1. **TLS/SSL for Observability**:
   - Add port 3443 for Grafana HTTPS
   - Add port 9443 for Prometheus HTTPS

2. **VPN Access Only for Observability**:
   - Remove public access to 3000/9090
   - Require VPN connection to view dashboards

3. **IP Whitelisting**:
   - Replace `0.0.0.0/0` with specific IP ranges for production
   - Use AWS WAF for additional protection

4. **Separate Observability Tier**:
   - Create 4th tier security group for monitoring-only services
   - Further isolate Prometheus/Grafana from data processing

---

**Date**: November 2, 2024  
**Status**: ✅ Implemented and Ready for Deployment  
**CA2 Feedback**: ✅ Addressed - Host-level firewall rules implemented
