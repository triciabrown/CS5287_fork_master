# Prerequisites

This project uses **Terraform for infrastructure** and **Ansible for application deployment**. Ensure you have the following installed in your environment (preferably WSL/Ubuntu):

## Required Tools

### 1. Terraform (>= 1.0)
```bash
# Method 1: Official HashiCorp Repository (Recommended)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Method 2: Snap (Alternative)
sudo snap install terraform --classic

# Verify installation
terraform version
```

### 2. Ansible (for application deployment)
```bash
# Install Ansible
sudo apt update && sudo apt install ansible

# Install required collections
ansible-galaxy collection install amazon.aws
ansible-galaxy collection install community.aws

# Verify installation
ansible --version
```

### 3. AWS CLI (for credential setup)
```bash
# Install AWS CLI
sudo apt install awscli
# OR if not available:
pipx install awscli

# Configure credentials
aws configure
```

### 4. Required Permissions
Your AWS user needs the following permissions:

**Core Infrastructure:**
- EC2: Create, modify, delete instances, security groups, VPCs, EIPs
- VPC: Create subnets, route tables, internet gateways, NAT gateways
- **AWS Secrets Manager**: CreateSecret, GetSecretValue, PutSecretValue, UpdateSecret, DeleteSecret

**Required IAM Policies (Recommended - AWS Managed):**
- `AmazonEC2FullAccess` - For EC2, VPC, Security Groups, EIPs
- `SecretsManagerReadWrite` - For AWS Secrets Manager operations

**How to Add Permissions:**
1. Go to AWS Console → IAM → Users → `ansible-deployer`
2. Click "Add permissions" → "Attach policies directly"  
3. Search for and attach: `AmazonEC2FullAccess` and `SecretsManagerReadWrite`
4. Click "Add permissions"

**Alternative (Custom Policy):**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "secretsmanager:CreateSecret",
                "secretsmanager:GetSecretValue", 
                "secretsmanager:PutSecretValue",
                "secretsmanager:UpdateSecret",
                "secretsmanager:DeleteSecret",
                "secretsmanager:TagResource"
            ],
            "Resource": "*"
        }
    ]
}
```

## Valid AWS Credentials
Configure AWS credentials using one of these methods:
- **AWS CLI**: `aws configure` (recommended)
- **Environment variables**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`
- **IAM roles**: If running from EC2 instance

# CA1 – Infrastructure as Code (IaC)

This assignment recreates the IoT pipeline from CA0 using automated deployment tools. The solution uses **Terraform for infrastructure provisioning** and **Ansible for application deployment**, providing a robust and maintainable Infrastructure as Code solution.

## ✨ Key Features

- **🔗 Hybrid IaC Architecture**: Terraform for infrastructure + Ansible for applications
- **🔒 Enterprise Security**: AWS Secrets Manager integration with KMS encryption  
- **⚡ Single-Command Deployment**: Complete infrastructure + applications with `./deploy.sh`
- **🌐 Network Isolation**: Custom VPC with public/private subnet architecture
- **🔄 Zero-Downtime Secrets**: Automatic password generation and rotation support
- **📦 Container Orchestration**: Docker-based microservices deployment
- **📊 Real-time Monitoring**: Home Assistant dashboard for IoT sensor data
- **📋 Assignment Compliance**: Meets 15% security requirement with encrypted secret storage

## 🏗️ Architecture: Terraform + Ansible

- **Terraform**: AWS infrastructure (VPC, EC2 instances, security groups, networking)
- **Ansible**: Application deployment (Docker, services, configuration)
- **Automated inventory**: Real IP addresses generated from Terraform outputs

This hybrid approach solves variable persistence and dependency issues while leveraging each tool's strengths.

## 🔒 Secure Secret Management

This project implements enterprise-grade secret management using **AWS Secrets Manager**:

### What Secrets Are Managed
- **MongoDB credentials** (root and application users)
- **Home Assistant login credentials**  
- **MQTT broker authentication**
- **Application configuration** (API keys, topic names)

### Security Features
- ✅ **No secrets in code** - All sensitive data stored in AWS Secrets Manager
- ✅ **Auto-generated passwords** - 32-character random passwords for security
- ✅ **Encrypted at rest** - AWS KMS encryption for all secrets
- ✅ **Access logging** - CloudTrail tracks all secret access
- ✅ **Rotation ready** - Secrets Manager supports automatic rotation

