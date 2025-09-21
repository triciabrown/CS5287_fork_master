# Plant Monitoring System - Terraform + Ansible Architecture

This project deploys an IoT plant monitoring system using **Terraform for infrastructure** and **Ansible for application deployment**. This architecture leverages the strengths of both tools for optimal infrastructure management.

## 🏗️ Architecture Overview

### Infrastructure (Terraform)
- **VPC** with public/private subnets
- **4 EC2 instances** (Kafka, MongoDB, Processor, Home Assistant)
- **Security Groups** with proper cross-references
- **NAT Gateway** for private subnet internet access
- **Elastic IPs** for persistent public access
- **Route Tables** for traffic routing

### Applications (Ansible)
- **Docker** installation and configuration
- **Kafka** message broker deployment
- **MongoDB** database setup with authentication
- **Data Processor** service for plant care logic
- **Home Assistant** dashboard and MQTT broker

## 📁 Project Structure

```
CA1/plant-monitor-IaC/
├── deploy.sh                    # Main deployment script
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                 # Main Terraform configuration
│   ├── variables.tf            # Input variables
│   ├── outputs.tf              # Output values
│   ├── generate-inventory.sh   # Inventory generation script
│   ├── templates/
│   │   └── inventory.tpl       # Ansible inventory template
│   └── modules/
│       ├── networking/         # VPC, subnets, gateways
│       ├── security/           # Security groups and rules
│       └── compute/            # EC2 instances and EIPs
├── application-deployment/     # Ansible playbooks
│   ├── inventory.ini           # Generated automatically
│   ├── group_vars/            # Ansible variables
│   ├── setup_docker.yml       # Docker installation
│   ├── deploy_*.yml           # Application deployments
│   └── health_check.yml       # System health validation
└── archive/                   # Archived Ansible IaC files
    └── iac-ansible/           # Original Ansible infrastructure code
```

## 🚀 Quick Start

### Prerequisites

1. **Install Terraform** (>= 1.0)
   ```bash
   # Download from https://developer.hashicorp.com/terraform/downloads
   # Or use package manager:
   sudo apt update && sudo apt install terraform
   ```

2. **Install Ansible**
   ```bash
   sudo apt update && sudo apt install ansible
   ```

3. **Configure AWS CLI**
   ```bash
   aws configure
   # Enter your AWS Access Key, Secret Key, Region (us-east-2), Output format (json)
   ```

4. **Set up SSH Key**
   ```bash
   # Download your AWS key pair and place it at:
   ~/.ssh/plant-monitoring-key.pem
   chmod 400 ~/.ssh/plant-monitoring-key.pem
   ```

### First-Time Setup

⚠️ **IMPORTANT**: Before running any deployment commands, initialize Terraform:

```bash
cd terraform
terraform init
cd ..
```

This downloads the required AWS and Random providers and sets up the Terraform working directory. **You must do this once before your first deployment.**

### Deployment

1. **Full Deployment** (Infrastructure + Applications)
   ```bash
   ./deploy.sh
   ```

2. **Infrastructure Only**
   ```bash
   ./deploy.sh infra
   ```

3. **Applications Only** (after infrastructure exists)
   ```bash
   ./deploy.sh apps
   ```

4. **Cleanup**
   ```bash
   # Complete teardown with interactive prompts
   ./teardown.sh
   
   # Quick cleanup (same as teardown.sh)
   ./deploy.sh clean
   ```

   **Secret Deletion Options:**
   - **Standard (Production)**: 7-day recovery window for AWS Secrets
   - **Force Delete (Development)**: Immediate deletion, no recovery possible

## 🔧 Configuration

### Terraform Variables

Customize infrastructure in `terraform/variables.tf`:

```hcl
variable "aws_region" {
  default = "us-east-2"  # Change AWS region
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"  # VPC CIDR block
}

variable "instance_type" {
  default = "t2.micro"  # EC2 instance size
}
```

### Ansible Variables

Customize applications in `application-deployment/group_vars/all.yml`:

```yaml
# Docker configuration
docker_compose_version: "2.21.0"

# Application ports
kafka_port: 9092
mongodb_port: 27017
homeassistant_port: 8123
```

## 🌐 Network Architecture

```
Internet
    │
    ├── Internet Gateway
    │
    ├── Public Subnet (10.0.0.0/24)
    │   └── VM-4-HomeAssistant (Bastion + Dashboard)
    │       └── Elastic IP (Public Access)
    │
    ├── NAT Gateway
    │
    └── Private Subnet (10.0.128.0/24)
        ├── VM-1-Kafka (Message Broker)
        ├── VM-2-MongoDB (Database)
        └── VM-3-Processor (Data Processing)
```

