# Docker Image Versions

This document tracks all Docker images used in the plant monitoring system.

## Best Practices
- ✅ **Always use specific version tags** (never `:latest` in production)
- ✅ **Pin all third-party images** to specific versions
- ✅ **Document image sources** and update dates
- ✅ **Test version upgrades** in development before production

## Custom Application Images

Built and maintained by the project team. Stored in Docker Hub: `docker.io/triciab221`

| Service | Image | Version | Source |
|---------|-------|---------|--------|
| Plant Sensor | `triciab221/plant-sensor` | `v1.0.0` | `/applications/sensor/` |
| Plant Processor | `triciab221/plant-processor` | `v1.0.0` | `/applications/processor/` |

**Build Command:**
```bash
cd applications/
PUSH_IMAGES=true ./build-images.sh
```

## Third-Party Images

Official images from Docker Hub. Pinned to specific versions for stability.

### Message Queue & Streaming

| Service | Image | Version | Notes |
|---------|-------|---------|-------|
| Zookeeper | `confluentinc/cp-zookeeper` | `7.4.0` | Kafka coordination service |
| Kafka | `confluentinc/cp-kafka` | `7.4.0` | Event streaming platform |
| Mosquitto | `eclipse-mosquitto` | `2.0` | MQTT broker for IoT |

### Data Storage

| Service | Image | Version | Notes |
|---------|-------|---------|-------|
| MongoDB | `mongo` | `6.0.4` | Document database |

### Automation & UI

| Service | Image | Version | Notes |
|---------|-------|---------|-------|
| Home Assistant | `homeassistant/home-assistant` | `2023.8.0` | Smart home automation |

## Version Update Strategy

### When to Update
- **Security patches**: Update immediately
- **Bug fixes**: Update after testing in development
- **Feature updates**: Evaluate need, test thoroughly
- **Major versions**: Plan migration, test extensively

### Update Process
1. **Review release notes** for breaking changes
2. **Test in local environment** first
3. **Update version** in `docker-compose.yml`
4. **Re-deploy with** `./deploy.sh`
5. **Monitor services** for issues
6. **Rollback if needed** by reverting version tag

### Rollback Procedure
```bash
# Revert docker-compose.yml to previous version
git checkout HEAD~1 docker-compose.yml

# Redeploy with previous versions
./deploy.sh
```

## Image Size Reference

Approximate sizes for capacity planning:

| Image | Size | Notes |
|-------|------|-------|
| plant-sensor:v1.0.0 | ~200MB | Node.js + dependencies |
| plant-processor:v1.0.0 | ~250MB | Node.js + Kafka/Mongo clients |
| cp-kafka:7.4.0 | ~800MB | Full Kafka installation |
| cp-zookeeper:7.4.0 | ~800MB | Full Zookeeper installation |
| mongo:6.0.4 | ~700MB | MongoDB with tools |
| eclipse-mosquitto:2.0 | ~10MB | Lightweight MQTT broker |
| home-assistant:2023.8.0 | ~1.2GB | Python + all integrations |

**Total Storage Required:** ~5-6GB per node (with volumes)

## Registry Configuration

### Docker Hub (Public)
- **Registry:** `docker.io`
- **Namespace:** `triciab221`
- **Authentication:** Required for push, optional for pull (public images)
- **Rate Limits:** 200 pulls/6 hours (authenticated), 100 pulls/6 hours (anonymous)

### Login
```bash
docker login docker.io
```

## Verification Commands

### Check Image Availability
```bash
# Custom images
docker manifest inspect docker.io/triciab221/plant-sensor:v1.0.0
docker manifest inspect docker.io/triciab221/plant-processor:v1.0.0

# Third-party images
docker manifest inspect confluentinc/cp-kafka:7.4.0
docker manifest inspect mongo:6.0.4
docker manifest inspect homeassistant/home-assistant:2023.8.0
```

### Pull All Images (Pre-cache)
```bash
# Pull all images to speed up deployment
docker pull confluentinc/cp-zookeeper:7.4.0
docker pull confluentinc/cp-kafka:7.4.0
docker pull mongo:6.0.4
docker pull eclipse-mosquitto:2.0
docker pull homeassistant/home-assistant:2023.8.0
docker pull triciab221/plant-processor:v1.0.0
docker pull triciab221/plant-sensor:v1.0.0
```

## Version History

| Date | Service | Old Version | New Version | Reason |
|------|---------|-------------|-------------|--------|
| 2025-10-17 | plant-sensor | latest | v1.0.0 | Initial versioned release |
| 2025-10-17 | plant-processor | latest | v1.0.0 | Initial versioned release |

## Future Considerations

### Planned Updates
- [ ] Evaluate Kafka 7.5.x for performance improvements
- [ ] Consider MongoDB 7.x when stable
- [ ] Monitor Home Assistant releases for security patches

### Alternative Registries
- **AWS ECR**: For production deployments on AWS
- **GitHub Container Registry**: For CI/CD integration
- **Harbor**: For self-hosted private registry

### Image Optimization
- [ ] Create Alpine-based images for smaller footprint
- [ ] Multi-stage builds for production images
- [ ] Remove development dependencies from production images
- [ ] Consider distroless base images for security

## Troubleshooting

### Image Pull Failures
```bash
# Check Docker Hub status
curl -s https://status.docker.com/

# Check rate limits
docker login docker.io  # Authenticate to increase limits

# Manually pull problematic image
docker pull triciab221/plant-sensor:v1.0.0 --platform linux/amd64
```

### Version Conflicts
```bash
# List all running images
docker service ls --format "table {{.Name}}\t{{.Image}}"

# Force recreation with new version
docker service update --image triciab221/plant-sensor:v1.0.0 plant-monitoring_sensor
```

### Storage Issues
```bash
# Clean up old images
docker system prune -a

# Check disk usage
docker system df
```

## References

- [Docker Image Tagging Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Semantic Versioning](https://semver.org/)
- [Docker Hub Rate Limits](https://docs.docker.com/docker-hub/download-rate-limit/)
- [Confluent Platform Compatibility](https://docs.confluent.io/platform/current/installation/versions-interoperability.html)