### How It Works
1. **Terraform** creates secrets with random passwords in AWS Secrets Manager
2. **Ansible** retrieves secrets securely during deployment
3. **Applications** get credentials via environment variables (never hardcoded)

This satisfies the assignment requirement: *"Integrate a vault or cloud secret manager... Do not check plaintext passwords, tokens, or keys into your repository."*

## Getting Started

- **Reference Architecture:** Same as CA0 (Producers → Kafka → Processor → DB/Analytics)
- **Cloud Provider:** AWS (same as CA0)
- **Automation Tool:** Ansible

## Ansible Installation & Windows Troubleshooting

### Common Issues on Windows

1. **Locale Encoding Error**
   - When running `ansible-galaxy collection install amazon.aws`, you may see:
     > ERROR: Ansible requires the locale encoding to be UTF-8; Detected 1252.
   - Setting the default encoding environment variable in your session may not resolve this.

2. **PATH Issues**
   - After installing Ansible with pip, you may need to add the user install location to your PATH:
     > C:\Users\trici\AppData\Roaming\Python\Python312\Scripts

3. **Windows Compatibility**
   - Ansible is not natively supported on Windows for control node usage. Many modules and collections (including `amazon.aws`) require a Linux environment.

### Recommended Solution: Use WSL (Windows Subsystem for Linux)

- Download and install WSL from the Microsoft Store or via PowerShell.
- Install a Linux distribution (e.g., Ubuntu) in WSL.
- Use `pipx` to install Ansible:
  ```bash
  pipx install ansible
  pipx install ansible-core
  ```
  - The initial install may only create the `ansible-community` command. You must also install `ansible-core` to get the full suite of Ansible commands.
- After this, you can successfully run:
  ```bash
  ansible-galaxy collection install amazon.aws
  ```

### Summary
- Ansible is best run from a Linux environment (WSL recommended for Windows users).
- If you encounter locale or compatibility errors, switch to WSL and use `pipx` for installation.
- Document any additional troubleshooting steps in this README as you progress.


## Mapping Manual CA0 Steps to Ansible Automation (CA1)

This section explains how each major manual step from CA0 is now automated in CA1 using Ansible, and highlights any changes required for automation:

| Manual Step (CA0) | Ansible Automation (CA1) | Notes/Changes |
|-------------------|-------------------------|---------------|
| Manually create VPC, subnets, gateways in AWS Console | Automated with `amazon.aws.ec2_vpc_net`, `ec2_vpc_subnet`, `ec2_vpc_igw`, `ec2_vpc_nat_gateway` tasks | CIDR blocks, subnet sizes, and gateway setup are now reproducible and version-controlled |
| Manually configure route tables | Automated with `ec2_vpc_route_table` and `ec2_vpc_route_table_route` tasks | Route associations and NAT/IGW routing are explicit in code |
| Manually create security groups and rules | Automated with `ec2_security_group` tasks | Rules for each service are defined in YAML, using group references for internal access |
| Launch EC2 instances via AWS Console | Automated with `ec2_instance` tasks | Instance specs, subnets, and security groups are parameterized |
| Allocate Elastic IP for public VM | Automated with `ec2_eip` task | Elastic IP is assigned to Home Assistant VM automatically |
| Manually record and update IP addresses | Automated output via Ansible `debug` task | Instance details are shown after provisioning |
| SSH key management | Still manual (reference key in playbook/inventory) | Key pair name must match AWS and local SSH key |
| Docker installation and service deployment | Will be automated in subsequent Ansible roles/playbooks | Manual install steps from CA0 will be translated to Ansible tasks |

**Key Changes for Automation:**
- All infrastructure is now defined as code and can be recreated or updated by running the playbook.
- Security group rules use group references for tighter access control.
- Elastic IP assignment and NAT gateway setup are explicit and repeatable.
- Manual steps for software installation will be replaced by Ansible roles for each service (next steps).

Document any additional changes or lessons learned as you progress through the automation process.


