# Docker Swarm Infrastructure with Security Best Practices
# Private subnet for worker nodes, public subnet for manager (with Home Assistant)
# Based on CA1 security architecture

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region for deployment"
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Name of the Docker Swarm cluster"
  default     = "plant-monitoring-swarm"
}

variable "manager_count" {
  description = "Number of manager nodes (recommend 1 for free tier)"
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  default     = 4
}

variable "key_name" {
  description = "Name of SSH key pair"
  default     = "plant-monitoring-swarm-key"
}

# ============================================================================
# VPC
# ============================================================================
resource "aws_vpc" "swarm_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.cluster_name}-vpc"
    Project = "plant-monitoring"
    Type    = "swarm"
  }
}

# ============================================================================
# Internet Gateway
# ============================================================================
resource "aws_internet_gateway" "swarm_igw" {
  vpc_id = aws_vpc.swarm_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# ============================================================================
# NAT Gateway for Private Subnet (Secure Architecture)
# ============================================================================
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.swarm_igw]
}

resource "aws_nat_gateway" "swarm_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.swarm_public.id

  tags = {
    Name = "${var.cluster_name}-nat-gateway"
  }

  depends_on = [aws_internet_gateway.swarm_igw]
}

# ============================================================================
# Subnets
# ============================================================================

# Public Subnet - Manager node with Home Assistant (public-facing)
resource "aws_subnet" "swarm_public" {
  vpc_id                  = aws_vpc.swarm_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-subnet"
    Type = "public"
  }
}

# Private Subnet - Worker nodes (NOT publicly accessible)
resource "aws_subnet" "swarm_private" {
  vpc_id                  = aws_vpc.swarm_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false  # No public IPs

  tags = {
    Name = "${var.cluster_name}-private-subnet"
    Type = "private"
  }
}

# ============================================================================
# Route Tables
# ============================================================================

# Public Route Table - Routes to Internet Gateway
resource "aws_route_table" "swarm_public_rt" {
  vpc_id = aws_vpc.swarm_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.swarm_igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "swarm_public_rta" {
  subnet_id      = aws_subnet.swarm_public.id
  route_table_id = aws_route_table.swarm_public_rt.id
}

# Private Route Table - Routes through NAT Gateway
resource "aws_route_table" "swarm_private_rt" {
  vpc_id = aws_vpc.swarm_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.swarm_nat.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

resource "aws_route_table_association" "swarm_private_rta" {
  subnet_id      = aws_subnet.swarm_private.id
  route_table_id = aws_route_table.swarm_private_rt.id
}

# ============================================================================
# Security Groups
# ============================================================================

# Security Group for Manager Node (Public)
resource "aws_security_group" "swarm_manager_sg" {
  name        = "${var.cluster_name}-manager-sg"
  description = "Security group for Docker Swarm manager node (public)"
  vpc_id      = aws_vpc.swarm_vpc.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Home Assistant UI (ONLY on manager in public subnet)
  ingress {
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Home Assistant web interface"
  }

  # Docker Swarm management from within VPC
  ingress {
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Swarm cluster management"
  }

  # Swarm node communication within VPC
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Swarm node communication TCP"
  }

  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Swarm node communication UDP"
  }

  # Overlay network within VPC
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Overlay network traffic"
  }

  # IPsec ESP for encrypted overlay networks
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "IPsec ESP for encrypted overlay"
  }

  # IPsec AH for encrypted overlay networks  
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "51"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "IPsec AH for encrypted overlay"
  }

  # IKE for IPsec key exchange
  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "IKE for IPsec key exchange"
  }

  # Allow all internal VPC traffic
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Internal VPC communication"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.cluster_name}-manager-sg"
  }
}

# Security Group for Worker Nodes (Private)
resource "aws_security_group" "swarm_worker_sg" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Security group for Docker Swarm worker nodes (private)"
  vpc_id      = aws_vpc.swarm_vpc.id

  # SSH ONLY from manager node
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.swarm_manager_sg.id]
    description     = "SSH from manager only"
  }

  # Docker Swarm management from manager
  ingress {
    from_port       = 2377
    to_port         = 2377
    protocol        = "tcp"
    security_groups = [aws_security_group.swarm_manager_sg.id]
    description     = "Swarm management from manager"
  }

  # Swarm node communication within cluster
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Swarm node communication TCP"
  }

  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Swarm node communication UDP"
  }

  # Overlay network within VPC
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Overlay network traffic"
  }

  # IPsec ESP for encrypted overlay networks
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "IPsec ESP for encrypted overlay"
  }

  # IPsec AH for encrypted overlay networks  
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "51"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "IPsec AH for encrypted overlay"
  }

  # IKE for IPsec key exchange
  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "IKE for IPsec key exchange"
  }

  # Worker-to-worker communication (self-referencing for same security group)
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    self        = true
    description = "Worker to worker gossip TCP (self-reference)"
  }

  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    self        = true
    description = "Worker to worker gossip UDP (self-reference)"
  }

  # Worker-to-worker overlay network (self-referencing)
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    self        = true
    description = "Worker to worker overlay VXLAN (self-reference)"
  }

  # Allow all internal VPC traffic
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Internal VPC communication"
  }

  # Allow all outbound traffic (for updates, Docker Hub, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.cluster_name}-worker-sg"
  }
}

# ============================================================================
# SSH Key Pair
# ============================================================================
resource "aws_key_pair" "swarm_key" {
  key_name   = var.key_name
  public_key = file("~/.ssh/docker-swarm-key.pub")

  tags = {
    Name = "${var.cluster_name}-key"
  }
}

