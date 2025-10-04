#!/bin/bash
# Add Additional Worker Nodes to Existing Kubernetes Cluster
# This script will provision 2 additional t2.micro instances and join them to the cluster

set -e

echo "🚀 Adding 2 additional worker nodes to the cluster..."

# Get current terraform state
cd /home/tricia/dev/CS5287_fork_master/CA2/aws-cluster-setup

# Create additional worker nodes by modifying count
echo "📝 Updating Terraform configuration to add worker nodes..."

# Backup current main.tf
cp main.tf main.tf.backup

# Update worker node count from 2 to 4
sed -i 's/count                  = 2/count                  = 4/' main.tf

echo "🏗️ Applying Terraform changes..."
terraform plan -out=add-workers.tfplan
terraform apply add-workers.tfplan

echo "⏱️ Waiting for new instances to be ready..."
sleep 60

# Get new worker IPs
echo "🔍 Getting new worker node IPs..."
NEW_WORKER_3_IP=$(terraform output -json worker_ips | jq -r '.[2]')
NEW_WORKER_4_IP=$(terraform output -json worker_ips | jq -r '.[3]')
CONTROL_PLANE_IP=$(terraform output -json control_plane_ip | jq -r '.')

echo "New worker nodes:"
echo "  Worker 3: $NEW_WORKER_3_IP"
echo "  Worker 4: $NEW_WORKER_4_IP"

# Get join command from control plane
echo "🔑 Getting cluster join token..."
JOIN_COMMAND=$(ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$CONTROL_PLANE_IP \
  "sudo kubeadm token create --print-join-command 2>/dev/null")

echo "Generated join command: $JOIN_COMMAND"

# Join new worker nodes to cluster
echo "🤝 Joining worker node 3 to cluster..."
ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$NEW_WORKER_3_IP \
  "sudo $JOIN_COMMAND"

echo "🤝 Joining worker node 4 to cluster..."  
ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$NEW_WORKER_4_IP \
  "sudo $JOIN_COMMAND"

echo "⏱️ Waiting for nodes to be ready..."
sleep 30

# Verify nodes joined successfully
echo "✅ Verifying cluster status..."
ssh -i ~/.ssh/k8s-cluster-key -o StrictHostKeyChecking=no ubuntu@$CONTROL_PLANE_IP \
  "kubectl get nodes -o wide"

echo ""
echo "🎉 Successfully added 2 additional worker nodes!"
echo ""
echo "New cluster capacity:"
echo "  Nodes: 5 total (1 control plane + 4 workers)"
echo "  CPU: 5 vCPUs total"
echo "  RAM: 5GB total (~3.5GB available for pods)"
echo ""
echo "Memory distribution now allows for:"
echo "  Kafka: 512Mi request ✅"
echo "  MongoDB: 256Mi request ✅"  
echo "  Home Assistant: 256Mi request ✅"
echo "  Processor: 128Mi request ✅"
echo "  MQTT: 64Mi request ✅"
echo "  System overhead: ~1.5GB"
echo ""
echo "Next steps:"
echo "1. Redeploy applications: cd ../plant-monitor-k8s-IaC && ./deploy.sh"
echo "2. Verify pod distribution: kubectl get pods -o wide"
echo "3. Set up horizontal pod autoscaling"
echo ""