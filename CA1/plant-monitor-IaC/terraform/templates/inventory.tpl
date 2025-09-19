# Plant Monitoring System Infrastructure Inventory
# Generated automatically by Terraform

[kafka_vm]
vm-1-kafka ansible_host=${kafka_private_ip}

[mongodb_vm]
vm-2-mongodb ansible_host=${mongodb_private_ip}

[processor_vm]
vm-3-processor ansible_host=${processor_private_ip}

[homeassistant_vm]
vm-4-homeassistant ansible_host=${homeassistant_public_ip}

# Legacy group names for backwards compatibility
[kafka]
vm-1-kafka ansible_host=${kafka_private_ip}

[mongodb]
vm-2-mongodb ansible_host=${mongodb_private_ip}

[processor]
vm-3-processor ansible_host=${processor_private_ip}

[homeassistant]
vm-4-homeassistant ansible_host=${homeassistant_public_ip}

# Private subnet VMs (accessible via bastion host)
[private_vms]
vm-1-kafka ansible_host=${kafka_private_ip}
vm-2-mongodb ansible_host=${mongodb_private_ip}
vm-3-processor ansible_host=${processor_private_ip}

# Public subnet VMs (direct access)
[public_vms]
vm-4-homeassistant ansible_host=${homeassistant_public_ip}

# SSH configuration for private VMs (through bastion)
[private_vms:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -i ~/.ssh/plant-monitoring-key.pem -W %h:%p -q ubuntu@${homeassistant_public_ip}"'

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/plant-monitoring-key.pem
ansible_ssh_host_key_checking=False
ansible_ssh_port=22

# AWS Secrets Manager secret names (populated by Terraform)
mongodb_credentials_secret=${mongodb_secret_name}
homeassistant_credentials_secret=${homeassistant_secret_name}
application_config_secret=${application_config_secret_name}