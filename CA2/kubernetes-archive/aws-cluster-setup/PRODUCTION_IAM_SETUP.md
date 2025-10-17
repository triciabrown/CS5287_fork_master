# Production IAM Setup for Kubernetes Deployment

## Overview
This guide shows how to properly set up IAM permissions for production Kubernetes cluster deployment while maintaining the principle of least privilege.

## Option 1: Enhance Existing ansible-deployer User (RECOMMENDED)

### Step 1: Create the Additional Policy

1. **Login to AWS Console with Admin Account**
2. **Navigate to IAM > Policies > Create Policy**
3. **Choose JSON tab** and paste the content from `additional-iam-policy.json`
4. **Name the policy**: `KubernetesClusterDeployment`
5. **Add description**: `Allows deployment of Kubernetes clusters with IAM roles and instance profiles`

### Step 2: Attach Policy to ansible-deployer User

```bash
# Via AWS CLI (if you have admin access):
aws iam attach-user-policy \
    --user-name ansible-deployer \
    --policy-arn arn:aws:iam::442042542151:policy/KubernetesClusterDeployment

# Via AWS Console:
# 1. Go to IAM > Users > ansible-deployer
# 2. Click "Add permissions" > "Attach policies directly"
# 3. Search for "KubernetesClusterDeployment"
# 4. Select and attach the policy
```

### Step 3: Verify Permissions

```bash
# Test that the user can now create IAM roles
aws iam create-role --role-name test-k8s-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "ec2.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

# Clean up test role
aws iam delete-role --role-name test-k8s-role
```

### Step 4: Deploy with Enhanced Permissions

```bash
# Now you can use the original main.tf with full IAM support
terraform destroy -auto-approve  # Clean up partial deployment
terraform apply -auto-approve    # Deploy with IAM roles
```

---

## Option 2: Create Dedicated Kubernetes Deployment User

### Step 1: Create New IAM User

```bash
# Create user
aws iam create-user --user-name k8s-cluster-deployer

# Create access key
aws iam create-access-key --user-name k8s-cluster-deployer
```

### Step 2: Create Comprehensive Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2FullAccess",
      "Effect": "Allow",
      "Action": "ec2:*",
      "Resource": "*"
    },
    {
      "Sid": "VPCFullAccess", 
      "Effect": "Allow",
      "Action": [
        "ec2:*Vpc*",
        "ec2:*Subnet*",
        "ec2:*Gateway*",
        "ec2:*Route*",
        "ec2:*SecurityGroup*",
        "ec2:*NetworkAcl*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMKubernetesAccess",
      "Effect": "Allow", 
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy"
      ],
      "Resource": [
        "arn:aws:iam::*:role/k8s-*",
        "arn:aws:iam::*:role/*k8s*",
        "arn:aws:iam::*:instance-profile/k8s-*",
        "arn:aws:iam::*:instance-profile/*k8s*"
      ]
    }
  ]
}
```

---

## Recommended Approach for Your Assignment

**Use Option 1** (enhance ansible-deployer) because:

1. **Consistency**: Continues using the same user from CA1
2. **Principle of Least Privilege**: Only adds necessary permissions
3. **Audit Trail**: Maintains clear separation between networking (CA1) and compute (CA2)
4. **Production-Ready**: Shows how to incrementally add permissions
5. **Assignment Continuity**: Demonstrates evolution of infrastructure permissions

---

## Security Best Practices Implemented

### 1. **Resource-Scoped Permissions**
- IAM actions limited to k8s-related resources
- Cannot create arbitrary IAM roles
- Cannot access other projects' resources

### 2. **AWS Managed Policy References**
- Uses AWS-maintained policies for EKS, CNI, ECR
- Reduces custom policy maintenance
- Follows AWS security recommendations

### 3. **Terraform State Security**
- Keep terraform state files secure
- Consider remote state with S3 + DynamoDB
- Enable state file encryption

### 4. **Monitoring and Auditing**
- All IAM actions logged in CloudTrail
- Resource tagging for cost allocation
- Clear resource naming conventions

---

## Next Steps After Policy Update

1. **Attach the new policy to ansible-deployer**
2. **Clean up the partial deployment**: `terraform destroy`
3. **Deploy with full IAM support**: `terraform apply`
4. **Verify cluster functionality with proper IAM roles**
5. **Document the permission model for your assignment**