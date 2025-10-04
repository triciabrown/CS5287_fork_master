#!/bin/bash
# DNS Update Script for Free Tier Kubernetes Cluster
# Automatically updates DNS records when cluster IPs change

set -e

# Configuration
DOMAIN_NAME="plant-monitor.your-domain.com"
MQTT_DOMAIN="mqtt.plant-monitor.your-domain.com" 
NAMESPACE="plant-monitoring"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🌐 DNS Update Script for Plant Monitoring System${NC}"
echo "=================================================="

# Get current external IP
EXTERNAL_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
if [[ -z "$EXTERNAL_IP" ]]; then
    EXTERNAL_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo -e "${YELLOW}⚠️  Using internal IP (no external IP available): $EXTERNAL_IP${NC}"
else
    echo -e "${GREEN}✅ External IP detected: $EXTERNAL_IP${NC}"
fi

# Function to update DNS record (example with AWS Route53)
update_aws_dns() {
    local domain=$1
    local ip=$2
    
    echo "Updating DNS record for $domain -> $ip"
    
    # Get hosted zone ID
    ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${domain#*.}'].Id" --output text | cut -d'/' -f3)
    
    if [[ -n "$ZONE_ID" ]]; then
        # Create change batch
        cat > /tmp/dns-change.json << EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "$domain",
            "Type": "A",
            "TTL": 300,
            "ResourceRecords": [{"Value": "$ip"}]
        }
    }]
}
EOF
        
        # Apply changes
        aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file:///tmp/dns-change.json
        echo -e "${GREEN}✅ DNS record updated for $domain${NC}"
    else
        echo -e "${YELLOW}⚠️  Hosted zone not found for $domain${NC}"
    fi
}

# Function to update with free DNS services (example with DuckDNS)
update_duckdns() {
    local subdomain=$1
    local ip=$2
    local token=$3  # Your DuckDNS token
    
    echo "Updating DuckDNS record for $subdomain.duckdns.org -> $ip"
    
    response=$(curl -s "https://www.duckdns.org/update?domains=$subdomain&token=$token&ip=$ip")
    
    if [[ "$response" == "OK" ]]; then
        echo -e "${GREEN}✅ DuckDNS updated successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  DuckDNS update failed: $response${NC}"
    fi
}

# Function to update /etc/hosts for local development
update_local_hosts() {
    local domain=$1
    local ip=$2
    
    echo "Updating local /etc/hosts for development"
    
    # Remove existing entries
    sudo sed -i "/$domain/d" /etc/hosts 2>/dev/null || true
    
    # Add new entries
    echo "$ip $domain" | sudo tee -a /etc/hosts > /dev/null
    echo "$ip mqtt.$domain" | sudo tee -a /etc/hosts > /dev/null
    
    echo -e "${GREEN}✅ Local /etc/hosts updated${NC}"
}

# Main execution
echo ""
echo -e "${YELLOW}📝 Choose DNS update method:${NC}"
echo "1) AWS Route53 (requires AWS CLI and hosted zone)"
echo "2) DuckDNS (free, requires token)"
echo "3) Local /etc/hosts (development only)"
echo "4) Display commands only (manual setup)"

read -p "Enter choice (1-4): " choice

case $choice in
    1)
        if command -v aws &> /dev/null; then
            update_aws_dns "$DOMAIN_NAME" "$EXTERNAL_IP"
            update_aws_dns "$MQTT_DOMAIN" "$EXTERNAL_IP"
        else
            echo -e "${YELLOW}⚠️  AWS CLI not found. Install AWS CLI first.${NC}"
        fi
        ;;
    2)
        read -p "Enter DuckDNS subdomain: " subdomain
        read -p "Enter DuckDNS token: " token
        update_duckdns "$subdomain" "$EXTERNAL_IP" "$token"
        ;;
    3)
        update_local_hosts "plant-monitor.local" "$EXTERNAL_IP"
        DOMAIN_NAME="plant-monitor.local"
        MQTT_DOMAIN="mqtt.plant-monitor.local"
        ;;
    4)
        echo ""
        echo -e "${BLUE}📋 Manual DNS Setup Commands:${NC}"
        echo "Domain: $DOMAIN_NAME"
        echo "IP Address: $EXTERNAL_IP"
        echo ""
        echo "AWS Route53:"
        echo "  aws route53 change-resource-record-sets --hosted-zone-id YOUR_ZONE_ID --change-batch '{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$DOMAIN_NAME\",\"Type\":\"A\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"$EXTERNAL_IP\"}]}}]}'"
        echo ""
        echo "Cloudflare:"
        echo "  curl -X PUT \"https://api.cloudflare.com/client/v4/zones/YOUR_ZONE_ID/dns_records/YOUR_RECORD_ID\" -H \"Authorization: Bearer YOUR_TOKEN\" -H \"Content-Type: application/json\" --data '{\"type\":\"A\",\"name\":\"$DOMAIN_NAME\",\"content\":\"$EXTERNAL_IP\"}'"
        ;;
esac

echo ""
echo -e "${BLUE}🌐 DNS Configuration Complete${NC}"
echo "============================================"
echo "Home Assistant URL: http://$DOMAIN_NAME"
echo "MQTT Broker: $MQTT_DOMAIN:1883"
echo ""
echo -e "${YELLOW}📝 Update Home Assistant Configuration:${NC}"
echo "In Home Assistant MQTT integration, use:"
echo "  Broker: $MQTT_DOMAIN"
echo "  Port: 1883"
echo ""
echo -e "${YELLOW}🔄 To update DNS when IP changes:${NC}"
echo "  ./update-dns.sh"