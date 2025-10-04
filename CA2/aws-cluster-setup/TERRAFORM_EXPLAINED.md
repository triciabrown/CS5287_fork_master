# How Terraform Deploys Infrastructure

## **The Terraform Workflow Explained**

### **Step 1: `terraform init`**
```bash
terraform init
```

**What it does:**
- Downloads the AWS provider plugin (from `main.tf` provider block)
- Sets up the backend (where Terraform stores state)
- Creates a `.terraform/` directory with plugins
- Initializes the working directory

**Files created:**
```
.terraform/
├── providers/
│   └── registry.terraform.io/hashicorp/aws/5.x.x/
└── terraform.tfstate     # State file (tracks what's deployed)
```

### **Step 2: `terraform plan`**
```bash
terraform plan
```

**What it does:**
- Reads `main.tf` and other `.tf` files
- Compares desired state (your .tf files) vs current state (AWS reality)
- Shows you EXACTLY what will be created/modified/destroyed
- No changes made yet - just a preview

**Example output:**
```
Terraform will perform the following actions:

  # aws_instance.k8s_control_plane will be created
  + resource "aws_instance" "k8s_control_plane" {
      + ami           = "ami-0c02fb55956c7d316"
      + instance_type = "t2.micro"
      + key_name      = "plant-monitoring-freetier-key"
      # ... more details
    }

Plan: 12 to add, 0 to change, 0 to destroy.
```

### **Step 3: `terraform apply`**
```bash
terraform apply
```

**What it does:**
- Executes the plan from step 2
- Makes API calls to AWS to create resources
- Updates the state file to track what was created
- Shows you the outputs (IP addresses, etc.)

---

## **Where Configuration Comes From**

Let me show you the key parts of our `main.tf`:

### **Provider Configuration**
```hcl
provider "aws" {
  region = var.aws_region  # Defaults to "us-east-2"
}
```
This tells Terraform to use AWS and which region.

### **Resource Definitions**
```hcl
# VPC (Virtual Private Cloud)
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "plant-monitoring-freetier-vpc"
  }
}

# EC2 Instance for Control Plane
resource "aws_instance" "k8s_control_plane" {
  ami                    = data.aws_ami.ubuntu.id  # Latest Ubuntu AMI
  instance_type          = "t2.micro"              # FREE TIER
  key_name               = aws_key_pair.k8s_key.key_name
  vpc_security_group_ids = [aws_security_group.k8s_control_plane.id]
  subnet_id              = aws_subnet.k8s_public.id
  
  # User data script runs on first boot
  user_data = base64encode(templatefile("${path.module}/scripts/control-plane-init.sh", {
    cluster_name = var.cluster_name
  }))
}
```

### **Dependencies and References**
Terraform automatically figures out the order:
1. Create VPC first
2. Create subnet (needs VPC)
3. Create security group (needs VPC)  
4. Create EC2 instance (needs subnet + security group)

---

## **Terraform vs Other Infrastructure Tools**

### **1. Terraform (HashiCorp)**
```hcl
# Declarative - describe what you want
resource "aws_instance" "web" {
  instance_type = "t2.micro"
  ami          = "ami-12345"
}
```

**Pros:**
- ✅ **Cloud-agnostic** (AWS, GCP, Azure, etc.)
- ✅ **State management** (tracks what exists)
- ✅ **Plan before apply** (see changes first)
- ✅ **Large community** and provider ecosystem
- ✅ **Declarative** (describe desired end state)

**Cons:**
- ❌ Learning curve for HCL syntax
- ❌ State file management can be tricky
- ❌ No built-in secrets management

### **2. AWS CloudFormation**
```yaml
# AWS-native, YAML/JSON
Resources:
  WebServer:
    Type: AWS::EC2::Instance
    Properties:
      InstanceType: t2.micro
      ImageId: ami-12345
```

**Pros:**
- ✅ **Native AWS integration**
- ✅ **No additional tools needed**
- ✅ **CloudFormation drift detection**
- ✅ **IAM integration**

**Cons:**
- ❌ **AWS only** (vendor lock-in)
- ❌ Verbose YAML syntax
- ❌ Slower than Terraform
- ❌ Limited logic/functions

### **3. Pulumi**
```typescript
// Real programming languages (TypeScript, Python, Go)
const instance = new aws.ec2.Instance("web", {
    instanceType: "t2.micro",
    ami: "ami-12345"
});
```

**Pros:**
- ✅ **Real programming languages**
- ✅ Familiar development tools
- ✅ Advanced logic and loops
- ✅ Built-in testing frameworks

