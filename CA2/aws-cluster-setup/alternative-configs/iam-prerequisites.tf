# IAM Prerequisites - Run with admin account first
# This file creates IAM resources that require elevated permissions

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# IAM Role for Kubernetes nodes
resource "aws_iam_role" "k8s_node_role" {
  name = "k8s-freetier-node-role"

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

  tags = {
    Environment = "Learning"
    FreeTier    = "true"
    ManagedBy   = "Terraform-IAM-Prerequisites"
    Project     = "PlantMonitoring-CA2"
  }
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

# EBS CSI driver policy
resource "aws_iam_role_policy" "k8s_ebs_csi_policy" {
  name = "k8s-freetier-ebs-csi-policy"
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
  name = "k8s-freetier-node-profile"
  role = aws_iam_role.k8s_node_role.name

  tags = {
    Environment = "Learning"
    FreeTier    = "true"
    ManagedBy   = "Terraform-IAM-Prerequisites"
    Project     = "PlantMonitoring-CA2"
  }
}

# Outputs for main infrastructure
output "node_instance_profile_name" {
  description = "Name of the IAM instance profile for nodes"
  value       = aws_iam_instance_profile.k8s_node_profile.name
}

output "node_role_arn" {
  description = "ARN of the IAM role for nodes"
  value       = aws_iam_role.k8s_node_role.arn
}