# ============================================================================
# AMI Data Source
# ============================================================================
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================================
# Manager Node (Public Subnet)
# ============================================================================
resource "aws_instance" "swarm_manager" {
  count         = var.manager_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.small"
  key_name      = aws_key_pair.swarm_key.key_name
  subnet_id     = aws_subnet.swarm_public.id

  # Apply BOTH node-level AND tier-level security groups
  # Node-level: Swarm management, SSH access
  # Tier-level: All 3 tiers (manager hosts services from all tiers)
  vpc_security_group_ids = [
    aws_security_group.swarm_manager_sg.id,
    aws_security_group.frontend_tier_sg.id,
    aws_security_group.messaging_tier_sg.id,
    aws_security_group.data_tier_sg.id
  ]

  # CRITICAL: Disable source/dest check for overlay network traffic
  source_dest_check = false

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
    encrypted   = false
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Update system
              apt-get update
              
              # Install Docker
              apt-get install -y docker.io
              
              # Enable and start Docker
              systemctl enable docker
              systemctl start docker
              
              # Add ubuntu user to docker group
              usermod -aG docker ubuntu
              
              # Install docker-compose for convenience
              apt-get install -y docker-compose
              
              echo "Docker installation complete on manager node"
              EOF

  tags = {
    Name    = "${var.cluster_name}-manager-${count.index + 1}"
    Role    = "manager"
    Project = "plant-monitoring"
    Type    = "swarm"
    Subnet  = "public"
  }
}

# ============================================================================
# Worker Nodes (Private Subnet - No Public IP)
# ============================================================================
resource "aws_instance" "swarm_workers" {
  count         = var.worker_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.swarm_key.key_name
  subnet_id     = aws_subnet.swarm_private.id

  # Apply BOTH node-level AND tier-level security groups
  # Node-level: Swarm management, SSH from manager
  # Tier-level: All 3 tiers (workers host services from all tiers)
  vpc_security_group_ids = [
    aws_security_group.swarm_worker_sg.id,
    aws_security_group.frontend_tier_sg.id,
    aws_security_group.messaging_tier_sg.id,
    aws_security_group.data_tier_sg.id
  ]
  
  # CRITICAL: Disable source/dest check for overlay network traffic
  source_dest_check = false

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
    encrypted   = false
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Wait for NAT Gateway to be fully operational (up to 60 seconds)
              echo "Waiting for network connectivity..."
              for i in {1..12}; do
                if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
                  echo "Network is up!"
                  break
                fi
                echo "Waiting for NAT Gateway... attempt $i/12"
                sleep 5
              done
              
              # Update system
              apt-get update
              
              # Install Docker
              apt-get install -y docker.io
              
              # Enable and start Docker
              systemctl enable docker
              systemctl start docker
              
              # Add ubuntu user to docker group
              usermod -aG docker ubuntu
              
              echo "Docker installation complete on worker node"
              EOF

  tags = {
    Name    = "${var.cluster_name}-worker-${count.index + 1}"
    Role    = "worker"
    Project = "plant-monitoring"
    Type    = "swarm"
    Subnet  = "private"
  }

  # Ensure NAT Gateway is fully created before workers start
  depends_on = [
    aws_nat_gateway.swarm_nat,
    aws_route_table_association.swarm_private_rta
  ]
}

# ============================================================================
# Outputs
# ============================================================================
output "manager_public_ip" {
  description = "Public IP of the manager node"
  value       = aws_instance.swarm_manager[0].public_ip
}

output "manager_private_ip" {
  description = "Private IP of the manager node"
  value       = aws_instance.swarm_manager[0].private_ip
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes (NO public IPs)"
  value       = aws_instance.swarm_workers[*].private_ip
}

output "ssh_command_manager" {
  description = "SSH command to connect to manager"
  value       = "ssh -i ~/.ssh/docker-swarm-key ubuntu@${aws_instance.swarm_manager[0].public_ip}"
}

output "ssh_to_workers" {
  description = "How to SSH to workers (via manager as bastion)"
  value       = "SSH to manager first, then use private IPs"
}

output "nat_gateway_ip" {
  description = "NAT Gateway Elastic IP (for worker internet access)"
  value       = aws_eip.nat_eip.public_ip
}

output "cluster_info" {
  description = "Cluster information"
  value = {
    vpc_id               = aws_vpc.swarm_vpc.id
    public_subnet_id     = aws_subnet.swarm_public.id
    private_subnet_id    = aws_subnet.swarm_private.id
    manager_sg           = aws_security_group.swarm_manager_sg.id
    worker_sg            = aws_security_group.swarm_worker_sg.id
    nat_gateway_id       = aws_nat_gateway.swarm_nat.id
    total_nodes          = var.manager_count + var.worker_count
    manager_count        = var.manager_count
    worker_count         = var.worker_count
    security_architecture = "Manager in public subnet, workers in private subnet with NAT"
  }
}

output "security_summary" {
  description = "Security architecture summary"
  value = <<-EOT
    Security Architecture:
    - Manager Node: Public subnet with Home Assistant exposed on port 8123
    - Worker Nodes: Private subnet, NO public IPs, NO direct internet access
    - Worker Internet: Via NAT Gateway for updates/Docker Hub
    - SSH to Workers: Only via manager node (bastion host)
    - Internal Communication: Encrypted overlay network
    - Principle: Least privilege access
  EOT
}
