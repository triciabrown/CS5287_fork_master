#!/bin/bash
# Join workers from manager node

WORKER_TOKEN="SWMTKN-1-4hf17t07qbo0pe9ixhn90tjl4evtzfn4i9o76tjs7fdfizjo0y-8wb2k9xotj9bygcyeohl961a1"
MANAGER_PRIVATE_IP="10.0.1.68"
WORKERS=("10.0.2.82" "10.0.2.49" "10.0.2.193" "10.0.2.84")

for i in "${!WORKERS[@]}"; do
  WORKER_IP="${WORKERS[$i]}"
  echo "Joining worker $((i+1)): ${WORKER_IP}"
  ssh -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key ubuntu@${WORKER_IP} \
    "sudo docker swarm join --token ${WORKER_TOKEN} ${MANAGER_PRIVATE_IP}:2377"
done

echo ""
echo "Cluster Status:"
sudo docker node ls
