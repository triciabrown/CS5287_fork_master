# Output values from the infrastructure deployment

# Networking outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.networking.public_subnet_id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.networking.private_subnet_id
}

# Security group outputs
output "security_group_ids" {
  description = "Map of security group IDs"
  value = {
    kafka        = module.security.kafka_sg_id
    mongodb      = module.security.mongodb_sg_id
    processor    = module.security.processor_sg_id
    homeassistant = module.security.homeassistant_sg_id
  }
}

# EC2 instance outputs
output "instance_details" {
  description = "Details of all EC2 instances"
  value = {
    kafka = {
      instance_id  = module.compute.kafka_instance_id
      private_ip   = module.compute.kafka_private_ip
    }
    mongodb = {
      instance_id  = module.compute.mongodb_instance_id
      private_ip   = module.compute.mongodb_private_ip
    }
    processor = {
      instance_id  = module.compute.processor_instance_id
      private_ip   = module.compute.processor_private_ip
    }
    homeassistant = {
      instance_id  = module.compute.homeassistant_instance_id
      private_ip   = module.compute.homeassistant_private_ip
      public_ip    = module.compute.homeassistant_public_ip
    }
  }
}

# Ansible inventory generation
output "ansible_inventory" {
  description = "Generated Ansible inventory content"
  value = templatefile("${path.module}/templates/inventory.tpl", {
    kafka_private_ip             = module.compute.kafka_private_ip
    mongodb_private_ip           = module.compute.mongodb_private_ip
    processor_private_ip         = module.compute.processor_private_ip
    homeassistant_private_ip     = module.compute.homeassistant_private_ip
    homeassistant_public_ip      = module.compute.homeassistant_public_ip
    mongodb_secret_name          = module.secrets.secret_names.mongodb_credentials
    homeassistant_secret_name    = module.secrets.secret_names.homeassistant_credentials
    application_config_secret_name = module.secrets.secret_names.application_config
  })
}

# Secrets management outputs
output "secrets_info" {
  description = "Information about managed secrets (no actual secrets exposed)"
  sensitive   = true
  value = {
    secret_names = module.secrets.secret_names
    mongodb_connection_template = module.secrets.mongodb_connection_template
    password_strength = module.secrets.password_strength_info
  }
}

# Connection info for manual access
output "connection_info" {
  description = "SSH connection information"
  value = {
    bastion_host = {
      public_ip = module.compute.homeassistant_public_ip
      command   = "ssh -i ~/.ssh/plant-monitoring-key.pem ubuntu@${module.compute.homeassistant_public_ip}"
    }
    private_instances = {
      kafka     = "ssh -i ~/.ssh/plant-monitoring-key.pem -o ProxyCommand='ssh -W %h:%p -q ubuntu@${module.compute.homeassistant_public_ip}' ubuntu@${module.compute.kafka_private_ip}"
      mongodb   = "ssh -i ~/.ssh/plant-monitoring-key.pem -o ProxyCommand='ssh -W %h:%p -q ubuntu@${module.compute.homeassistant_public_ip}' ubuntu@${module.compute.mongodb_private_ip}"
      processor = "ssh -i ~/.ssh/plant-monitoring-key.pem -o ProxyCommand='ssh -W %h:%p -q ubuntu@${module.compute.homeassistant_public_ip}' ubuntu@${module.compute.processor_private_ip}"
    }
  }
}