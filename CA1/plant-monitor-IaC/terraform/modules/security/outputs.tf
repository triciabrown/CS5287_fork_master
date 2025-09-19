# Security Module Outputs

output "kafka_sg_id" {
  description = "ID of the Kafka security group"
  value       = aws_security_group.kafka.id
}

output "mongodb_sg_id" {
  description = "ID of the MongoDB security group"
  value       = aws_security_group.mongodb.id
}

output "processor_sg_id" {
  description = "ID of the Processor security group"
  value       = aws_security_group.processor.id
}

output "homeassistant_sg_id" {
  description = "ID of the Home Assistant security group"
  value       = aws_security_group.homeassistant.id
}

output "security_group_ids" {
  description = "Map of all security group IDs"
  value = {
    kafka        = aws_security_group.kafka.id
    mongodb      = aws_security_group.mongodb.id
    processor    = aws_security_group.processor.id
    homeassistant = aws_security_group.homeassistant.id
  }
}