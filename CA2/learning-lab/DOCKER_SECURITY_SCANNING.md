# Docker Security Scanning Guide

## **Why Scan Container Images?**

Container images often contain:
- **Base OS vulnerabilities** (Ubuntu, Alpine, etc.)
- **Application dependencies** with known security flaws
- **Outdated packages** missing security patches
- **Malware or suspicious code** (rare but possible)

**Real Example**: A MongoDB image might have a vulnerable OpenSSL version that could be exploited.

---

## **Scanning Tools**

### **1. Docker Scout (Recommended for Docker Desktop)**

```bash
# Install Docker Scout (if not already available)
curl -fsSL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh -o install-scout.sh
sh install-scout.sh

# Scan images we're using in our learning lab
docker scout cves confluentinc/cp-kafka:7.4.0
docker scout cves confluentinc/cp-zookeeper:7.4.0  
docker scout cves mongo:6.0.4
docker scout cves eclipse-mosquitto:2.0
```

### **2. Trivy (Open Source)**

```bash
# Install Trivy
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Scan our learning lab images
trivy image confluentinc/cp-kafka:7.4.0
trivy image confluentinc/cp-zookeeper:7.4.0
trivy image mongo:6.0.4
trivy image eclipse-mosquitto:2.0

# Output to JSON for automated processing
trivy image --format json mongo:6.0.4 > mongo-scan-results.json
```

### **3. Snyk (Commercial)**

```bash
# Install Snyk CLI
npm install -g snyk

# Authenticate and scan
snyk auth
snyk container test confluentinc/cp-kafka:7.4.0
```

---

## **Sample Security Scan Results**

### **Critical Vulnerability Example**
```
┌─────────────────────────────────────────────────────────────┐
│ Package: openssl                                            │
│ Installed Version: 1.1.1f-1ubuntu2.16                     │
│ Vulnerability ID: CVE-2022-3602                            │
│ Severity: CRITICAL                                          │
│ Description: X.509 Email Address Buffer Overflow           │
│ Fixed Version: 1.1.1f-1ubuntu2.17                         │
└─────────────────────────────────────────────────────────────┘
```

**Action Required:** 
- ❌ **DO NOT DEPLOY** - Critical vulnerability found
- ✅ **UPDATE** to mongo:6.0.5 or newer
- 🔄 **RE-SCAN** after updating

### **Low Risk Example**
```
┌─────────────────────────────────────────────────────────────┐
│ Package: curl                                               │
│ Installed Version: 7.68.0-1ubuntu2.14                     │
│ Vulnerability ID: CVE-2022-42916                           │
│ Severity: LOW                                               │
│ Description: HSTS bypass                                    │
│ Fixed Version: 7.68.0-1ubuntu2.15                         │
└─────────────────────────────────────────────────────────────┘
```

**Action Required:**
- ✅ **OK TO DEPLOY** - Low risk, plan update in next maintenance window
- 📅 **SCHEDULE** update within 30 days

---

## **Hands-On Exercise: Scan Our Learning Lab**

Let's check if our current images have vulnerabilities:

```bash
# Navigate to our exercise directory
cd /home/tricia/dev/CS5287_fork_master/CA2/learning-lab/04-kafka-networking

# Scan each image we're using
echo "🔍 Scanning Kafka image..."
docker scout cves confluentinc/cp-kafka:7.4.0

echo "🔍 Scanning Zookeeper image..."  
docker scout cves confluentinc/cp-zookeeper:7.4.0

echo "🔍 Scanning MongoDB image (from Exercise 3)..."
docker scout cves mongo:6.0.4

# Create a security report
echo "# Security Scan Results - $(date)" > SECURITY_SCAN_REPORT.md
echo "" >> SECURITY_SCAN_REPORT.md
echo "## Images Scanned" >> SECURITY_SCAN_REPORT.md
echo "- confluentinc/cp-kafka:7.4.0" >> SECURITY_SCAN_REPORT.md
echo "- confluentinc/cp-zookeeper:7.4.0" >> SECURITY_SCAN_REPORT.md  
echo "- mongo:6.0.4" >> SECURITY_SCAN_REPORT.md
echo "" >> SECURITY_SCAN_REPORT.md
echo "## Scan Date: $(date)" >> SECURITY_SCAN_REPORT.md
```

---

## **CI/CD Integration Example**

### **GitHub Actions Workflow**

```yaml
# .github/workflows/security-scan.yml
name: Container Security Scan
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Install Trivy
      run: |
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
    
    - name: Scan for vulnerabilities
      run: |
        # Scan and fail if CRITICAL vulnerabilities found
        trivy image --severity CRITICAL --exit-code 1 ${{ secrets.ECR_REGISTRY }}/plant-processor:${{ github.sha }}
        
        # Generate report for HIGH vulnerabilities (warning only)
        trivy image --severity HIGH --format table ${{ secrets.ECR_REGISTRY }}/plant-processor:${{ github.sha }}
```

---

## **Vulnerability Remediation Strategies**

### **1. Update Base Images**
```dockerfile
# Before (vulnerable)
FROM ubuntu:20.04

# After (patched)
FROM ubuntu:22.04
```

### **2. Multi-Stage Builds**
```dockerfile
# Use minimal base images for production
FROM node:18-alpine AS builder
COPY . .
RUN npm ci --only=production

FROM node:18-alpine AS runtime
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
USER 1001
```

### **3. Distroless Images**
```dockerfile
# Ultra-minimal images with no package manager
FROM gcr.io/distroless/nodejs:18
COPY --from=builder /app .
```

---

## **Security Policy Template**

```markdown
# Container Security Policy

## Vulnerability Severity Levels

| Severity | Action Required | Timeline |
|----------|----------------|----------|
| **CRITICAL** | Block deployment | Immediate fix required |
| **HIGH** | Create ticket | Fix within 7 days |
| **MEDIUM** | Monitor | Fix within 30 days |
| **LOW** | Track | Fix in next scheduled maintenance |

## Scanning Requirements

- [ ] All images scanned before deployment
- [ ] Automated scanning in CI/CD pipeline
- [ ] Weekly re-scans of production images
- [ ] Vulnerability database updated daily

## Approval Process

1. Developer runs security scan locally
2. CI/CD pipeline scans on PR creation
3. Security team approves HIGH+ vulnerability exceptions
4. Deployment blocked if CRITICAL vulnerabilities present
```

---

## **Best Practices**

### **1. Regular Updates**
- Rebuild images monthly with latest base image patches
- Monitor security advisories for your dependencies
- Use automated dependency update tools (Dependabot, Renovate)

### **2. Minimal Images**
- Use Alpine Linux or distroless base images
- Remove unnecessary packages and tools
- Use multi-stage builds to exclude build dependencies

### **3. Runtime Security**
- Run containers as non-root users
- Use read-only root filesystems where possible
- Implement resource limits and security contexts

### **4. Image Provenance**
- Use official images from trusted registries
- Verify image signatures when available
- Maintain internal registry with approved images

---

## **Next Steps**

After completing this security scanning exercise:

1. ✅ **Document findings** - Create security scan reports
2. 🔄 **Implement fixes** - Update any vulnerable images
3. 🤖 **Automate scanning** - Add to CI/CD pipeline
4. 📊 **Regular monitoring** - Schedule weekly scans
5. 📝 **Security policy** - Define organization standards