## 🔐 Security Groups

| Service | Ports | Source | Purpose |
|---------|-------|---------|----------|
| **Kafka** | 22 | 0.0.0.0/0 | SSH Admin |
| | 9092 | VPC CIDR | Kafka Broker |
| **MongoDB** | 22 | 0.0.0.0/0 | SSH Admin |
| | 27017 | Processor SG | Database Access |
| **Processor** | 22 | 0.0.0.0/0 | SSH Admin |
| | 8080 | HA SG | API Access |
| | 9092 | Kafka SG | Consume Messages |
| | 27017 | MongoDB SG | Store Data |
| | 1883 | HA SG | Publish MQTT |
| **Home Assistant** | 22 | 0.0.0.0/0 | SSH + Bastion |
| | 8123 | 0.0.0.0/0 | Dashboard |
| | 1883 | Processor SG | MQTT Broker |

## 📊 Outputs and Access

After deployment, access your system:

### SSH Access
- **Bastion Host**: `ssh -i ~/.ssh/plant-monitoring-key.pem ubuntu@<PUBLIC_IP>`
- **Private VMs**: Use proxy through bastion (see deployment output)

### Web Interfaces
- **Home Assistant Dashboard**: `http://<PUBLIC_IP>:8123`
- **System Health**: Check via `ansible-playbook health_check.yml`

## 🔄 State Management

### Terraform State
- Local state file: `terraform/terraform.tfstate`
- For team environments, consider remote state (S3 + DynamoDB)

### Inventory Generation
- Ansible inventory automatically generated from Terraform outputs
- Run `terraform/generate-inventory.sh` to regenerate manually

## 🐛 Troubleshooting

### Common Issues

1. **"Inconsistent dependency lock file" Error**
   ```bash
   # Run this if you get provider dependency errors:
   cd terraform
   terraform init
   cd ..
   # Then retry ./deploy.sh
   ```

2. **"Secret already scheduled for deletion" Error**
   ```bash
   # If you get AWS Secrets Manager deletion conflicts:
   # Option 1: Use teardown script with force deletion (recommended for dev)
   ./teardown.sh
   # Then choose option 2 when prompted for secret deletion
   
   # Option 2: Manual force deletion
   aws secretsmanager delete-secret --secret-id "plant-monitoring-dev/mongodb/credentials" --force-delete-without-recovery
   aws secretsmanager delete-secret --secret-id "plant-monitoring-dev/homeassistant/credentials" --force-delete-without-recovery
   aws secretsmanager delete-secret --secret-id "plant-monitoring-dev/application/config" --force-delete-without-recovery
   ```

2. **SSH Connection Failed**
   ```bash
   # Check security groups and instance state
   aws ec2 describe-instances --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value[],State.Name,PublicIpAddress]'
   ```

3. **Terraform Apply Failed**
   ```bash
   # Check AWS credentials and permissions
   aws sts get-caller-identity
   ```

4. **Ansible Playbook Failed**
   ```bash
   # Test connectivity
   ansible all -i application-deployment/inventory.ini -m ping
   ```

### Useful Commands

```bash
# Check infrastructure status
cd terraform && terraform show

# View all outputs
cd terraform && terraform output

# Test Ansible connectivity
cd application-deployment && ansible all -i inventory.ini -m ping

# View generated inventory
cat application-deployment/inventory.ini
```

## 🆚 Why Terraform + Ansible?

### Previous Issues with Ansible-only IaC
- Variable persistence across playbook runs
- Complex dependency management
- Limited state tracking
- Resource drift detection

### Current Benefits
- **Terraform**: Declarative infrastructure, state management, dependency resolution
- **Ansible**: Powerful configuration management, application deployment
- **Clear separation**: Infrastructure vs Configuration concerns
- **Reproducible**: Consistent deployments with proper state tracking

## 📚 Additional Resources

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [AWS EC2 User Guide](https://docs.aws.amazon.com/ec2/)
- [Docker Compose Reference](https://docs.docker.com/compose/)

## 🤝 Contributing

1. Make infrastructure changes in `terraform/`
2. Test with `terraform plan`
3. Make application changes in `application-deployment/`
4. Test with individual playbooks before full deployment
5. Update documentation as needed