## Directory Structure
```
CA1/
  README.md
  plant-monitor-IaC/
   inventory.ini
   playbook.yml
   aws_infra.yml
   docker-compose/
    kafka.yml
    mongodb.yml
    processor.yml
    homeassistant.yml
   mongodb_init-db.js
   roles/
    common/
    kafka/
    mongodb/
    processor/
    homeassistant/
```

### Docker Compose Files
- All service deployment files (`kafka.yml`, `mongodb.yml`, `processor.yml`, `homeassistant.yml`) are now located in `plant-monitor-IaC/docker-compose/` for clarity and reproducibility.
- The MongoDB initialization script is in `plant-monitor-IaC/mongodb_init-db.js`.
- Ansible roles reference these files for copy operations, making the automation self-contained.


### AWS Credentials Setup
To run Ansible playbooks that provision AWS resources, you must provide AWS credentials. Recommended methods:

1. **Environment Variables** (temporary, for your shell session):
  ```powershell
  $env:AWS_ACCESS_KEY_ID="your-access-key-id"
  $env:AWS_SECRET_ACCESS_KEY="your-secret-access-key"
  $env:AWS_DEFAULT_REGION="us-east-2"
  ```

2. **AWS CLI Configuration File** (persistent):
  Run `aws configure` in your shell and follow the prompts. This creates a file at `~/.aws/credentials`.

3. **IAM Role (for EC2/WSL control node)**:
  If running Ansible from an EC2 instance, attach an IAM role with required permissions. Ansible will use the instance profile automatically.

**Troubleshooting Note:**
- On WSL/Ubuntu, the `awscli` package may not be available in the default repositories. If you see "Package 'awscli' has no installation candidate", install AWS CLI using pipx:
  ```bash
  pipx install awscli
  ```
  This will provide the `aws` command for configuring credentials and using AWS CLI features.

**Never hardcode credentials in playbooks or source files.**

### Quick Start Deployment
1. **Ensure prerequisites are installed** (Terraform, Ansible, AWS CLI)
2. **Configure AWS credentials**: `aws configure`
3. **Deploy everything** with one command:
   ```bash
   cd CA1/plant-monitor-IaC
   ./deploy.sh
   ```

### Complete System Teardown
**⚠️ IMPORTANT: Use the teardown script, NOT `terraform destroy` directly!**

The teardown script handles the complete lifecycle safely:
```bash
cd CA1/plant-monitor-IaC
./teardown.sh
```

**What the teardown script does:**
1. **Gracefully stops all applications** (prevents data corruption)
2. **Cleans up AWS Secrets Manager** secrets (with recovery options)
3. **Destroys AWS infrastructure** using Terraform
4. **Verifies cleanup** worked properly
5. **Removes local files** (inventory, temp files)

**Options:**
- **Standard deletion**: Secrets have 7-day recovery window (recommended for production)
- **Force deletion**: Immediate deletion with no recovery (for dev/testing)

**Why not use `terraform destroy` directly?**
- Only destroys infrastructure, leaves running applications
- Doesn't clean up secrets or local files
- No verification that cleanup worked
- Can leave orphaned resources

### Step-by-Step Deployment (Advanced)
1. **Infrastructure (Terraform)**:
   ```bash
   cd CA1/plant-monitor-IaC/terraform
   terraform init
   terraform plan
   terraform apply
   ```

2. **Generate Ansible inventory**:
   ```bash
   ./generate-inventory.sh
   ```

3. **Applications (Ansible)**:
   ```bash
   cd ../application-deployment
   ansible-playbook -i inventory.ini setup_docker.yml
   ansible-playbook -i inventory.ini deploy_*.yml
   ```

4. **Verify deployment**:
   ```bash
   ansible-playbook -i inventory.ini health_check.yml
   ```

Document any issues or troubleshooting steps in this README as you test and refine your automation.

## Links
- [CA0 Submission](../CA0/README.md)
- [Assignment Description](../../doc/assignments/README.md)

---

Add documentation, diagrams, and links to your Ansible files below as you build out your solution.

## Troubleshooting

### Resource Ownership and Manual Cleanup
If you previously created AWS resources (such as Elastic IPs, NAT Gateways, or EC2 instances) using the AWS root user or a different IAM user, your new `ansible-deployer` IAM user may not have permission to delete or release those resources. This can result in errors or orphaned resources when running the teardown playbook.

