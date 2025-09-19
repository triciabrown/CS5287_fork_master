# Plant Monitoring System - Terraform Infrastructure
# This configuration provisions AWS infrastructure for the IoT plant monitoring system

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure AWS provider
provider "aws" {
  region = var.aws_region
}

# Local values for consistent naming and tagging
locals {
  project_name = "plant-monitoring"
  environment  = var.environment
  
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}

# Networking module - VPC, subnets, gateways, routing
module "networking" {
  source = "./modules/networking"
  
  project_name = local.project_name
  environment  = local.environment
  aws_region   = var.aws_region
  
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidr  = var.private_subnet_cidr
  availability_zone    = var.availability_zone
  
  tags = local.common_tags
}

# Security module - Security groups and rules
module "security" {
  source = "./modules/security"
  
  project_name = local.project_name
  environment  = local.environment
  
  vpc_id   = module.networking.vpc_id
  vpc_cidr = var.vpc_cidr
  
  tags = local.common_tags
}

# Secrets module - AWS Secrets Manager for secure credential storage
module "secrets" {
  source = "./modules/secrets"
  
  project_name = local.project_name
  environment  = local.environment
  
  tags = local.common_tags
}

# Compute module - EC2 instances, EIPs
module "compute" {
  source = "./modules/compute"
  
  project_name = local.project_name
  environment  = local.environment
  aws_region   = var.aws_region
  
  # Networking inputs
  vpc_id            = module.networking.vpc_id
  public_subnet_id  = module.networking.public_subnet_id
  private_subnet_id = module.networking.private_subnet_id
  
  # Security inputs  
  kafka_sg_id        = module.security.kafka_sg_id
  mongodb_sg_id      = module.security.mongodb_sg_id
  processor_sg_id    = module.security.processor_sg_id
  homeassistant_sg_id = module.security.homeassistant_sg_id
  
  # Instance configuration
  ami_id        = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  
  tags = local.common_tags
}