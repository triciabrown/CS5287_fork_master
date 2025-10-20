# Quick Reference Card

## Default Commands (AWS Production)

### Deploy Everything
```bash
./deploy.sh
```
**What it does:**
- Provisions AWS infrastructure (Terraform)
- Configures 5-node Docker Swarm cluster (Ansible)
- Deploys all applications
- **Time:** ~5-7 minutes
- **Cost:** Uses AWS Free Tier

### Teardown Everything
```bash
./teardown.sh
```
**What it does:**
- Removes all applications
- Destroys ALL AWS resources
- Cleans up local files
- **Time:** ~2-3 minutes
- **Important:** This destroys everything!

## Development Commands (Local)

### Local Deploy
```bash
MODE=local ./deploy.sh
```
**What it does:**
- Single-node Swarm on local machine
- No AWS resources
- Fast testing
- **Time:** ~2 minutes

### Local Teardown
```bash
MODE=local ./teardown.sh
```
**What it does:**
- Removes local stack only
- Preserves local Swarm (optional)
- No AWS interaction

## Summary

| Command | Mode | What Happens |
|---------|------|--------------|
| `./deploy.sh` | **AWS (default)** | Provisions infrastructure + deploys apps |
| `./teardown.sh` | **AWS (default)** | Destroys ALL AWS resources |
| `MODE=local ./deploy.sh` | Local override | Local single-node deployment |
| `MODE=local ./teardown.sh` | Local override | Local cleanup only |

## Assignment Submission

For CA2 grading, the default commands are:

**Deploy:**
```bash
cd plant-monitor-swarm-IaC
./deploy.sh
```

**Teardown:**
```bash
cd plant-monitor-swarm-IaC
./teardown.sh
```

These commands meet the requirement:
> "Provide a single command (or Makefile target) to apply the full stack and another to delete it."

✅ **Single command** provisions infrastructure and deploys applications  
✅ **Single command** destroys all resources  
✅ **Fully idempotent** - can run multiple times safely  
✅ **Declarative** - all configuration in YAML files
