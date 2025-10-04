#!/bin/bash
# Install NGINX Ingress Controller with Security Configurations
# CS5287 CA2 - Secure ingress setup for Plant Monitoring System

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔒 Installing NGINX Ingress Controller with Security Features${NC}"
echo "=================================================================="

# Check if ingress controller is already installed
if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    echo -e "${GREEN}✅ NGINX Ingress Controller namespace already exists${NC}"
else
    echo -e "${YELLOW}📦 Installing NGINX Ingress Controller...${NC}"
    
    # Install NGINX Ingress Controller for AWS
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml
    
    echo -e "${YELLOW}⏳ Waiting for ingress controller to be ready...${NC}"
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
fi

# Apply security-focused ingress configuration
echo -e "${YELLOW}🛡️  Applying security-focused ingress configuration...${NC}"
kubectl apply -f "$(dirname "$0")/ingress.yaml"

# Check ingress controller service type and get access information
INGRESS_SERVICE_TYPE=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.type}')
echo -e "${GREEN}✅ Ingress controller service type: $INGRESS_SERVICE_TYPE${NC}"

if [[ "$INGRESS_SERVICE_TYPE" == "LoadBalancer" ]]; then
    echo -e "${YELLOW}⏳ Waiting for Load Balancer to be provisioned...${NC}"
    kubectl wait --namespace ingress-nginx \
        --for=jsonpath='{.status.loadBalancer.ingress}' \
        service/ingress-nginx-controller \
        --timeout=300s || echo "Load balancer still provisioning..."
    
    EXTERNAL_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                 kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
                 echo "pending")
    
    if [[ "$EXTERNAL_IP" != "pending" ]]; then
        echo -e "${GREEN}🌍 External Access Information:${NC}"
        echo "=================================================================="
        echo "🏠 Home Assistant Dashboard:"
        echo "  📍 URL: http://$EXTERNAL_IP"
        echo "  🔒 Security: Rate limited, security headers enabled"
        echo ""
        echo "📝 To use custom domain:"
        echo "  1. Point your domain to: $EXTERNAL_IP"
        echo "  2. Update ingress.yaml host from 'plant-monitoring.local' to your domain"
        echo "  3. Enable TLS section in ingress.yaml for HTTPS"
    else
        echo -e "${YELLOW}⏳ Load Balancer still provisioning. Check status with:${NC}"
        echo "kubectl get service ingress-nginx-controller -n ingress-nginx -w"
    fi
else
    # For NodePort or other service types
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
             kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    NODE_PORT=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
    
    echo -e "${GREEN}🌍 External Access Information:${NC}"
    echo "=================================================================="
    echo "🏠 Home Assistant Dashboard:"
    echo "  📍 URL: http://$NODE_IP:$NODE_PORT"
    echo "  🔒 Security: Rate limited, security headers enabled"
fi

echo ""
echo -e "${GREEN}🔒 Security Features Enabled:${NC}"
echo "✅ Rate limiting (30 requests per minute)"
echo "✅ Security headers (X-Frame-Options, X-XSS-Protection, etc.)"
echo "✅ Network policies restricting pod communication"
echo "✅ ClusterIP services (no direct external port exposure)"
echo "✅ Request body size limits"
echo "✅ WebSocket support with timeouts"
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
echo -e "${GREEN}✅ Secure ingress setup complete!${NC}"