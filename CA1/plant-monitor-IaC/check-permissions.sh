#!/bin/bash

# AWS Permissions Checker for Plant Monitoring Infrastructure
# Verifies that the current AWS user has the required permissions

echo "🔍 Checking AWS Permissions for Plant Monitoring Deployment..."
echo "================================================================"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS CLI not configured or credentials invalid"
    echo "   Run: aws configure"
    exit 1
fi

# Get current user identity
USER_ARN=$(aws sts get-caller-identity --query "Arn" --output text)
echo "✅ AWS User: $USER_ARN"

# Test EC2 permissions
echo ""
echo "🔧 Testing EC2 Permissions..."
if aws ec2 describe-vpcs --max-items 1 &>/dev/null; then
    echo "✅ EC2 Read: OK"
else
    echo "❌ EC2 Read: Failed"
fi

# Test Secrets Manager permissions
echo ""
echo "🔐 Testing AWS Secrets Manager Permissions..."

# Try to list secrets (basic read permission)
if aws secretsmanager list-secrets --max-items 1 &>/dev/null; then
    echo "✅ Secrets Manager Read: OK"
else
    echo "❌ Secrets Manager Read: Failed"
fi

# Test secret creation (will create and immediately delete a test secret)
TEST_SECRET_NAME="plant-monitoring-permission-test-$(date +%s)"
echo "🧪 Testing secret creation with: $TEST_SECRET_NAME"

if aws secretsmanager create-secret \
    --name "$TEST_SECRET_NAME" \
    --description "Permission test - will be deleted immediately" \
    --secret-string '{"test":"value"}' &>/dev/null; then
    
    echo "✅ Secrets Manager Create: OK"
    
    # Clean up test secret
    aws secretsmanager delete-secret \
        --secret-id "$TEST_SECRET_NAME" \
        --force-delete-without-recovery &>/dev/null
    echo "🧹 Test secret cleaned up"
else
    echo "❌ Secrets Manager Create: FAILED"
    echo ""
    echo "🚨 ERROR: Missing AWS Secrets Manager permissions!"
    echo "   Your user needs the following permissions:"
    echo "   - secretsmanager:CreateSecret"
    echo "   - secretsmanager:GetSecretValue" 
    echo "   - secretsmanager:PutSecretValue"
    echo "   - secretsmanager:UpdateSecret"
    echo "   - secretsmanager:DeleteSecret"
    echo ""
    echo "📖 See CA1/README.md for the complete IAM policy JSON"
    exit 1
fi

echo ""
echo "🎉 All permissions verified! Ready for deployment."
echo "   Run: ./deploy.sh"