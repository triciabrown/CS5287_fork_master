---
marp: true
theme: default
paginate: true
size: 16:9
title: Primer on Infrastructure as Code (IaC)
description: Concepts, benefits, and popular tools
---

# What Is Infrastructure as Code?

Video: [https://youtu.be/iJMPeQkvHpc](https://youtu.be/iJMPeQkvHpc)

- Treat infrastructure (VMs, networks, storage) as versioned code
- Declarative or imperative definitions stored in text files
- Automated provisioning, configuration, and teardown
- Benefits: repeatability, consistency, auditability, collaboration

---

## Why IaC Matters

- **Idempotency**: safe re-runs produce the same state
- **Version Control**: diff, review, and rollback infrastructure changes
- **Collaboration**: share modules, enforce standards via code
- **Automation**: integrate into CI/CD pipelines for rapid deployments
- **Documentation**: code serves as living documentation of topology

---

## Declarative vs. Imperative IaC

- **Declarative**
    - Describe *what* the final state should be
    - Tool figures out *how* to reach that state
    - Examples: Terraform, CloudFormation, ARM/Bicep

- **Imperative**
    - Specify *step-by-step* commands to run
    - Greater control over execution flow
    - Examples: Ansible, Chef, Puppet

---

## Categories of IaC Tools

### **Provisioners**

- Create cloud resources: VMs, networks, load balancers
- Terraform, Pulumi, Crossplane

### **Configuration Management**

- Install software & configure OS/services on servers
- Ansible, Chef, Puppet, SaltStack

---

## Categories of IaC Tools (cont.)

### **Orchestration & Templating**

- Deploy multi-tier applications via templates
- AWS CloudFormation, Azure ARM/Bicep, Google Deployment Manager

### **Containers & Kubernetes Operators**

- Manage infra via Kubernetes CRDs and controllers
- Helm, Flux, ArgoCD, Terraform Operator

---

## Popular IaC Tools at a Glance

* **Terraform**  
  * HashiCorp tool, declarative HCL, multi-cloud support, large module registry
* **Pulumi**  
  * Code-first (JavaScript, Python, Go, .NET), multi-cloud, state management
* **Ansible**  
  * Agentless, YAML playbooks, imperative or idempotent tasks, extensive modules
* **Chef & Puppet**  
  * Ruby-based DSL, client/server model, desired-state configs
* **CloudFormation / ARM / Deployment Manager**  
  * Native to AWS, Azure, GCP; deep integration, drift detection
* **Crossplane**  
  * Kubernetes-native control plane for provisioning cloud resources

---

## IaC Workflow

1. Write code (modules, playbooks, templates)
2. Store in Git; peer review changes via pull requests
3. Execute plan/preview (e.g., `terraform plan`)
4. Apply changes (`terraform apply`, `ansible-playbook`, etc.)
5. Monitor drift; update code and re-apply as needed
6. Destroy resources when no longer needed

---

## Key Takeaways

- IaC shifts infra from manual to code-driven
- Choose declarative vs. imperative based on use case
- Leverage version control, modularity, and CI/CD integration
- Select tools that fit your cloud environment and team skills