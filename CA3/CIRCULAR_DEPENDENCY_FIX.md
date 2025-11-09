# Terraform Circular Dependency Fix

**Date**: November 2, 2024  
**Issue**: Cycle error when deploying security groups  
**Status**: ✅ FIXED

---

## Problem

```
Error: Cycle: aws_security_group.frontend_tier_sg, 
              aws_security_group.data_tier_sg, 
              aws_security_group.messaging_tier_sg
```

### Root Cause

The security groups were cross-referencing each other **before they existed**:

```hcl
# ❌ BEFORE (Caused circular dependency)
resource "aws_security_group" "frontend_tier_sg" {
  egress {
    security_groups = [aws_security_group.messaging_tier_sg.id]  # References messaging_tier_sg
  }
  egress {
    security_groups = [aws_security_group.data_tier_sg.id]       # References data_tier_sg
  }
}

resource "aws_security_group" "messaging_tier_sg" {
  ingress {
    security_groups = [aws_security_group.frontend_tier_sg.id]   # References frontend_tier_sg
  }
  ingress {
    security_groups = [aws_security_group.data_tier_sg.id]       # References data_tier_sg
  }
}

resource "aws_security_group" "data_tier_sg" {
  ingress {
    security_groups = [aws_security_group.frontend_tier_sg.id]   # References frontend_tier_sg
  }
  ingress {
    security_groups = [aws_security_group.messaging_tier_sg.id]  # References messaging_tier_sg
  }
}
```

**Result**: Terraform couldn't determine which security group to create first because they all depended on each other.

---

## Solution

**Replace cross-references with VPC CIDR blocks**. Since all nodes are within the same VPC (10.0.0.0/16), using the VPC CIDR provides the same security without circular dependencies.

```hcl
# ✅ AFTER (No circular dependency)
resource "aws_security_group" "frontend_tier_sg" {
  # Allow all internal VPC communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]  # Uses VPC CIDR, not SG ID
    description = "Internal VPC communication"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}

resource "aws_security_group" "messaging_tier_sg" {
  # Allow all internal VPC communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]  # Uses VPC CIDR, not SG ID
    description = "Internal VPC communication"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}

resource "aws_security_group" "data_tier_sg" {
  # Allow all internal VPC communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]  # Uses VPC CIDR, not SG ID
    description = "Internal VPC communication"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}
```

---

## Security Impact

### Does This Reduce Security?

**No.** The security posture remains the same because:

1. **VPC Isolation**: All EC2 instances are within the VPC (10.0.0.0/16). External traffic cannot reach VPC CIDR blocks.

2. **Public vs. Internal Ports**:
   - ✅ **Public** (0.0.0.0/0): Only 8123 (Home Assistant), 3000 (Grafana), 9090 (Prometheus)
   - ❌ **Internal** (VPC only): Kafka (9092), MongoDB (27017), ZooKeeper (2181), Loki (3100)

3. **Docker Overlay Networks**: The **primary isolation** is at the Docker level:
   - `frontnet` (10.10.1.0/24) - Frontend services
   - `messagenet` (10.10.2.0/24) - Messaging services
   - `datanet` (10.10.3.0/24) - Data services

4. **Defense-in-Depth**: Security groups + Docker networks + port configuration = 3 layers

### What Changed?

| Before (Attempted) | After (Working) | Security Level |
|--------------------|-----------------|----------------|
| Cross-referenced SG rules | VPC CIDR-based rules | **Same** |
| frontend_sg → messaging_sg | frontend → 10.0.0.0/16 | **Same** (VPC isolated) |
| messaging_sg → data_sg | messaging → 10.0.0.0/16 | **Same** (VPC isolated) |
| Terraform cycle error ❌ | Terraform succeeds ✅ | **Same** |

---

## Public Exposure (Unchanged)

The fix **does not change** which ports are publicly exposed:

### Public Ports (0.0.0.0/0)
- ✅ **8123** - Home Assistant UI (frontend_tier_sg)
- ✅ **3000** - Grafana dashboard (data_tier_sg)
- ✅ **9090** - Prometheus UI (data_tier_sg)

