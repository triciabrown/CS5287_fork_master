# Free Tier Kubernetes Cluster Infrastructure

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
  default     = "us-east-2"  # Ohio region (generally cheaper)
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

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

# Use most recent Ubuntu 22.04 LTS (Jammy) server AMI
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

# Get current user's IP for SSH access
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

# VPC Configuration
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-igw"
  })
}

# Public Subnet
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

# Route Table for Public Subnet
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

# Security Group for Control Plane
resource "aws_security_group" "k8s_control_plane" {
  name        = "${var.cluster_name}-control-plane"
  description = "Security group for Kubernetes control plane"
  vpc_id      = aws_vpc.k8s_vpc.id

  # SSH Access (restricted to your IP)
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  # Kubernetes API Server
  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", local.my_ip]  # VPC + your IP for kubectl access
  }

  # etcd server client API
  ingress {
    description = "etcd"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Kubelet API
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # kube-scheduler
  ingress {
    description = "kube-scheduler"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # kube-controller-manager
  ingress {
    description = "kube-controller-manager"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Flannel VXLAN
  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow all outbound
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

# Security Group for Worker Nodes
resource "aws_security_group" "k8s_workers" {
  name        = "${var.cluster_name}-workers"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = aws_vpc.k8s_vpc.id

  # SSH Access (restricted to your IP)
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  # Kubelet API
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # NodePort Services (if needed)
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Flannel VXLAN
  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow all outbound
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

# IAM Role for EC2 instances (needed for EBS CSI driver)
resource "aws_iam_role" "k8s_node_role" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policies for Kubernetes nodes
resource "aws_iam_role_policy_attachment" "k8s_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.k8s_node_role.name
}

resource "aws_iam_role_policy_attachment" "k8s_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.k8s_node_role.name
}

resource "aws_iam_role_policy_attachment" "k8s_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.k8s_node_role.name
}

# Additional IAM policy for EBS CSI driver
resource "aws_iam_role_policy" "k8s_ebs_csi_policy" {
  name = "${var.cluster_name}-ebs-csi-policy"
  role = aws_iam_role.k8s_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteSnapshot",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:DetachVolume",
          "ec2:ModifyVolume"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "k8s_node_profile" {
  name = "${var.cluster_name}-node-profile"
  role = aws_iam_role.k8s_node_role.name

  tags = local.common_tags
}

# Key Pair
resource "aws_key_pair" "k8s_key" {
  key_name   = "${var.cluster_name}-key"
  public_key = file(var.ssh_public_key_path)

  tags = local.common_tags
}

# Control Plane Instance (t2.micro - FREE TIER)
resource "aws_instance" "k8s_control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"  # FREE TIER
  key_name               = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_control_plane.id]
  subnet_id              = aws_subnet.k8s_public.id
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name

  root_block_device {
    volume_size = 30  # FREE TIER (up to 30GB)
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

  lifecycle {
    create_before_destroy = false
  }
}

# Worker Node Instances (t2.micro - FREE TIER)
resource "aws_instance" "k8s_workers" {
  count                  = 4  # Increased from 2 to 4 for better resource distribution
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"  # FREE TIER
  key_name               = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_workers.id]
  subnet_id              = aws_subnet.k8s_public.id
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name

  root_block_device {
    volume_size = 30  # FREE TIER (up to 30GB)
    volume_type = "gp2"
    encrypted   = true
    
    tags = merge(local.common_tags, {
      Name = "${var.cluster_name}-worker-${count.index + 1}-root"
    })
  }

  user_data = base64encode(templatefile("${path.module}/scripts/worker-init.sh", {
    cluster_name = var.cluster_name
    control_plane_ip = aws_instance.k8s_control_plane.private_ip
  }))

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-worker-${count.index + 1}"
    Role = "worker"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  lifecycle {
    create_before_destroy = false
  }
}

# Outputs
output "cluster_info" {
  value = {
    cluster_name         = var.cluster_name
    region              = var.aws_region
    vpc_id              = aws_vpc.k8s_vpc.id
    subnet_id           = aws_subnet.k8s_public.id
  }
}

output "control_plane_ip" {
  description = "Public IP of the control plane node"
  value       = aws_instance.k8s_control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP of the control plane node"
  value       = aws_instance.k8s_control_plane.private_ip
}

output "worker_ips" {
  description = "Public IPs of worker nodes"
  value       = aws_instance.k8s_workers[*].public_ip
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = aws_instance.k8s_workers[*].private_ip
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to each node"
  value = {
    control_plane = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_control_plane.public_ip}"
    worker_1     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[0].public_ip}"
    worker_2     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[1].public_ip}"
    worker_3     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[2].public_ip}"
    worker_4     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[3].public_ip}"
  }
}

output "cost_estimate" {
  description = "Monthly cost estimate"
  value = {
    instances = "5 x t2.micro = $0/month (FREE TIER - 750 hours/month allows ~31 instances)"
    storage   = "5 x 30GB EBS gp2 = $0/month (FREE TIER - 30GB free per month)"
    network   = "Data transfer within free tier limits"
    total     = "$0/month (100% FREE!)"
    note      = "Free tier allows 750 EC2 hours/month - we use only 3,600 hours/month (5*24*30)"
  }
}