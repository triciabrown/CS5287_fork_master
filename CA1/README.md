# CA1 – Infrastructure as Code (IaC)

This assignment recreates the IoT pipeline from CA0 using automated deployment tools (Ansible). All infrastructure setup, configuration, and service deployment should be defined as code and documented here.

## Getting Started

- **Reference Architecture:** Same as CA0 (Producers → Kafka → Processor → DB/Analytics)
- **Cloud Provider:** AWS (same as CA0)
- **Automation Tool:** Ansible

## Ansible Installation & Windows Troubleshooting

### Common Issues on Windows

1. **Locale Encoding Error**
   - When running `ansible-galaxy collection install amazon.aws`, you may see:
     > ERROR: Ansible requires the locale encoding to be UTF-8; Detected 1252.
   - Setting the default encoding environment variable in your session may not resolve this.

2. **PATH Issues**
   - After installing Ansible with pip, you may need to add the user install location to your PATH:
     > C:\Users\trici\AppData\Roaming\Python\Python312\Scripts

3. **Windows Compatibility**
   - Ansible is not natively supported on Windows for control node usage. Many modules and collections (including `amazon.aws`) require a Linux environment.

### Recommended Solution: Use WSL (Windows Subsystem for Linux)

- Download and install WSL from the Microsoft Store or via PowerShell.
- Install a Linux distribution (e.g., Ubuntu) in WSL.
- Use `pipx` to install Ansible:
  ```bash
  pipx install ansible
  pipx install ansible-core
  ```
  - The initial install may only create the `ansible-community` command. You must also install `ansible-core` to get the full suite of Ansible commands.
- After this, you can successfully run:
  ```bash
  ansible-galaxy collection install amazon.aws
  ```

### Summary
- Ansible is best run from a Linux environment (WSL recommended for Windows users).
- If you encounter locale or compatibility errors, switch to WSL and use `pipx` for installation.
- Document any additional troubleshooting steps in this README as you progress.


## Mapping Manual CA0 Steps to Ansible Automation (CA1)

This section explains how each major manual step from CA0 is now automated in CA1 using Ansible, and highlights any changes required for automation:

| Manual Step (CA0) | Ansible Automation (CA1) | Notes/Changes |
|-------------------|-------------------------|---------------|
| Manually create VPC, subnets, gateways in AWS Console | Automated with `amazon.aws.ec2_vpc_net`, `ec2_vpc_subnet`, `ec2_vpc_igw`, `ec2_vpc_nat_gateway` tasks | CIDR blocks, subnet sizes, and gateway setup are now reproducible and version-controlled |
| Manually configure route tables | Automated with `ec2_vpc_route_table` and `ec2_vpc_route_table_route` tasks | Route associations and NAT/IGW routing are explicit in code |
| Manually create security groups and rules | Automated with `ec2_security_group` tasks | Rules for each service are defined in YAML, using group references for internal access |
| Launch EC2 instances via AWS Console | Automated with `ec2_instance` tasks | Instance specs, subnets, and security groups are parameterized |
| Allocate Elastic IP for public VM | Automated with `ec2_eip` task | Elastic IP is assigned to Home Assistant VM automatically |
| Manually record and update IP addresses | Automated output via Ansible `debug` task | Instance details are shown after provisioning |
| SSH key management | Still manual (reference key in playbook/inventory) | Key pair name must match AWS and local SSH key |
| Docker installation and service deployment | Will be automated in subsequent Ansible roles/playbooks | Manual install steps from CA0 will be translated to Ansible tasks |

**Key Changes for Automation:**
- All infrastructure is now defined as code and can be recreated or updated by running the playbook.
- Security group rules use group references for tighter access control.
- Elastic IP assignment and NAT gateway setup are explicit and repeatable.
- Manual steps for software installation will be replaced by Ansible roles for each service (next steps).

Document any additional changes or lessons learned as you progress through the automation process.


## Directory Structure
```
CA1/
  README.md
  ansible/
   inventory.ini
   playbook.yml
   aws_infra.yml
   docker-compose/
    kafka.yml
    mongodb.yml
    processor.yml
    homeassistant.yml
   mongodb_init-db.js
   roles/
    common/
    kafka/
    mongodb/
    processor/
    homeassistant/
```

### Docker Compose Files
- All service deployment files (`kafka.yml`, `mongodb.yml`, `processor.yml`, `homeassistant.yml`) are now located in `ansible/docker-compose/` for clarity and reproducibility.
- The MongoDB initialization script is in `ansible/mongodb_init-db.js`.
- Ansible roles reference these files for copy operations, making the automation self-contained.


### AWS Credentials Setup
To run Ansible playbooks that provision AWS resources, you must provide AWS credentials. Recommended methods:

1. **Environment Variables** (temporary, for your shell session):
  ```powershell
  $env:AWS_ACCESS_KEY_ID="your-access-key-id"
  $env:AWS_SECRET_ACCESS_KEY="your-secret-access-key"
  $env:AWS_DEFAULT_REGION="us-east-2"
  ```

2. **AWS CLI Configuration File** (persistent):
  Run `aws configure` in your shell and follow the prompts. This creates a file at `~/.aws/credentials`.

3. **IAM Role (for EC2/WSL control node)**:
  If running Ansible from an EC2 instance, attach an IAM role with required permissions. Ansible will use the instance profile automatically.

**Troubleshooting Note:**
- On WSL/Ubuntu, the `awscli` package may not be available in the default repositories. If you see "Package 'awscli' has no installation candidate", install AWS CLI using pipx:
  ```bash
  pipx install awscli
  ```
  This will provide the `aws` command for configuring credentials and using AWS CLI features.

**Never hardcode credentials in playbooks or source files.**

### Testing Your Ansible Automation
1. Ensure your AWS credentials are set up and valid.
2. Run the infrastructure playbook to provision VPC, subnets, security groups, and EC2 instances:
  ```bash
  ansible-playbook ansible/aws_infra.yml
  ```
3. Update `inventory.ini` with the public/private IPs of your new instances (output by the playbook).
4. Run the main playbook to install Docker and deploy services:
  ```bash
  ansible-playbook ansible/playbook.yml -i ansible/inventory.ini
  ```
5. Verify service status using Ansible output and by connecting to your VMs.

Document any issues or troubleshooting steps in this README as you test and refine your automation.

## Links
- [CA0 Submission](../CA0/README.md)
- [Assignment Description](../../doc/assignments/README.md)

---

Add documentation, diagrams, and links to your Ansible files below as you build out your solution.