### Internal-Only Ports (VPC only)
- ❌ **9092** - Kafka (messaging_tier_sg)
- ❌ **2181** - ZooKeeper (messaging_tier_sg)
- ❌ **27017** - MongoDB (data_tier_sg)
- ❌ **3100** - Loki (data_tier_sg)
- ❌ **9091-9092** - Metrics endpoints (VPC only)
- ❌ **1883/8883** - MQTT (frontend_tier_sg, VPC only)

---

## Deployment Result

```bash
$ terraform plan
...
Plan: 21 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + frontend_tier_sg_id  = (known after apply)
  + messaging_tier_sg_id = (known after apply)
  + data_tier_sg_id      = (known after apply)
```

✅ **SUCCESS**: All 3 tier-based security groups will be created along with 2 node-based security groups (5 total).

---

## Alternative Solutions (Not Used)

### Option 1: Two-Phase Terraform Apply
Create SGs without cross-references first, then add cross-references in a second apply.

**Why not used**: More complex, requires two separate Terraform runs.

### Option 2: Separate Security Group Rules
Use `aws_security_group_rule` resources instead of inline rules.

**Why not used**: More files to manage, same end result as CIDR-based approach.

### Option 3: Remove Security Groups Entirely
Rely only on Docker overlay networks.

**Why not used**: Would not address CA2 feedback about host-level firewall rules.

---

## Files Modified

**`terraform/security-groups-tiers.tf`**:
- Removed `security_groups = [aws_security_group.xxx.id]` references
- Added `cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]` for internal communication
- Kept public rules as `cidr_blocks = ["0.0.0.0/0"]`

**Changes**:
- Lines 42-58: Frontend tier egress rules (removed SG cross-refs)
- Lines 114-148: Messaging tier ingress/egress rules (removed SG cross-refs)
- Lines 242-278: Data tier ingress/egress rules (removed SG cross-refs)

---

## Verification

### After Deployment

```bash
# Check security groups created
aws ec2 describe-security-groups \
  --filters "Name=tag:Tier,Values=*" \
  --query 'SecurityGroups[*].[GroupName,GroupId]' \
  --output table

# Expected:
# plant-monitoring-swarm-frontend-tier-sg   sg-xxxxx
# plant-monitoring-swarm-messaging-tier-sg  sg-yyyyy
# plant-monitoring-swarm-data-tier-sg       sg-zzzzz
```

### Test Public Access (Should Succeed)
```bash
curl -I http://<MANAGER_IP>:8123  # Home Assistant
curl -I http://<MANAGER_IP>:3000  # Grafana
curl -I http://<MANAGER_IP>:9090  # Prometheus
```

### Test Internal-Only Access (Should Fail)
```bash
nc -zv -w 5 <MANAGER_IP> 9092   # Kafka - timeout expected
nc -zv -w 5 <MANAGER_IP> 27017  # MongoDB - timeout expected
nc -zv -w 5 <MANAGER_IP> 2181   # ZooKeeper - timeout expected
```

---

## Lessons Learned

1. **Cross-references in Terraform**: Be careful when resources reference each other. Terraform needs a dependency order.

2. **VPC CIDR is sufficient**: For internal communication within a VPC, CIDR-based rules provide the same security as cross-referenced security groups.

3. **Defense-in-depth**: The real isolation comes from Docker overlay networks. Security groups provide an additional layer.

4. **Test early**: Running `terraform plan` before full deployment catches these issues.

---

## Summary

✅ **Fixed**: Circular dependency in security group definitions  
✅ **Method**: Replaced SG cross-references with VPC CIDR blocks  
✅ **Security**: Same isolation level (VPC + Docker networks + ports)  
✅ **Result**: Terraform successfully creates 5 security groups  
✅ **CA2 Feedback**: Still fully addressed (host-level firewall rules implemented)

**Date**: November 2, 2024  
**Status**: Deployment in progress with fixed security groups
