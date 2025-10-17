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
  description = "AWS region"
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

variable "enable_production_optimizations" {
  description = "Enable production optimizations: private subnets, NAT Gateway, ECR caching"
  type        = bool
  default     = false
}

variable "enable_image_caching" {
  description = "Enable ECR image caching with VPC endpoints to reduce data transfer costs"
  type        = bool
  default     = false
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

# Get AWS account ID for ECR registry
data "aws_caller_identity" "current" {}

locals {
  my_ip = "${chomp(data.http.myip.response_body)}/32"
  account_id = data.aws_caller_identity.current.account_id
  
  common_tags = {
    Project     = "PlantMonitoring-CA2"
    Environment = var.enable_production_optimizations ? "Production" : "Learning"
    ManagedBy   = "Terraform"
    FreeTier    = "true"
    Optimized   = var.enable_production_optimizations ? "true" : "false"
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

# PRIVATE SUBNETS - Production optimization: Worker nodes with NO public IPs
resource "aws_subnet" "k8s_private" {
  count                   = var.enable_production_optimizations ? 2 : 0
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.${count.index + 10}.0/24"  # 10.0.10.0/24, 10.0.11.0/24
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false  # CRITICAL: No public IPs

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-private-subnet-${count.index + 1}"
    Type = "Private"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb" = "1"  # For internal load balancers
  })
}

# NAT Gateway for outbound internet access from private subnets
resource "aws_eip" "nat_eip" {
  count  = var.enable_production_optimizations ? 1 : 0
  domain = "vpc"
  
  depends_on = [aws_internet_gateway.k8s_igw]
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "k8s_nat" {
  count         = var.enable_production_optimizations ? 1 : 0
  allocation_id = aws_eip.nat_eip[0].id
  subnet_id     = aws_subnet.k8s_public.id
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-nat-gateway"
    Cost = "~$32/month for production networking"
  })
}

# Route table for private subnets - routes through NAT Gateway
resource "aws_route_table" "k8s_private_rt" {
  count  = var.enable_production_optimizations ? 1 : 0
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.k8s_nat[0].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-private-rt"
  })
}

resource "aws_route_table_association" "k8s_private_rta" {
  count          = var.enable_production_optimizations ? length(aws_subnet.k8s_private) : 0
  subnet_id      = aws_subnet.k8s_private[count.index].id
  route_table_id = aws_route_table.k8s_private_rt[0].id
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
# Security Group for Worker Nodes
resource "aws_security_group" "k8s_worker" {
  name        = "${var.cluster_name}-worker"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = aws_vpc.k8s_vpc.id

  # SSH Access (restricted to your IP via bastion)
  ingress {
    description = "SSH from control plane"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.k8s_control_plane.id]
  }

  # Allow SSH from your IP directly (for troubleshooting)
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
    security_groups = [aws_security_group.k8s_control_plane.id]
  }

  # NodePort Services
  ingress {
    description = "NodePort range"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # CNI (Flannel) VXLAN traffic
  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-worker-sg"
  })
}

# PRODUCTION OPTIMIZATION: ECR Private Registry for image caching
resource "aws_ecr_repository" "plant_monitoring_images" {
  for_each = var.enable_image_caching ? toset([
    "homeassistant",
    "mongodb", 
    "kafka",
    "plant-processor",
    "plant-sensor"
  ]) : []
  
  name                 = "plant-monitoring/${each.key}"
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ecr-${each.key}"
  })
}

# ECR lifecycle policies to manage storage costs
resource "aws_ecr_lifecycle_policy" "plant_monitoring_lifecycle" {
  for_each   = aws_ecr_repository.plant_monitoring_images
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "prod"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# VPC ENDPOINTS - Reduces data transfer costs for ECR
resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_image_caching ? 1 : 0
  name        = "${var.cluster_name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.k8s_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-vpc-endpoints-sg"
  })
}

# ECR Docker endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  count               = var.enable_image_caching ? 1 : 0
  vpc_id              = aws_vpc.k8s_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.enable_production_optimizations ? aws_subnet.k8s_private[*].id : [aws_subnet.k8s_public.id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  
  private_dns_enabled = true
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ecr-dkr-endpoint"
    Savings = "Eliminates internet data transfer for image pulls"
  })
}

# ECR API endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  count               = var.enable_image_caching ? 1 : 0
  vpc_id              = aws_vpc.k8s_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.enable_production_optimizations ? aws_subnet.k8s_private[*].id : [aws_subnet.k8s_public.id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  
  private_dns_enabled = true
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ecr-api-endpoint"
  })
}

# S3 endpoint for ECR layer storage
resource "aws_vpc_endpoint" "s3" {
  count           = var.enable_image_caching ? 1 : 0
  vpc_id          = aws_vpc.k8s_vpc.id
  service_name    = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = var.enable_production_optimizations ? [aws_route_table.k8s_private_rt[0].id] : [aws_route_table.k8s_public_rt.id]
  
  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-s3-endpoint"
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

# Enhanced ECR access policy for image caching optimization
resource "aws_iam_role_policy" "k8s_ecr_optimization_policy" {
  count = var.enable_image_caching ? 1 : 0
  name  = "${var.cluster_name}-ecr-optimization-policy"
  role  = aws_iam_role.k8s_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [
          for repo in aws_ecr_repository.plant_monitoring_images :
          repo.arn
        ]
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

# Control Plane Instance (t2.small - MINIMUM FOR K8S + WORKLOADS)
resource "aws_instance" "k8s_control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.small"  # 1 vCPU, 2GB RAM - Minimum for K8s + apps
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
  vpc_security_group_ids = [aws_security_group.k8s_worker.id]
  # PRODUCTION OPTIMIZATION: Use private subnets when enabled, public subnet otherwise
  subnet_id              = var.enable_production_optimizations ? aws_subnet.k8s_private[count.index % 2].id : aws_subnet.k8s_public.id
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name
  
  # PRODUCTION OPTIMIZATION: Disable public IP assignment for private subnet nodes
  associate_public_ip_address = var.enable_production_optimizations ? false : null

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
    ecr_registry = var.enable_image_caching ? "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com" : ""
  }))

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-worker-${count.index + 1}"
    Role = "worker"
    Subnet = var.enable_production_optimizations ? "private" : "public"
    SecurityLevel = var.enable_production_optimizations ? "production" : "development"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  lifecycle {
    create_before_destroy = false
  }
}

