# Compute Module - EC2 Instances and Elastic IPs
# Creates all compute resources for the plant monitoring system

# Kafka Instance (VM-1) - Private Subnet
resource "aws_instance" "kafka" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.kafka_sg_id]

  tags = merge(var.tags, {
    Name = "VM-1-Kafka"
    Role = "kafka"
  })
}

# MongoDB Instance (VM-2) - Private Subnet
resource "aws_instance" "mongodb" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.mongodb_sg_id]

  tags = merge(var.tags, {
    Name = "VM-2-MongoDB"
    Role = "mongodb"
  })
}

# Processor Instance (VM-3) - Private Subnet
resource "aws_instance" "processor" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.processor_sg_id]

  tags = merge(var.tags, {
    Name = "VM-3-Processor"
    Role = "processor"
  })
}

# Home Assistant Instance (VM-4) - Public Subnet
resource "aws_instance" "homeassistant" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.homeassistant_sg_id]
  associate_public_ip_address = true

  tags = merge(var.tags, {
    Name = "VM-4-HomeAssistant"
    Role = "homeassistant"
  })
}

# Elastic IP for Home Assistant (idempotent with tags)
resource "aws_eip" "homeassistant" {
  instance = aws_instance.homeassistant.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-ha-eip"
  })

  depends_on = [aws_instance.homeassistant]
}