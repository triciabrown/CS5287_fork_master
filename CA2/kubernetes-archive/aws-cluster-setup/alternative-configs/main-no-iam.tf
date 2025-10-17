# Simplified Terraform without IAM resources
# Use this version with limited IAM permissions

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
  description = "AWS region for the cluster"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "plant-monitoring-freetier"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/k8s-cluster-key.pub"
}

# Optional: Use existing IAM instance profile if available
variable "existing_instance_profile" {
  description = "Name of existing IAM instance profile (optional)"
  type        = string
  default     = ""
}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

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

data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  my_ip = "${chomp(data.http.myip.response_body)}/32"
  
  common_tags = {
    Project     = "PlantMonitoring-CA2"
    Environment = "Learning"
    ManagedBy   = "Terraform"
    FreeTier    = "true"
  }
}

# VPC Configuration (same as before)
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id
  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-igw"
  })
}

resource "aws_subnet" "k8s_public" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-public-subnet"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_route_table" "k8s_public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-public-rt"
  })
}

resource "aws_route_table_association" "k8s_public_rta" {
  subnet_id      = aws_subnet.k8s_public.id
  route_table_id = aws_route_table.k8s_public_rt.id
}

# Security Groups (same as before)
resource "aws_security_group" "k8s_control_plane" {
  name        = "${var.cluster_name}-control-plane"
  description = "Security group for Kubernetes control plane"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", local.my_ip]
  }

  ingress {
    description = "etcd"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "kube-scheduler"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "kube-controller-manager"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-control-plane-sg"
  })
}

resource "aws_security_group" "k8s_workers" {
  name        = "${var.cluster_name}-workers"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-workers-sg"
  })
}

# Key Pair
resource "aws_key_pair" "k8s_key" {
  key_name   = "${var.cluster_name}-key"
  public_key = file(var.ssh_public_key_path)
  tags = local.common_tags
}

# EC2 Instances without IAM (can be added later)
resource "aws_instance" "k8s_control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_control_plane.id]
  subnet_id              = aws_subnet.k8s_public.id
  
  # Use existing instance profile if provided
  iam_instance_profile = var.existing_instance_profile != "" ? var.existing_instance_profile : null

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
    encrypted   = true
    tags = merge(local.common_tags, {
      Name = "${var.cluster_name}-control-plane-root"
    })
  }

  user_data = base64encode(templatefile("${path.module}/scripts/control-plane-init.sh", {
    cluster_name = var.cluster_name
  }))

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-control-plane"
    Role = "control-plane"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

resource "aws_instance" "k8s_workers" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_workers.id]
  subnet_id              = aws_subnet.k8s_public.id
  
  # Use existing instance profile if provided
  iam_instance_profile = var.existing_instance_profile != "" ? var.existing_instance_profile : null

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
    encrypted   = true
    tags = merge(local.common_tags, {
      Name = "${var.cluster_name}-worker-${count.index + 1}-root"
    })
  }

  user_data = base64encode(templatefile("${path.module}/scripts/worker-init.sh", {
    cluster_name = var.cluster_name
  }))

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-worker-${count.index + 1}"
    Role = "worker"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# Outputs
output "cluster_info" {
  value = {
    cluster_name = var.cluster_name
    region       = var.aws_region
    vpc_id       = aws_vpc.k8s_vpc.id
    subnet_id    = aws_subnet.k8s_public.id
  }
}

output "control_plane_ip" {
  description = "Public IP of the control plane node"
  value       = aws_instance.k8s_control_plane.public_ip
}

output "worker_ips" {
  description = "Public IPs of worker nodes"
  value       = aws_instance.k8s_workers[*].public_ip
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to each node"
  value = {
    control_plane = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_control_plane.public_ip}"
    worker_1     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[0].public_ip}"
    worker_2     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[1].public_ip}"
  }
}

output "next_steps" {
  description = "Next steps for cluster setup"
  value = {
    manual_iam = "To add IAM roles later: 1) Create roles with admin account, 2) Attach to instances via AWS Console"
    basic_cluster = "This creates a basic cluster. Add IAM roles for EBS storage and container registry access."
    cost = "3 x t2.micro = $0/month (FREE TIER)"
  }
}