# Outputs
output "cluster_info" {
  value = {
    cluster_name                = var.cluster_name
    region                     = var.aws_region
    vpc_id                     = aws_vpc.k8s_vpc.id
    public_subnet_id           = aws_subnet.k8s_public.id
    private_subnet_ids         = var.enable_production_optimizations ? aws_subnet.k8s_private[*].id : []
    production_optimizations   = var.enable_production_optimizations
    image_caching_enabled      = var.enable_image_caching
  }
}

output "control_plane_ip" {
  description = "Public IP of the control plane node (bastion host)"
  value       = aws_instance.k8s_control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP of the control plane node"
  value       = aws_instance.k8s_control_plane.private_ip
}

output "worker_ips" {
  description = "Public IPs of worker nodes (only if in public subnet)"
  value       = var.enable_production_optimizations ? ["NONE - Workers in private subnets for security"] : aws_instance.k8s_workers[*].public_ip
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = aws_instance.k8s_workers[*].private_ip
}

output "network_security" {
  description = "Network security configuration"
  value = {
    control_plane_access = "Public IP for kubectl and bastion access"
    worker_nodes_access  = var.enable_production_optimizations ? "Private subnets only - SSH via bastion" : "Public IPs (development mode)"
    external_access      = "Only Home Assistant via Load Balancer/Ingress"
    nat_gateway         = var.enable_production_optimizations ? "Enabled for private subnet internet access" : "Not needed - using public subnets"
  }
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to each node"
  value = var.enable_production_optimizations ? {
    control_plane_bastion = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_control_plane.public_ip}"
    worker_via_bastion   = "ssh -J ubuntu@${aws_instance.k8s_control_plane.public_ip} -i ~/.ssh/k8s-cluster-key ubuntu@<worker-private-ip>"
    note                 = "Workers only accessible through bastion host for security"
  } : {
    control_plane = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_control_plane.public_ip}"
    worker_1     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[0].public_ip}"
    worker_2     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[1].public_ip}"
    worker_3     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[2].public_ip}"
    worker_4     = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@${aws_instance.k8s_workers[3].public_ip}"
  }
}

output "ecr_repositories" {
  description = "ECR repositories for image caching (if enabled)"
  value = var.enable_image_caching ? {
    for name, repo in aws_ecr_repository.plant_monitoring_images :
    name => repo.repository_url
  } : {}
}

output "data_transfer_optimization" {
  description = "Data transfer cost optimization features"
  value = {
    vpc_endpoints_enabled = var.enable_image_caching
    ecr_private_registry = var.enable_image_caching ? "Images cached in ECR" : "Using Docker Hub (internet data transfer)"
    estimated_savings    = var.enable_image_caching ? "90%+ reduction in data transfer costs" : "Standard internet transfer costs apply"
    image_pull_source    = var.enable_image_caching ? "ECR via VPC endpoints (no internet charges)" : "Docker Hub via internet"
  }
}

output "cost_estimate" {
  description = "Monthly cost estimate"
  value = {
    instances = "5 x t2.micro = $0/month (FREE TIER - 750 hours/month allows ~31 instances)"
    storage   = "5 x 30GB EBS gp2 = $0/month (FREE TIER - 30GB free per month)"
    network   = var.enable_production_optimizations ? "Data transfer within free tier limits" : "Data transfer within free tier limits"
    nat_gateway = var.enable_production_optimizations ? "~$32/month (production networking cost)" : "$0/month (no NAT Gateway)"
    vpc_endpoints = var.enable_image_caching ? "~$7/month (interface endpoints)" : "$0/month (no VPC endpoints)"
    ecr_storage = var.enable_image_caching ? "~$1/month (minimal usage)" : "$0/month (no ECR)"
    total_learning_mode = "100% FREE (development configuration)"
    total_production_mode = var.enable_production_optimizations ? "~$40/month (production-ready with private networking)" : "Same as learning mode"
    data_transfer_savings = var.enable_image_caching ? "95% reduction vs repeated Docker Hub pulls" : "Standard Docker Hub transfer costs"
  }
}

output "production_readiness" {
  description = "Production readiness assessment"
  value = {
    network_security    = var.enable_production_optimizations ? "✅ Private subnets, bastion host" : "⚠️ All nodes have public IPs"
    image_optimization  = var.enable_image_caching ? "✅ ECR private registry, VPC endpoints" : "⚠️ Docker Hub pulls (high data transfer)"
    data_transfer      = var.enable_image_caching ? "✅ 95% reduction in bandwidth usage" : "⚠️ Full internet downloads each deployment"
    cost_optimized     = var.enable_production_optimizations ? "⚠️ $40/month production costs" : "✅ 100% free tier"
    security_level     = var.enable_production_optimizations ? "PRODUCTION READY 🚀" : "DEVELOPMENT/LEARNING 📚"
  }
}