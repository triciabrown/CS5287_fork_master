#!/bin/bash
# Build and Push Custom Container Images
# CS5287 CA2 - Plant Monitoring System

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Update these as needed
DOCKER_REGISTRY="docker.io"
DOCKER_NAMESPACE="triciab221"  # Your Docker Hub username
IMAGE_VERSION="v1.0.0"

# Check if namespace is still default
if [[ "$DOCKER_NAMESPACE" == "cs5287" ]]; then
    echo -e "${YELLOW}⚠️  Please update DOCKER_NAMESPACE to your Docker Hub username in this script${NC}"
    read -p "Enter your Docker Hub username: " username
    if [[ -n "$username" ]]; then
        DOCKER_NAMESPACE="$username"
    else
        echo -e "${RED}❌ Docker Hub username required${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}🐳 Building Custom Container Images${NC}"
echo "================================="

# Check Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
    exit 1
fi

# Check Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker daemon not running. Please start Docker.${NC}"
    exit 1
fi

echo -e "${YELLOW}📋 Configuration:${NC}"
echo "Registry: $DOCKER_REGISTRY"
echo "Namespace: $DOCKER_NAMESPACE"
echo "Version: $VERSION_TAG"
echo ""

# Build Sensor Image
echo -e "${YELLOW}� Building Plant Sensor Image${NC}"
cd sensor/
docker build -t $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:$VERSION_TAG .
docker tag $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:$VERSION_TAG $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:latest

echo -e "${GREEN}✅ Sensor image built successfully${NC}"
cd ..

# Build Processor Image
echo -e "${YELLOW}⚙️ Building Processor Image${NC}"
cd processor/
docker build -t $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:$VERSION_TAG .
docker tag $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:$VERSION_TAG $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:latest

echo -e "${GREEN}✅ Processor image built successfully${NC}"
cd ..

echo ""
echo -e "${YELLOW}📦 Images Built:${NC}"
docker images | grep -E "(plant-producer|plant-processor)"

echo ""
echo -e "${BLUE}🚀 Push Images to Registry${NC}"
echo "=========================="

# Check if logged into Docker registry
if ! docker info | grep -q "Username:"; then
    echo -e "${YELLOW}⚠️  Not logged into Docker registry. Please run:${NC}"
    echo "docker login"
    echo ""
    echo -e "${YELLOW}Then re-run this script to push images.${NC}"
    echo ""
    echo -e "${BLUE}To use images locally without registry:${NC}"
    echo "1. Update plant-monitoring-manifests.yaml image references to:"
    echo "   - image: $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-producer:$VERSION_TAG"
    echo "   - image: $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:$VERSION_TAG"
    echo "2. Add 'imagePullPolicy: Never' to use local images"
    exit 0
fi

# Push images
echo "Pushing sensor image..."
docker push $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:$VERSION_TAG
docker push $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:latest

echo "Pushing processor image..."
docker push $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:$VERSION_TAG
docker push $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:latest

echo ""
echo -e "${GREEN}🎉 Images successfully pushed to registry!${NC}"
echo ""
echo -e "${YELLOW}📝 Images ready for deployment:${NC}"
echo "Sensor: $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:$VERSION_TAG"
echo "Processor: $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:$VERSION_TAG"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo "1. Update image references in plant-monitoring-manifests.yaml if needed"
echo "2. Run: ./deploy-production.sh"
echo ""
echo -e "${BLUE}Ready for deployment! 🚀${NC}"