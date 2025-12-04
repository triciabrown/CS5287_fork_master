# Secrets Management in Docker Swarm

## Overview

Docker Swarm provides native secrets management similar to Ansible Vault used in CA1. This document explains how secrets are handled securely in the CA2 implementation.

## Comparison: CA1 vs CA2 Secrets

| Aspect | CA1 (Ansible Vault) | CA2 (Docker Swarm Secrets) |
|--------|---------------------|---------------------------|
| **Storage** | Encrypted YAML file in git | Encrypted Raft log in Swarm |
| **Encryption** | AES256 with password | AES-GCM (256-bit) automatic |
| **Distribution** | Ansible decrypts during deploy | TLS-encrypted to containers |
| **Access Control** | Vault password required | Only authorized services |
| **Runtime Access** | Environment variables | Mounted files in `/run/secrets/` |
| **At Rest** | Encrypted in git | Encrypted in Swarm database |
| **In Transit** | SSH to target hosts | TLS within Swarm |
| **Rotation** | Edit and re-encrypt file | Create new secret, update service |

## How Docker Swarm Secrets Work

### 1. Secret Creation
```bash
# Create a secret from stdin
echo "my-secret-password" | docker secret create mongo_password -

# Create a secret from file
docker secret create tls_cert ./cert.pem
```

**What happens:**
- Secret is encrypted with cluster's encryption key
- Stored in Swarm's Raft log (encrypted at rest)
- Only Swarm managers can access the Raft log
- Secret content is **never** readable again (even by managers)

### 2. Secret Distribution
```yaml
# docker-compose.yml
services:
  mongodb:
    image: mongo:6.0.4
    secrets:
      - mongo_root_password
    environment:
      MONGO_INITDB_ROOT_PASSWORD_FILE: /run/secrets/mongo_root_password

secrets:
  mongo_root_password:
    external: true
```

**What happens:**
- When service starts, Swarm manager sends secret over **mutual TLS**
- Secret is mounted as a file in `/run/secrets/` (in-memory tmpfs)
- Only the specific container can read the file
- Secret is **never written to disk**

### 3. Secret Usage in Containers
```javascript
// In application code (processor/app.js)
const fs = require('fs');

// Read connection string from secret file
const mongoConnString = fs.readFileSync(
  '/run/secrets/mongodb_connection_string', 
  'utf8'
).trim();
```

**Security benefits:**
- ✅ Not in environment variables (visible via `docker inspect`)
- ✅ Not in container filesystem (persists after container death)
- ✅ Only in memory (tmpfs mount)
- ✅ Destroyed when container stops

## Our Implementation

### Secrets Created

| Secret Name | Purpose | Used By |
|-------------|---------|---------|
| `mongo_root_username` | MongoDB admin user | mongodb |
| `mongo_root_password` | MongoDB admin password | mongodb |
| `mongo_app_username` | Application database user | processor |
| `mongo_app_password` | Application database password | processor |
| `mongodb_connection_string` | Full MongoDB connection URI | processor |
| `mqtt_username` | MQTT broker user | mosquitto, processor |
| `mqtt_password` | MQTT broker password | mosquitto, processor |

### Creation Process

```bash
# Run the secrets creation script
cd CA2/plant-monitor-swarm-IaC
./scripts/create-secrets.sh
```

This script:
1. Checks if Docker Swarm is active
2. Generates secure random passwords using `openssl`
3. Creates each secret in Swarm's encrypted store
4. Optionally saves backup to `.credentials` (if `SAVE_CREDENTIALS_FILE=true`)

### Security Best Practices

#### ✅ DO:
- Use Docker Swarm Secrets for all sensitive data
- Rotate secrets periodically
- Use strong random passwords (32+ characters)
- Keep `.credentials` file secure (chmod 600) if created
- Add `.credentials` to `.gitignore` (already done)
- Use `external: true` for secrets in compose file

#### ❌ DON'T:
- Store secrets in environment variables
- Commit `.credentials` file to git
- Use hardcoded passwords in code
- Share secrets between unrelated services
- Store secrets in Docker images

## Secret Rotation

To rotate a secret:

```bash
# 1. Create new secret with different name
echo "new-password" | docker secret create mongo_password_v2 -

# 2. Update service to use new secret
docker service update \
  --secret-rm mongo_password \
  --secret-add mongo_password_v2 \
  plant-monitoring_mongodb

# 3. Remove old secret
docker secret rm mongo_password
```

## Troubleshooting

### Viewing Secrets
```bash
# List all secrets
docker secret ls

# Inspect secret metadata (NOT the value)
docker secret inspect mongo_root_password

# Check which services use a secret
docker secret inspect mongo_root_password --format '{{.Spec.Name}}: {{.Spec.Labels}}'
```

### Common Issues

**Secret not found:**
```
Error: secret not found: mongo_root_password
```
**Solution:** Run `./scripts/create-secrets.sh` before deploying

**Cannot update secret:**
```
Error: secret is in use by the following service: mongodb
```
**Solution:** Secrets are immutable. Create a new secret with a different name.

**Permission denied reading /run/secrets:**
```
Error: EACCES: permission denied, open '/run/secrets/mongo_password'
```
**Solution:** Ensure service has the secret declared in compose file.

## Comparison with Alternative Approaches

### Environment Variables ❌
```yaml
environment:
  MONGO_PASSWORD: "hardcoded-password"  # BAD!
```
**Problems:**
- Visible in `docker inspect`
- Visible in logs if printed
- Visible in process list
- Stored in container metadata

### Config Files in Images ❌
```dockerfile
COPY secrets.json /app/secrets.json  # BAD!
```
**Problems:**
- Baked into image layers
- Visible to anyone with image access
- Can't rotate without rebuilding

### Docker Swarm Secrets ✅
```yaml
secrets:
  - mongo_password  # GOOD!
```
**Benefits:**
- Encrypted at rest and in transit
- Scoped to specific services
- Not in container metadata
- Destroyed with container

## Migration from CA1

CA1 used Ansible Vault to encrypt secrets in `group_vars/all/vault.yml`:

```yaml
# CA1: group_vars/all/vault.yml (encrypted with ansible-vault)
---
mongo_root_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  encrypted_content_here
```

CA2 uses Docker Swarm Secrets instead:

```bash
# CA2: Create secrets in Swarm
echo "same-password-as-CA1" | docker secret create mongo_root_password -
```

**Both approaches provide:**
- ✅ Encryption at rest
- ✅ Secure distribution
- ✅ Access control
- ✅ Audit trail

**Key difference:**
- CA1: Secrets in version control (encrypted)
- CA2: Secrets in Swarm cluster (not in git)

## References

- [Docker Secrets Documentation](https://docs.docker.com/engine/swarm/secrets/)
- [Manage sensitive data with Docker secrets](https://docs.docker.com/engine/swarm/secrets/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Secrets in Compose files](https://docs.docker.com/compose/compose-file/09-secrets/)

## Summary

Docker Swarm Secrets provide **production-grade** secrets management that is:
- **Secure**: Encrypted at rest and in transit
- **Convenient**: Native Docker integration
- **Auditable**: All secret operations logged
- **Flexible**: Support for rotation and updates

This is the **correct approach** for CA2, directly comparable to the Ansible Vault approach used in CA1.

The `.credentials` file is only a **backup** and should be:
1. Protected with `chmod 600`
2. Excluded from git (via `.gitignore`)
3. Deleted after deployment verification (optional)

**The actual secrets live securely in Docker Swarm's encrypted storage.**