**Cons:**
- ❌ Smaller community
- ❌ More complex for simple tasks
- ❌ Requires programming knowledge

### **4. AWS CDK (Cloud Development Kit)**
```typescript
// AWS-specific, multiple languages
const instance = new ec2.Instance(this, 'WebServer', {
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T2, ec2.InstanceSize.MICRO),
  machineImage: ec2.MachineImage.latestAmazonLinux()
});
```

**Pros:**
- ✅ **Type safety** with IDEs
- ✅ **AWS best practices** built-in
- ✅ Generates CloudFormation
- ✅ Rich AWS service support

**Cons:**
- ❌ **AWS only** (vendor lock-in)
- ❌ Steeper learning curve
- ❌ Less mature than Terraform

### **5. Ansible (Configuration Management)**
```yaml
# Primarily for configuration, but can provision
- name: Launch instance
  amazon.aws.ec2_instance:
    instance_type: t2.micro
    image_id: ami-12345
    state: present
```

**Pros:**
- ✅ **Agentless** (SSH-based)
- ✅ Great for **configuration management**
- ✅ Simple YAML syntax
- ✅ Large module ecosystem

**Cons:**
- ❌ **Not infrastructure-first** (designed for config)
- ❌ No built-in state management
- ❌ Sequential execution (slower)

---

## **Why Terraform for Kubernetes Infrastructure?**

### **1. Kubernetes-Specific Benefits**
```hcl
# Terraform can manage both infrastructure AND Kubernetes resources
resource "aws_instance" "k8s_node" {
  # Create the VM
}

resource "kubernetes_namespace" "app" {
  # Also manage Kubernetes objects
  depends_on = [aws_instance.k8s_node]
}
```

### **2. Multi-Cloud Kubernetes**
```hcl
# Same syntax works for different clouds
# AWS EKS
resource "aws_eks_cluster" "main" { }

# Google GKE  
resource "google_container_cluster" "main" { }

# Azure AKS
resource "azurerm_kubernetes_cluster" "main" { }
```

### **3. GitOps Integration**
```bash
# Infrastructure as Code in Git
git commit -m "Add monitoring to cluster"
terraform plan   # Review changes
terraform apply  # Deploy changes
```

---

## **Alternative Approaches for Kubernetes**

### **1. Managed Services (Easy)**
```bash
# AWS EKS (managed control plane)
aws eks create-cluster --name my-cluster

# Google GKE
gcloud container clusters create my-cluster

# Azure AKS  
az aks create --name my-cluster
```
**When to use:** Production workloads, don't want to manage control plane

### **2. Kubernetes Installers (Learning)**
```bash
# kubeadm (what we're using)
kubeadm init

# kops (AWS-specific)
kops create cluster

# Rancher RKE
rke up
```
**When to use:** Learning, custom requirements, cost optimization

### **3. All-in-One Distributions**
```bash
# k3s (lightweight)
curl -sfL https://get.k3s.io | sh -

# MicroK8s (Ubuntu)
snap install microk8s

# Kind (Docker)
kind create cluster
```
**When to use:** Development, testing, edge computing

---

## **Our Choice: Terraform + kubeadm**

### **Why This Combination?**

1. **Learning Value**: You understand every component
2. **Cost Effective**: No managed service fees  
3. **Flexibility**: Full control over configuration
4. **Transferable Skills**: Works with any cloud
5. **Production Ready**: Scales to real workloads

### **The Complete Stack**
```
┌─────────────────────────────────────┐
│           Terraform                 │ ← Infrastructure provisioning
├─────────────────────────────────────┤
│           kubeadm                   │ ← Kubernetes installation  
├─────────────────────────────────────┤
│           kubectl                   │ ← Kubernetes management
├─────────────────────────────────────┤  
│        Your Applications            │ ← Plant monitoring system
└─────────────────────────────────────┘
```

---

## **Hands-On: See Terraform in Action**

Let's examine what our `terraform plan` would show:

```bash
cd /home/tricia/dev/CS5287_fork_master/CA2/aws-cluster-setup

# See what Terraform will create (without creating it)
terraform init
terraform plan

# Example output:
# + aws_vpc.k8s_vpc
# + aws_subnet.k8s_public  
# + aws_security_group.k8s_control_plane
# + aws_instance.k8s_control_plane
# + aws_instance.k8s_workers[0]
# + aws_instance.k8s_workers[1]
# ... (12 resources total)
```

This gives you complete visibility into what will be created before you spend any money!

The power of Terraform is this **declarative approach** - you describe the desired end state, and Terraform figures out how to get there.