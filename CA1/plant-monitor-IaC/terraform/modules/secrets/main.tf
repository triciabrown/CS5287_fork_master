# Secrets Module - AWS Secrets Manager Integration
# Manages all sensitive information securely for the plant monitoring system

# Generate secure random passwords (avoiding Docker Compose variable substitution chars)
resource "random_password" "mongodb_root_password" {
  length  = 32
  special = true
  # Exclude characters that conflict with Docker Compose variable substitution
  override_special = "!@#%^&*()_+-={}|:<>?~"
}

resource "random_password" "mongodb_app_password" {
  length  = 32
  special = true
  # Exclude characters that conflict with Docker Compose variable substitution
  override_special = "!@#%^&*()_+-={}|:<>?~"
}

resource "random_password" "homeassistant_password" {
  length  = 16
  special = false  # Home Assistant passwords work better without special chars
}

# MongoDB Credentials Secret
resource "aws_secretsmanager_secret" "mongodb_credentials" {
  name                    = "${var.project_name}-${var.environment}/mongodb/credentials"
  description             = "MongoDB root and application user credentials for plant monitoring system"
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name        = "${var.project_name}-mongodb-credentials"
    Service     = "mongodb"
    SecretType  = "database-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "mongodb_credentials" {
  secret_id = aws_secretsmanager_secret.mongodb_credentials.id
  secret_string = jsonencode({
    root_username    = "admin"
    root_password    = random_password.mongodb_root_password.result
    app_username     = "plant_monitor"
    app_password     = random_password.mongodb_app_password.result
    database_name    = "plant_monitoring"
    connection_string = "mongodb://${urlencode("plant_monitor")}:${urlencode(random_password.mongodb_app_password.result)}@{MONGODB_HOST}:27017/plant_monitoring"
  })
}

# Home Assistant Credentials Secret
resource "aws_secretsmanager_secret" "homeassistant_credentials" {
  name                    = "${var.project_name}-${var.environment}/homeassistant/credentials"
  description             = "Home Assistant login credentials and MQTT settings"
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name        = "${var.project_name}-homeassistant-credentials"
    Service     = "homeassistant"
    SecretType  = "application-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "homeassistant_credentials" {
  secret_id = aws_secretsmanager_secret.homeassistant_credentials.id
  secret_string = jsonencode({
    admin_username = "admin"
    admin_password = random_password.homeassistant_password.result
    mqtt_username  = "plant_monitor"
    mqtt_password  = random_password.homeassistant_password.result
  })
}

# Application Configuration Secret
resource "aws_secretsmanager_secret" "application_config" {
  name                    = "${var.project_name}-${var.environment}/application/config"
  description             = "Application configuration and API keys"
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name        = "${var.project_name}-application-config"
    Service     = "processor"
    SecretType  = "application-config"
  })
}

resource "aws_secretsmanager_secret_version" "application_config" {
  secret_id = aws_secretsmanager_secret.application_config.id
  secret_string = jsonencode({
    kafka_topics = {
      plant_sensors = "plant-sensors"
      plant_alerts  = "plant-alerts"
    }
    processor_config = {
      check_interval_seconds = 300
      alert_threshold_hours  = 24
    }
    mqtt_config = {
      discovery_prefix = "homeassistant"
      state_topic_prefix = "plant_monitor"
    }
  })
}