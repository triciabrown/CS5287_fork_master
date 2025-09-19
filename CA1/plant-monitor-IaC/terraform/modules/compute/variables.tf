# Compute Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_id" {
  description = "ID of the public subnet"
  type        = string
}

variable "private_subnet_id" {
  description = "ID of the private subnet"
  type        = string
}

variable "kafka_sg_id" {
  description = "ID of the Kafka security group"
  type        = string
}

variable "mongodb_sg_id" {
  description = "ID of the MongoDB security group"
  type        = string
}

variable "processor_sg_id" {
  description = "ID of the Processor security group"
  type        = string
}

variable "homeassistant_sg_id" {
  description = "ID of the Home Assistant security group"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "key_name" {
  description = "Name of the AWS key pair"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}