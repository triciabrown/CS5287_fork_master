#!/bin/bash
# Data Transfer Monitoring Script
# Run this during deployment to track progress

echo "=== AWS Data Transfer Monitoring ==="
echo "Date: $(date)"
echo ""

# Check if kubectl is available
if command -v kubectl &> /dev/null; then
    echo "🔍 Kubernetes Cluster Status:"
    kubectl get nodes --no-headers 2>/dev/null | wc -l | xargs echo "  Nodes ready:"
    kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" | xargs echo "  Pods running:"
    echo ""
fi

# Monitor container image pulls
echo "🖼️  Container Image Activity:"
if command -v kubectl &> /dev/null; then
    kubectl get events --all-namespaces --field-selector reason=Pulled --no-headers 2>/dev/null | wc -l | xargs echo "  Images pulled:"
    kubectl get events --all-namespaces --field-selector reason=Pulling --no-headers 2>/dev/null | wc -l | xargs echo "  Images pulling:"
fi

# Estimate data usage
echo ""
echo "📊 Estimated Data Transfer:"
if command -v kubectl &> /dev/null; then
    PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running")
    IMAGES=$(kubectl get events --all-namespaces --field-selector reason=Pulled --no-headers 2>/dev/null | wc -l)
    
    # Rough estimates
    SYSTEM_OVERHEAD=$((50 * $PODS))  # 50MB per pod for system overhead  
    IMAGE_DATA=$((100 * $IMAGES))    # 100MB average per image pull
    TOTAL=$((SYSTEM_OVERHEAD + IMAGE_DATA))
    
    echo "  System overhead: ~${SYSTEM_OVERHEAD}MB"
    echo "  Image pulls: ~${IMAGE_DATA}MB" 
    echo "  Total estimate: ~${TOTAL}MB"
    
    if [ $TOTAL -gt 800 ]; then
        echo "  ⚠️  WARNING: Approaching 1GB limit!"
    elif [ $TOTAL -gt 500 ]; then
        echo "  ⚠️  CAUTION: Over 500MB used"
    else
        echo "  ✅ Usage appears reasonable"
    fi
fi

echo ""
echo "💡 Tips to minimize further usage:"
echo "  - Deploy applications one at a time"
echo "  - Monitor before deploying large components"
echo "  - Use 'kubectl get events' to track image pulls"
echo ""