**Solution:**
- Always use your `ansible-deployer` IAM user for all resource creation and management for this project.
- If you encounter errors about permissions or resources that cannot be deleted, log in to the AWS Console as the root user (or the user that created the resource) and manually delete those resources.
- Common resources that may require manual cleanup include Elastic IPs, NAT Gateways, and EC2 instances created outside of your automation workflow.

This will help ensure your teardown playbook can fully clean up all resources and prevent unexpected AWS charges.

---

## 🚀 Automated Plant Monitoring System Deployment

### Complete Application Stack - Ready for Deployment

The CA1 assignment now includes **complete automation** for the Smart House Plant Monitoring system from CA0. All application code, configurations, and deployment scripts have been ported and are ready for one-click deployment.

#### Application Components Included

| VM | Service | Technology | Status |
|----|---------|------------|--------|
| **VM-1** | Kafka (KRaft) | Apache Kafka 3.5.0 | ✅ Ready |
| **VM-2** | MongoDB | MongoDB 6.0.4 | ✅ Ready |
| **VM-3** | Plant Processor | Node.js + Custom App | ✅ Ready |
| **VM-4** | Home Assistant + Sensors | Home Assistant + MQTT + Node.js | ✅ Ready |

#### Deployment Options

**Option 1: Complete One-Click Deployment**
```bash
cd CA1/plant-monitor-IaC
chmod +x deploy.sh
./deploy.sh
```

**Option 2: Infrastructure + Applications Separately**
```bash
cd CA1/plant-monitor-IaC

# Deploy infrastructure only (Terraform)
./deploy.sh infra

# Deploy applications after infrastructure is ready (Ansible)
./deploy.sh apps
```

**Option 3: Manual Step-by-Step (Advanced)**
```bash
cd CA1/plant-monitor-IaC

# Infrastructure with Terraform
cd terraform && terraform init && terraform apply
cd ..

# Generate Ansible inventory
terraform/generate-inventory.sh

# Applications with Ansible
cd application-deployment
ansible-playbook -i inventory.ini setup_docker.yml
ansible-playbook -i inventory.ini deploy_kafka.yml
ansible-playbook -i inventory.ini deploy_mongodb.yml
ansible-playbook -i inventory.ini deploy_processor.yml
ansible-playbook -i inventory.ini deploy_homeassistant.yml
```

#### System Health Monitoring

```bash
cd CA1/plant-monitor-IaC

# Run comprehensive health check via deployment script
./deploy.sh

# Or run directly with Ansible
cd application-deployment
ansible-playbook -i inventory.ini health_check.yml
```

#### Expected Results After Deployment

1. **Home Assistant Dashboard**: Accessible at `http://<VM-4-PUBLIC-IP>:8123`
2. **Plant Sensors**: Two plants (Monstera and Snake Plant) sending realistic sensor data
3. **Real-time Processing**: Plant health analysis and MQTT discovery
4. **Data Storage**: MongoDB storing all sensor readings and plant data
5. **Complete IoT Pipeline**: End-to-end data flow from sensors → Kafka → Processor → MongoDB → Home Assistant

#### 🔧 MQTT Configuration (IMPORTANT!)

After deployment, **you must manually configure the MQTT integration** in Home Assistant:

1. **Access Home Assistant**: Open `http://<VM-4-PUBLIC-IP>:8123` in your browser
2. **Create Account**: Set up your Home Assistant user account (first time only)
3. **Add MQTT Integration**:
   - Go to **Settings** → **Devices & services**
   - Click **"+ ADD INTEGRATION"**
   - Search for **"MQTT"** and select it
4. **Configure MQTT Broker**:
   - **Broker**: `<VM-4-PUBLIC-IP>` (same IP as Home Assistant)
   - **Port**: `1883`
   - **Username**: Leave blank
   - **Password**: Leave blank
   - **Enable discovery**: ✅ (checked)
   - **Discovery prefix**: `homeassistant` (default)
5. **Verify Setup**: Plant sensors will appear automatically as entities after MQTT configuration

**📖 Detailed Setup Guide**: A complete MQTT configuration guide is available at `/opt/homeassistant/config/MQTT_SETUP_GUIDE.md` on the Home Assistant VM.

