#!/bin/bash
# Lightweight NGINX Ingress Controller for t2.micro environments
# CS5287 CA2 - Resource-optimized ingress setup

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔒 Installing Lightweight NGINX Ingress Controller for t2.micro${NC}"
echo "=================================================================="

# Check if ingress controller is already installed
if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  NGINX Ingress Controller namespace exists, cleaning up first...${NC}"
    kubectl delete namespace ingress-nginx --ignore-not-found=true
    echo "Waiting for cleanup..."
    sleep 10
fi

echo -e "${YELLOW}📦 Installing resource-optimized NGINX Ingress Controller...${NC}"

# Install lightweight version with reduced resource requirements
kubectl apply -f "$(dirname "$0")/ingress-controller-lite.yaml"

echo -e "${YELLOW}⏳ Waiting for lightweight ingress controller to be ready...${NC}"
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app=ingress-nginx \
    --timeout=180s

echo -e "${GREEN}✅ Lightweight ingress controller ready!${NC}"

# Apply security-focused ingress configuration
echo -e "${YELLOW}🛡️  Applying security-focused ingress configuration...${NC}"
kubectl apply -f "$(dirname "$0")/ingress.yaml"

# Get access information
INGRESS_SERVICE_TYPE=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.type}')
echo -e "${GREEN}✅ Ingress controller service type: $INGRESS_SERVICE_TYPE${NC}"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
         kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

echo -e "${GREEN}🌍 External Access Information:${NC}"
echo "=================================================================="
echo "🏠 Home Assistant Dashboard:"
echo "  📍 URL: http://$NODE_IP:$NODE_PORT"
echo "  🔒 Security: Rate limited, security headers enabled"
echo "  💡 Note: Add 'plant-monitoring.local' to your /etc/hosts pointing to $NODE_IP for proper hostname access"

echo ""
echo -e "${GREEN}🔒 Security Features Enabled:${NC}"
echo "✅ Rate limiting (30 requests per minute)"
echo "✅ Security headers (X-Frame-Options, X-XSS-Protection, etc.)"
echo "✅ Network policies restricting pod communication"
echo "✅ ClusterIP services (no direct external port exposure)"
echo "✅ Resource-optimized for t2.micro (32Mi RAM, 25m CPU)"
echo "✅ Control plane tolerations for scheduling flexibility"
echo ""
echo -e "${YELLOW}📝 Port Forwarding Alternative (for development):${NC}"
echo "kubectl port-forward -n plant-monitoring svc/homeassistant-service 8123:8123"
echo "Then access: http://localhost:8123"
echo ""
echo -e "${YELLOW}🔍 Monitoring Commands:${NC}"
echo "kubectl get ingress -n plant-monitoring"
echo "kubectl describe ingress homeassistant-ingress -n plant-monitoring"
echo "kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller"

echo ""
echo -e "${GREEN}✅ Lightweight secure ingress setup complete!${NC}"