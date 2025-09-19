# Secrets Module Outputs

# Secret ARNs for referencing in other resources
output "mongodb_credentials_arn" {
  description = "ARN of the MongoDB credentials secret"
  value       = aws_secretsmanager_secret.mongodb_credentials.arn
}

output "homeassistant_credentials_arn" {
  description = "ARN of the Home Assistant credentials secret"
  value       = aws_secretsmanager_secret.homeassistant_credentials.arn
}

output "application_config_arn" {
  description = "ARN of the application configuration secret"
  value       = aws_secretsmanager_secret.application_config.arn
}

# Secret names for Ansible lookup
output "secret_names" {
  description = "Map of secret names for Ansible integration"
  value = {
    mongodb_credentials      = aws_secretsmanager_secret.mongodb_credentials.name
    homeassistant_credentials = aws_secretsmanager_secret.homeassistant_credentials.name
    application_config       = aws_secretsmanager_secret.application_config.name
  }
}

# Connection strings and config for outputs
output "mongodb_connection_template" {
  description = "MongoDB connection string template"
  value       = "mongodb://plant_monitor:**SECRET**@{MONGODB_HOST}:27017/plant_monitoring"
  sensitive   = false  # This is just a template, not actual credentials
}

# Generated passwords (for debugging/verification only - use secrets manager in production)
output "password_strength_info" {
  description = "Information about generated password complexity"
  value = {
    mongodb_password_length = length(random_password.mongodb_root_password.result)
    ha_password_length      = length(random_password.homeassistant_password.result)
  }
}