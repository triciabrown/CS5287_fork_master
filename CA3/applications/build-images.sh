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
VERSION_TAG="v1.0.0"
PUSH_IMAGES="${PUSH_IMAGES:-auto}"  # auto, true, false

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
echo -e "${YELLOW}🌱 Building Plant Sensor Image${NC}"
cd sensor/
docker build -t $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:$VERSION_TAG .
docker tag $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:$VERSION_TAG $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:latest

echo -e "${GREEN}✅ Sensor image built successfully${NC}"
cd ..

# Build Processor Image
echo -e "${YELLOW}⚙️  Building Processor Image${NC}"
cd processor/
docker build -t $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:$VERSION_TAG .
docker tag $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:$VERSION_TAG $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:latest

echo -e "${GREEN}✅ Processor image built successfully${NC}"
cd ..

echo ""
echo -e "${YELLOW}📦 Images Built:${NC}"
docker images | grep -E "(plant-sensor|plant-processor)"

echo ""

# Determine if we should push
SHOULD_PUSH=false

if [ "$PUSH_IMAGES" = "true" ]; then
    SHOULD_PUSH=true
elif [ "$PUSH_IMAGES" = "false" ]; then
    SHOULD_PUSH=false
    echo -e "${YELLOW}⚠️  Image push disabled (PUSH_IMAGES=false)${NC}"
    echo -e "${BLUE}Images are built locally only${NC}"
    echo ""
elif [ "$PUSH_IMAGES" = "auto" ]; then
    # Auto mode: check if logged in
    if docker info 2>/dev/null | grep -q "Username:"; then
        SHOULD_PUSH=true
    else
        SHOULD_PUSH=false
        echo -e "${YELLOW}⚠️  Not logged into Docker registry${NC}"
        echo -e "${BLUE}Images are built locally only${NC}"
        echo ""
        echo -e "${YELLOW}To push images to Docker Hub:${NC}"
        echo "  1. docker login"
        echo "  2. PUSH_IMAGES=true ./build-images.sh"
        echo ""
    fi
fi

# Push images if requested and logged in
if [ "$SHOULD_PUSH" = true ]; then
    echo -e "${BLUE}🚀 Pushing Images to Registry${NC}"
    echo "=========================="
    
    echo "Pushing sensor image..."
    docker push $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:$VERSION_TAG
    docker push $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:latest
    
    echo "Pushing processor image..."
    docker push $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:$VERSION_TAG
    docker push $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:latest
    
    echo ""
    echo -e "${GREEN}🎉 Images successfully pushed to registry!${NC}"
    echo ""
    echo -e "${YELLOW}📝 Images available in Docker Hub:${NC}"
    echo "Sensor:    $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:$VERSION_TAG"
    echo "Sensor:    $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-sensor:latest"
    echo "Processor: $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:$VERSION_TAG"
    echo "Processor: $DOCKER_REGISTRY/$DOCKER_NAMESPACE/plant-processor:latest"
    echo ""
    echo -e "${BLUE}📝 Next Steps:${NC}"
    echo "1. Images are now available in your Docker Hub registry"
    echo "2. Deploy to Swarm: cd ../plant-monitor-swarm-IaC && ./deploy.sh"
    echo "3. For multi-node: Worker nodes will pull from Docker Hub automatically"
else
    echo -e "${GREEN}✅ Build complete (local images only)${NC}"
    echo ""
    echo -e "${BLUE}📝 Next Steps:${NC}"
    echo "1. For single-node deployment: cd ../plant-monitor-swarm-IaC && ./deploy.sh"
    echo "2. For multi-node deployment: Push images first with PUSH_IMAGES=true ./build-images.sh"
fi