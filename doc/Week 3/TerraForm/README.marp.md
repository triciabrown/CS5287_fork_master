---
marp: true
theme: default
paginate: true
size: 16:9
title: Terraform Overview
description: Declarative infrastructure provisioning with Terraform
---

# Terraform Overview

Video: [https://youtu.be/KpMgxOFoY0A](https://youtu.be/KpMgxOFoY0A)


HashiCorp Terraform is a leading open-source tool for provisioning, changing, and versioning infrastructure safely and efficiently. It lets you define your data center resources (cloud services, network, DNS, load balancers, etc.) in human-readable configuration files and manages the lifecycle of these resources via a declarative workflow.

---

## 1. Key Concepts

- **Declarative Configuration**  
  You describe *what* you want (e.g., “a VM with 2 vCPU and 4 GB RAM in us-west1”), not *how* to create it. Terraform’s engine computes the necessary actions to achieve that state.

- **Providers & Resources**
    - **Provider**: plugin that knows how to manage a given platform (AWS, Azure, GCP, VMware, Kubernetes, etc.)
    - **Resource**: a concrete infrastructure object (EC2 instance, S3 bucket, VPC, DNS record).

--- 
## 1. Key Concepts (cont.)

- **State Management**  
  Terraform maintains a state file (by default `terraform.tfstate`) that tracks metadata and IDs of created resources, enabling differential updates (planned changes vs. actual).

- **Execution Plans**  
  `terraform plan` compares desired configuration against current state and shows a preview of actions: create, update, or destroy.

- **Graph of Dependencies**  
  Terraform builds a directed acyclic graph of resource dependencies to determine parallelism and ordering of operations.

---

## 2. Configuration Language: HCL

- **HashiCorp Configuration Language (HCL)**
    - Human-friendly syntax with blocks, labels, and arguments
    - Supports interpolation, variables, maps, lists, and conditionals
    - Example snippet:

```textmate
provider "aws" {
      region = var.aws_region
    }

    resource "aws_instance" "web" {
      ami           = data.aws_ami.ubuntu.id
      instance_type = "t3.medium"
      tags = {
        Name = "web-server"
      }
    }
```

---

## 2. Configuration Language: HCL (cont.)

- **Variables & Outputs**
    - **Variables** (`variable "foo" { … }`) allow parameterization
    - **Outputs** (`output "ip" { value = aws_instance.web.public_ip }`) expose attributes for other modules or users

- **Modules**
    - Reusable, composable packages of Terraform code
    - Can be local directories, registry modules, or remote sources (Git, cloud-hosted registry)
    - Promote DRY (Don’t Repeat Yourself) and team collaboration

---

## 3. Workflow

1. **Write Configuration**  
   Define providers, resources, variables, and modules in `.tf` files.

2. **Initialize**  
   `terraform init`
    - Downloads providers and modules
    - Prepares backend for remote state (optional: S3, Terraform Cloud, etc.)

3. **Plan**  
   `terraform plan`
    - Creates an execution plan showing proposed changes
   
---

## 3. Workflow (cont.)

4. **Apply**  
   `terraform apply`
    - Prompts for approval, then executes create/update/destroy actions

5. **Inspect & Update**
    - Modify configuration and repeat plan/apply
    - Terraform determines only the delta changes needed

6. **Destroy**  
   `terraform destroy`
    - Safely tears down all managed resources

---

## 4. Backends & Collaboration

- **Local State vs. Remote Backends**
    - Local: state file on disk (not suited for team use)
    - Remote: S3, Azure Blob, GCS, HashiCorp Terraform Cloud/Enterprise—enable state locking, versioning, and access controls

- **Workspaces**  
  Logical separations of state (e.g., dev, staging, prod) within the same configuration

- **Collaboration Features**
    - State locking to prevent concurrent writes
    - Sentinel policies (Terraform Enterprise) for policy-as-code
    - VCS-driven runs with Terraform Cloud integration

---

## 5. Ecosystem & Extensibility

- **Providers**: hundreds of official/community-maintained providers for cloud platforms, SaaS, DNS, monitoring, and more
- **Provisioners**: execute local or remote scripts (e.g., `remote-exec`, `local-exec`) after resource creation
- **Third-Party Tools**:
    - **Terragrunt**: wrapper for DRY configurations and environment promotion
    - **tfsec**: static analysis for security best practices
    - **terraform-docs**: generate documentation from HCL

---

## 6. Benefits & Use Cases

- **Repeatability & Consistency**  
  Infrastructure definitions are versioned alongside application code.

- **Automation & CI/CD**  
  Integrate Terraform runs into pipelines for fully automated deployments.

- **Auditability & Compliance**  
  Execution plans and state provide an audit trail of who changed what and when.

- **Multi-Cloud & Hybrid Deployments**  
  One consistent toolchain for diversified environments.

---

# Summary

* Infrastructure as Code: Terraform enables declarative infrastructure definition, provisioning, and management across
multiple clouds and services

* Rich Ecosystem: Extensive collection of providers and integrations for diverse infrastructure needs

* Mature State Management: Reliable tracking and management of infrastructure state for consistent deployments

* Straightforward Workflows: Clear, predictable processes for infrastructure lifecycle management

* Industry Standard: De facto tool for multi-cloud infrastructure automation