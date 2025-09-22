# CA1 Assignment - Deployment and Teardown Logs

This directory contains the complete logs for the Infrastructure as Code (IaC) deployment and teardown processes as required for the CA1 assignment submission.

## Log Files

### Teardown Process
- **`teardown.log`** (102,281 bytes) - Complete teardown execution with terminal colors
- **`teardown-clean.log`** (79,191 bytes) - Clean teardown log without ANSI escape codes *(recommended for reading)*

### Deploy Process  
- **`deploy.log`** (131,368 bytes) - Complete deployment execution with terminal colors
- **`deploy-clean.log`** (117,200 bytes) - Clean deployment log without ANSI escape codes *(recommended for reading)*

## Process Overview

### Teardown Process (teardown-clean.log)
1. **Application Graceful Shutdown** - Stopped all Docker containers on VMs
2. **AWS Secrets Force Deletion** - Permanently deleted all secrets (no 7-day recovery)  
3. **Infrastructure Destruction** - Terraform destroyed all 32 AWS resources
4. **Cleanup Verification** - Verified no remaining instances, EIPs, or VPCs
5. **Local File Cleanup** - Removed temporary files and state

### Deploy Process (deploy-clean.log)
1. **Infrastructure Deployment** - Terraform created all AWS resources (VPC, subnets, instances, security groups, secrets)
2. **Inventory Generation** - Generated Ansible inventory from Terraform outputs
3. **Instance Readiness** - Waited for SSH connectivity via bastion host
4. **Application Deployment** - Deployed all services via Ansible:
   - Docker installation on all VMs
   - Persistent volume setup
   - Kafka broker with topics creation
   - MongoDB with authentication and initialization
   - Plant Care Processor with full connectivity
   - Home Assistant with MQTT broker and sensor simulation
5. **Health Validation** - Comprehensive 17-point system health check (all passed)

## Key Deployment Results

### Infrastructure Created
- **VPC**: vpc-0571f9cfea1d48079 with public/private subnets
- **Instances**: 4 EC2 t2.micro instances (1 public, 3 private)
- **Security Groups**: 4 groups with proper inter-service communication rules  
- **Secrets**: 3 AWS Secrets Manager secrets with generated passwords
- **Networking**: NAT Gateway, Internet Gateway, Elastic IPs, route tables

### Services Deployed
- **VM-1 (Kafka)**: 10.0.128.88 - Message broker with 3 topics
- **VM-2 (MongoDB)**: 10.0.128.150 - Database with authentication
- **VM-3 (Processor)**: 10.0.128.96 - Plant care processing service  
- **VM-4 (Home Assistant)**: 18.191.38.131 - Dashboard + MQTT broker + 2 plant sensors

### Health Check Results
✅ **17/17 Health Checks Passed**
- All Docker services running
- Kafka connectivity and messaging working
- MongoDB authentication and operations functional
- Processor connecting to all services (Kafka, MongoDB, MQTT)
- Home Assistant web interface accessible
- MQTT broker operational
- Plant sensors sending data to Kafka
- Complete data pipeline validated

## System Access

- **Home Assistant Dashboard**: http://18.191.38.131:8123
- **MQTT Broker**: 18.191.38.131:1883 (public access enabled)
- **SSH Bastion**: `ssh -i ~/.ssh/plant-monitoring-key.pem ubuntu@18.191.38.131`

## Assignment Compliance

These logs demonstrate:
- ✅ **Idempotent Provisioning** - Terraform manages all infrastructure declaratively
- ✅ **Parameterization** - Variables used for regions, instance types, credentials
- ✅ **Secure Secret Handling** - AWS Secrets Manager integration (no plaintext credentials)
- ✅ **Automated Deployment** - Single `./deploy.sh` command deploys entire stack
- ✅ **Automated Teardown** - Single `./teardown.sh` command destroys everything
- ✅ **Pipeline Validation** - End-to-end smoke tests prove data flow functionality
- ✅ **Documentation** - Complete README with setup and usage instructions

The logs show successful creation and destruction of cloud infrastructure with comprehensive validation, meeting all CA1 assignment requirements.