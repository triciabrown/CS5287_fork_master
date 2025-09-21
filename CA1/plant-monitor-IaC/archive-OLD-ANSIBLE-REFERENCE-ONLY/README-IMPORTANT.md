# ⚠️ ARCHIVE - REFERENCE ONLY ⚠️

## IMPORTANT: This directory is for reference purposes only!

### DO NOT EXECUTE THESE FILES

This directory contains the **old Ansible-based infrastructure deployment approach** that has been **replaced by Terraform**.

### Current Deployment Method (USE THIS):
- **Infrastructure**: `terraform/` directory 
- **Applications**: `application-deployment/` directory

### Why This Archive Exists:
- Historical reference for the original deployment approach
- Learning material to understand the evolution of the project
- Backup of the original implementation

### Known Issues with These Files:
- `security.yml` conflicts with current deployment
- `deploy.sh` and `aws_infra.yml` attempt to create infrastructure that Terraform now manages
- These scripts expect different inventory formats and variable structures

### Migration Summary:
- **Old**: Pure Ansible for both infrastructure and applications
- **New**: Terraform for infrastructure + Ansible for applications only

---
**Last Updated**: September 2025  
**Status**: ARCHIVED - DO NOT USE