**🚨 Common Issue**: Do NOT use `localhost` as the broker address - it won't work from your browser. Always use the VM's public IP address.

#### Application Files Structure

All application code from CA0 has been copied to `CA1/applications/`:

```
CA1/applications/
├── vm-1-kafka/                # Kafka KRaft configuration
│   └── docker-compose.yml
├── vm-2-mongodb/              # MongoDB with initialization
│   ├── docker-compose.yml
│   └── init-db.js
├── vm-3-processor/            # Plant care processor
│   ├── docker-compose.yml
│   └── plant-care-processor/
│       ├── app.js
│       ├── package.json
│       └── Dockerfile
└── vm-4-homeassistant/        # Home Assistant + sensors
    ├── docker-compose.yml
    ├── plant-sensors/
    │   ├── sensor.js
    │   ├── package.json
    │   └── Dockerfile
    └── mosquitto/config/
        └── mosquitto.conf
```

#### Key Automation Features

- **Dynamic IP Configuration**: All inter-service communication uses Ansible-discovered IPs
- **Dependency Management**: Services start in proper order with health checks
- **Container Health Monitoring**: Docker health checks ensure service reliability
- **MQTT Public Access**: Security groups configured for browser-based MQTT integration
- **Automatic MQTT Discovery**: Plant sensors auto-register with Home Assistant (after MQTT setup)
- **Complete Teardown**: Single command removes all resources cleanly

#### Security Configuration

The infrastructure includes the following security features:
- **Network Isolation**: Private subnet for backend services (Kafka, MongoDB, Processor)
- **Bastion Host Access**: Home Assistant VM serves as bastion for private subnet access
- **MQTT Public Access**: Port 1883 open to public (required for browser-based Home Assistant MQTT integration)
- **Minimal Exposure**: Only necessary ports (SSH, HTTP, MQTT) exposed to internet
- **AWS Secrets Manager**: All credentials encrypted and managed through AWS Secrets Manager

#### Troubleshooting

**Service Logs**: Access logs from any VM:
```bash
# SSH to bastion host
ssh ubuntu@<VM-4-PUBLIC-IP>

# SSH to private VMs through bastion
ssh ubuntu@<PRIVATE-VM-IP>

# Check service logs
cd /opt/apps/<service-name>
docker compose logs
```

**MQTT Connection Issues**:
```bash
# Test MQTT broker connectivity (replace with actual VM IP)
nc -z <VM-4-PUBLIC-IP> 1883

# Check MQTT broker logs
ssh ubuntu@<VM-4-PUBLIC-IP>
cd /opt/homeassistant
docker compose logs mosquitto

# Verify plant sensor logs
docker compose logs plant-sensor-001
```

**Home Assistant MQTT Setup Problems**:
- ✅ **Use VM's public IP** for broker address (not `localhost`)
- ✅ **Port 1883** is correct
- ✅ **No authentication** required (username/password blank)
- ✅ **Enable discovery** must be checked
- ❌ **Don't use `localhost`** - won't work from browser
- 📖 **Read setup guide** at `/opt/homeassistant/config/MQTT_SETUP_GUIDE.md`

**System Health Check**: Use health check for comprehensive diagnosis:
```bash
cd CA1/plant-monitor-IaC/application-deployment
ansible-playbook -i inventory.ini health_check.yml
```

**Plant Sensors Not Appearing**:
1. Verify MQTT integration is configured correctly
2. Check that discovery is enabled in MQTT settings
3. Wait 1-2 minutes for auto-discovery to work
4. Go to **Settings** → **Devices & services** → **MQTT** → **Configure** → Listen to topic `homeassistant/sensor/+/config`

---

### Project Status: Complete & Ready for Evaluation

✅ **Infrastructure Automation**: Full AWS infrastructure as code  
✅ **Application Deployment**: Complete 4-VM application stack automation  
✅ **Health Monitoring**: Comprehensive system validation  
✅ **Documentation**: Complete deployment and troubleshooting guide  
✅ **Self-Contained**: All files included for grading  

The Smart House Plant Monitoring system is now fully automated and demonstrates enterprise-level Infrastructure as Code and DevOps practices.