#!/bin/bash
# Join workers to swarm - execute on manager node

WORKER_TOKEN="$1"
MANAGER_PRIVATE_IP="$2"
shift 2
WORKERS=("$@")

echo "Worker join configuration:"
echo "  Manager IP: ${MANAGER_PRIVATE_IP}"
echo "  Number of workers: ${#WORKERS[@]}"
echo ""

for i in "${!WORKERS[@]}"; do
  WORKER_IP="${WORKERS[$i]}"
  echo "Joining worker $((i+1)): ${WORKER_IP}"
  ssh -o StrictHostKeyChecking=no -i ~/.ssh/docker-swarm-key ubuntu@${WORKER_IP} \
    "sudo docker swarm join --token ${WORKER_TOKEN} ${MANAGER_PRIVATE_IP}:2377" 2>&1
  echo ""
done

echo "Final cluster status:"
sudo docker node ls
