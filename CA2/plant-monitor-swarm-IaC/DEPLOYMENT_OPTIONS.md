# Deployment Options

## Quick Reference

### Default Deployment (AWS Multi-Node - PRODUCTION)
```bash
./deploy.sh
```
- Provisions AWS infrastructure (1 manager + 4 workers)
- Configures Docker Swarm cluster
- Deploys all applications
- **This is the primary deployment mode for the assignment**

### Local Development Deployment
```bash
MODE=local ./deploy.sh
```
- Uses existing local machine
- Single-node Docker Swarm
- Fast deployment for testing
- Does NOT build or push images

### Build Images During Deployment
```bash
BUILD_IMAGES=true ./deploy.sh              # AWS with image building
BUILD_IMAGES=true MODE=local ./deploy.sh   # Local with image building
```
- Builds custom images before deploying
- Does NOT push to Docker Hub (local only)
- Useful when code changed
- Single-node deployment only

### Build Images Separately (Recommended for Multi-Node)
```bash
# 1. Build images
cd ../applications
./build-images.sh

# 2. Deploy
cd ../plant-monitor-swarm-IaC
./deploy.sh
```
- Gives you control over build process
- Can inspect images before deploying
- Cleaner separation of concerns

### Build AND Push to Docker Hub
```bash
# 1. Login to Docker Hub (one time)
docker login

# 2. Build and push images
cd ../applications
PUSH_IMAGES=true ./build-images.sh

# 3. Deploy (images will be pulled from Docker Hub)
cd ../plant-monitor-swarm-IaC
./deploy.sh
```
- Required for multi-node deployments
- Images available on all worker nodes
- Images available for team/graders

## Image Building Options

### build-images.sh Environment Variables

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `PUSH_IMAGES` | `auto`, `true`, `false` | `auto` | Control image pushing |

**Examples:**
```bash
# Auto mode: push if logged in, skip if not
./build-images.sh

# Force push (fails if not logged in)
PUSH_IMAGES=true ./build-images.sh

# Build only, never push
PUSH_IMAGES=false ./build-images.sh
```

## Deploy Script Options

### deploy.sh Environment Variables

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `BUILD_IMAGES` | `true`, `false` | `false` | Build images before deploying |
| Stack Name | any string | `plant-monitoring` | First positional argument |

**Examples:**
```bash
# Default: use existing images
./deploy.sh

# Build images first
BUILD_IMAGES=true ./deploy.sh

# Custom stack name
./deploy.sh my-custom-stack

# Both options
BUILD_IMAGES=true ./deploy.sh my-stack
```

## Common Workflows

### Production Deployment (AWS)
```bash
# Default - no mode specification needed
./deploy.sh

# Swarm provisions infrastructure and deploys everything
# Access Home Assistant at the provided IP address
```

### Local Development (Single Node)
```bash
# First time setup
MODE=local ./deploy.sh

# Code changed, rebuild and redeploy
BUILD_IMAGES=true MODE=local ./deploy.sh

# Or separately
cd ../applications && ./build-images.sh
cd ../plant-monitor-swarm-IaC && docker stack rm plant-monitoring
MODE=local ./deploy.sh
```

### Production Teardown
```bash
# Default - destroys ALL AWS resources
./teardown.sh

# This will:
# 1. Remove the Docker stack
# 2. Destroy all EC2 instances
# 3. Destroy VPC, security groups, etc.
# 4. Clean up Terraform state
```

## Troubleshooting

### "Image not found" Error
```
Error: image docker.io/triciab221/plant-processor:latest not found
```

**Solution:**
```bash
# Option 1: Build locally
cd applications
./build-images.sh

# Option 2: Pull from Docker Hub
docker pull docker.io/triciab221/plant-processor:latest
docker pull docker.io/triciab221/plant-sensor:latest

# Option 3: Build during deploy
BUILD_IMAGES=true ./deploy.sh
```

### "Not logged into Docker" Warning
```
⚠️  Not logged into Docker registry
```

**This is OK for local deployment!** Images are built locally and don't need to be pushed.

**Only login if:**
- You want to push to Docker Hub
- You're deploying multi-node (workers need to pull)

```bash
docker login
# Enter your Docker Hub username and password
```

### Image Built But Not Pushed
```
Images are built locally only
To push images to Docker Hub:
  1. docker login
  2. PUSH_IMAGES=true ./build-images.sh
```

**This is expected behavior!** The script detected you're not logged in and skipped pushing.

**Action:**
- For single-node: No action needed
- For multi-node: Login and re-run with `PUSH_IMAGES=true`

## Best Practices

### ✅ DO:
- Use default `./deploy.sh` for normal deployments
- Build images separately when developing
- Push to Docker Hub for multi-node deployments
- Use meaningful stack names for multiple environments
- Keep images in Docker Hub for reproducibility

### ❌ DON'T:
- Build images on every deployment (unnecessary)
- Push to Docker Hub unless needed (saves time)
- Mix build and deploy unless you know why
- Forget to login before pushing (will fail)

## Performance Tips

| Operation | Time | When to Use |
|-----------|------|-------------|
| `./deploy.sh` (no build) | ~1-2 min | Most deployments |
| `BUILD_IMAGES=true ./deploy.sh` | ~3-5 min | Code changed |
| Build separately | ~2-3 min build, ~1-2 min deploy | Best control |
| Push to Docker Hub | +1-2 min | Multi-node only |

## Summary

**Default behavior (AWS PRODUCTION):**
- `./deploy.sh` - Full AWS infrastructure + application deployment
- `./teardown.sh` - Complete AWS teardown

**Development override:**
- `MODE=local ./deploy.sh` - Local single-node deployment
- `MODE=local ./teardown.sh` - Local cleanup only

**Optional modifiers:**
- `BUILD_IMAGES=true ./deploy.sh` - Build images first (for local mode)
- `PUSH_IMAGES=true ./build-images.sh` - Push images to Docker Hub

**Assignment submission:**
The default `./deploy.sh` command provisions complete AWS infrastructure and deploys the application stack with a single command, meeting the CA2 requirement for declarative orchestration deployment! 🎉
