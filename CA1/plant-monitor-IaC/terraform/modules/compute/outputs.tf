# Compute Module Outputs

# Instance IDs
output "kafka_instance_id" {
  description = "ID of the Kafka instance"
  value       = aws_instance.kafka.id
}

output "mongodb_instance_id" {
  description = "ID of the MongoDB instance"
  value       = aws_instance.mongodb.id
}

output "processor_instance_id" {
  description = "ID of the Processor instance"
  value       = aws_instance.processor.id
}

output "homeassistant_instance_id" {
  description = "ID of the Home Assistant instance"
  value       = aws_instance.homeassistant.id
}

# Private IP addresses
output "kafka_private_ip" {
  description = "Private IP address of the Kafka instance"
  value       = aws_instance.kafka.private_ip
}

output "mongodb_private_ip" {
  description = "Private IP address of the MongoDB instance"
  value       = aws_instance.mongodb.private_ip
}

output "processor_private_ip" {
  description = "Private IP address of the Processor instance"
  value       = aws_instance.processor.private_ip
}

output "homeassistant_private_ip" {
  description = "Private IP address of the Home Assistant instance"
  value       = aws_instance.homeassistant.private_ip
}

# Public IP addresses
output "homeassistant_public_ip" {
  description = "Public IP address of the Home Assistant instance (Elastic IP)"
  value       = aws_eip.homeassistant.public_ip
}

# Instance details map
output "instances" {
  description = "Map of all instance details"
  value = {
    kafka = {
      id         = aws_instance.kafka.id
      private_ip = aws_instance.kafka.private_ip
    }
    mongodb = {
      id         = aws_instance.mongodb.id
      private_ip = aws_instance.mongodb.private_ip
    }
    processor = {
      id         = aws_instance.processor.id
      private_ip = aws_instance.processor.private_ip
    }
    homeassistant = {
      id         = aws_instance.homeassistant.id
      private_ip = aws_instance.homeassistant.private_ip
      public_ip  = aws_eip.homeassistant.public_ip
    }
  }
}