# Security Module - Security Groups and Rules
# Creates all security groups for the plant monitoring system

# Kafka Security Group (VM-1)
resource "aws_security_group" "kafka" {
  name        = "SG-Kafka"
  description = "Kafka security group - VM-1 message broker for plant sensor data"
  vpc_id      = var.vpc_id

  # SSH access for administrative tasks
  ingress {
    description = "SSH access for administrative tasks"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kafka broker access from VPC (processor and other services)
  ingress {
    description = "Kafka broker access from VPC (processor and other services)"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Default outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-sg-kafka"
  })
}

# MongoDB Security Group (VM-2)
resource "aws_security_group" "mongodb" {
  name        = "SG-MongoDB"
  description = "MongoDB security group - VM-2 database with authentication for plant sensor data storage"
  vpc_id      = var.vpc_id

  # SSH access for administrative tasks and database management
  ingress {
    description = "SSH access for administrative tasks and database management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Default outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-sg-mongodb"
  })
}

# Processor Security Group (VM-3)
resource "aws_security_group" "processor" {
  name        = "SG-Processor"
  description = "Processor security group - VM-3 plant care processor with automatic MQTT discovery"
  vpc_id      = var.vpc_id

  # SSH access for administrative tasks and application deployment
  ingress {
    description = "SSH access for administrative tasks and application deployment"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP outbound for package downloads and external API calls
  ingress {
    description = "HTTP outbound for package downloads and external API calls"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS outbound for package downloads and external API calls
  ingress {
    description = "HTTPS outbound for package downloads and external API calls"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Default outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-sg-processor"
  })
}

# Home Assistant Security Group (VM-4)
resource "aws_security_group" "homeassistant" {
  name        = "SG-HomeAssistant"
  description = "Home Assistant security group - VM-4 dashboard + MQTT broker + plant sensors (public access)"
  vpc_id      = var.vpc_id

  # SSH access for administrative tasks (also serves as bastion host)
  ingress {
    description = "SSH access for administrative tasks (also serves as bastion host for private subnet access)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Home Assistant dashboard public access
  ingress {
    description = "Home Assistant dashboard public access for plant monitoring interface"
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Default outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-sg-homeassistant"
  })
}

# Cross-reference rules that require security group IDs
# MongoDB database access restricted to processor service only
resource "aws_security_group_rule" "mongodb_from_processor" {
  description              = "MongoDB database access restricted to processor service only (database boundary)"
  type                     = "ingress"
  from_port                = 27017
  to_port                  = 27017
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.processor.id
  security_group_id        = aws_security_group.mongodb.id
}

# Processor API access from Home Assistant for plant care recommendations
resource "aws_security_group_rule" "processor_from_homeassistant" {
  description              = "Processor API access from Home Assistant for plant care recommendations"
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.homeassistant.id
  security_group_id        = aws_security_group.processor.id
}



# Home Assistant MQTT broker access from processor
resource "aws_security_group_rule" "homeassistant_from_processor_mqtt" {
  description              = "MQTT broker access from processor service for plant care alerts and sensor data"
  type                     = "ingress"
  from_port                = 1883
  to_port                  = 1883
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.processor.id
  security_group_id        = aws_security_group.homeassistant.id
}

# Home Assistant MQTT broker public access for browser-based MQTT integration
resource "aws_security_group_rule" "homeassistant_mqtt_public" {
  description       = "MQTT broker public access for Home Assistant integration setup from browsers"
  type              = "ingress"
  from_port         = 1883
  to_port           = 1883
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.homeassistant.id
}