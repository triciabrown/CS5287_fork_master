# ============================================================================
# Tier-Based Security Groups for CA3
# Implements defense-in-depth at AWS security group level
# Maps to Docker Swarm overlay networks: frontnet, messagenet, datanet
# ============================================================================

# ============================================================================
# FRONTEND TIER SECURITY GROUP
# Services: Home Assistant, Mosquitto (user-facing frontend)
# Network: frontnet (10.10.1.0/24)
# ============================================================================
resource "aws_security_group" "frontend_tier_sg" {
  name        = "${var.cluster_name}-frontend-tier-sg"
  description = "Security group for frontend tier (Home Assistant, MQTT)"
  vpc_id      = aws_vpc.swarm_vpc.id

  # Home Assistant Web UI - Public Access
  ingress {
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Home Assistant web interface (public)"
  }

  # MQTT - Internal to VPC only
  ingress {
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "MQTT unencrypted (internal only)"
  }

  # MQTT over TLS - Internal to VPC only
  ingress {
    from_port   = 8883
    to_port     = 8883
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "MQTT over TLS (internal only)"
  }

  # Allow all internal VPC communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Internal VPC communication"
  }

  # Allow all outbound to internet (for updates, external APIs)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.cluster_name}-frontend-tier-sg"
    Tier = "frontend"
  }
}

# ============================================================================
# MESSAGING TIER SECURITY GROUP
# Services: Kafka, ZooKeeper, Sensors
# Network: messagenet (10.10.2.0/24)
# ============================================================================
resource "aws_security_group" "messaging_tier_sg" {
  name        = "${var.cluster_name}-messaging-tier-sg"
  description = "Security group for messaging tier (Kafka, ZooKeeper, Sensors)"
  vpc_id      = aws_vpc.swarm_vpc.id

  # Kafka - Internal to VPC only (NO PUBLIC ACCESS)
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Kafka broker (internal only)"
  }

  # ZooKeeper - Internal to VPC only (NO PUBLIC ACCESS)
  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "ZooKeeper (internal only)"
  }

  # ZooKeeper peer communication
  ingress {
    from_port   = 2888
    to_port     = 2888
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "ZooKeeper peer communication"
  }

  # ZooKeeper leader election
  ingress {
    from_port   = 3888
    to_port     = 3888
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "ZooKeeper leader election"
  }

  # Kafka JMX metrics (for monitoring)
  ingress {
    from_port   = 9999
    to_port     = 9999
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Kafka JMX (internal only)"
  }

  # Allow all internal VPC communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Internal VPC communication"
  }

  # Allow all outbound to internet (for updates, external APIs)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.cluster_name}-messaging-tier-sg"
    Tier = "messaging"
  }
}

# ============================================================================
# DATA TIER SECURITY GROUP
# Services: MongoDB, Processor, Observability Stack (Grafana, Prometheus, Loki)
# Network: datanet (10.10.3.0/24)
# ============================================================================
resource "aws_security_group" "data_tier_sg" {
  name        = "${var.cluster_name}-data-tier-sg"
  description = "Security group for data tier (MongoDB, Processor, Observability)"
  vpc_id      = aws_vpc.swarm_vpc.id

  # MongoDB - Internal to VPC only (NO PUBLIC ACCESS)
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "MongoDB (internal only)"
  }

  # Grafana UI - Public Access for Dashboard Viewing
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Grafana dashboard (public)"
  }

  # Prometheus UI - Public Access for Metrics Viewing
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Prometheus UI (public)"
  }

  # Loki - Internal to VPC only (accessed via Grafana)
  ingress {
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Loki log aggregation (internal only)"
  }

  # Prometheus metrics endpoints - Internal to VPC only
  ingress {
    from_port   = 9091
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Application metrics endpoints (internal only)"
  }

  # Kafka Exporter metrics
  ingress {
    from_port   = 9308
    to_port     = 9308
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Kafka Exporter metrics (internal only)"
  }

  # MongoDB Exporter metrics
  ingress {
    from_port   = 9216
    to_port     = 9216
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "MongoDB Exporter metrics (internal only)"
  }

  # Node Exporter metrics
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Node Exporter metrics (internal only)"
  }

  # Allow all internal VPC communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.swarm_vpc.cidr_block]
    description = "Internal VPC communication"
  }

  # Allow all outbound to internet (for updates, external APIs)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.cluster_name}-data-tier-sg"
    Tier = "data"
  }
}

# ============================================================================
# OUTPUTS - Security Group IDs
# ============================================================================
output "frontend_tier_sg_id" {
  description = "Security group ID for frontend tier"
  value       = aws_security_group.frontend_tier_sg.id
}

output "messaging_tier_sg_id" {
  description = "Security group ID for messaging tier"
  value       = aws_security_group.messaging_tier_sg.id
}

output "data_tier_sg_id" {
  description = "Security group ID for data tier"
  value       = aws_security_group.data_tier_sg.id
}
