# Archived Ansible Infrastructure-as-Code Playbooks

This directory contains the original Ansible playbooks that were used for AWS infrastructure provisioning before migrating to Terraform. These files are preserved for reference and historical purposes.

## Background

During the initial development phase, Ansible was used for both infrastructure provisioning and application deployment. However, we encountered several challenges:

1. **Variable Persistence Issues**: Variables registered in one playbook were not available in subsequent playbook runs
2. **Dependency Management**: Complex dependencies between resources were difficult to manage across separate playbook files
3. **State Management**: Ansible lacks the state management capabilities that Terraform provides
4. **Resource Tracking**: Difficult to track and manage infrastructure changes over time

## Migration to Terraform

The infrastructure provisioning has been migrated to Terraform while keeping Ansible for its strengths:
- **Terraform**: Infrastructure provisioning (VPC, subnets, security groups, EC2 instances, etc.)
- **Ansible**: Configuration management and application deployment

## Archived Files

### Infrastructure Playbooks
- `networking.yml` - VPC, subnets, IGW, route tables
- `security.yml` - Security groups and rules
- `compute.yml` - EC2 instances  
- `network_endpoints.yml` - EIPs, NAT Gateway, private routing

### Teardown Playbooks
- `aws_teardown.yml` - Master teardown orchestration
- `teardown_*.yml` - Modular teardown for specific resource types

### Deployment Scripts
- `deploy.sh` - Original deployment orchestration script
- `check_health.sh` - Health checking utilities
- `make_executable.sh` - Permission setup script

### Debug Utilities
- `debug_*.yml` - Debugging playbooks for troubleshooting

## Key Lessons Learned

1. **Use the right tool for the job**: Terraform for infrastructure, Ansible for configuration
2. **Variable scoping**: Cross-playbook variable sharing is complex in Ansible
3. **Idempotency**: Some AWS resources (like EIPs) require careful handling for proper idempotency
4. **Resource ordering**: Dependencies matter - security groups before VPC deletion, etc.

## Working Solutions Preserved

Despite the challenges, several solutions in these files work correctly:
- VPC CIDR-based resource lookups
- Idempotent EIP allocation with tags
- Security group cross-references
- Modular teardown with proper dependency ordering

These patterns may be useful for future Ansible work in other contexts.