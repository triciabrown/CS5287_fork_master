# MongoDB Security Fix - Docker Secrets Implementation

## Problem Identified

The MongoDB initialization configuration had hardcoded credentials (`plantapp`/`plantpass`) instead of using Docker secrets. This created a security vulnerability and prevented the processor from connecting.

## Root Cause

1. **Original Issue**: `create-configs.sh` created a MongoDB init config with hardcoded credentials
2. **Mismatch**: Docker secrets contained different credentials (`plant_app`/`plantapp456`)
3. **Result**: Processor authentication failures - user `plant_app` not found in database

## Solution Implemented

### 1. Removed MongoDB Init Config Approach

**Why**: MongoDB's `/docker-entrypoint-initdb.d/` scripts run before Docker secrets are fully available, making it impossible to read credentials at init time without using EOF logic or embedded scripts.

**Changes**:
- Removed `mongodb_init_config` from `docker-compose.yml`
- Simplified `create-configs.sh` to only create Mosquitto and Home Assistant configs
- All MongoDB user creation now handled by `verify_mongodb_users()` function

### 2. Centralized User Management in deploy-all.sh

**Function**: `verify_mongodb_users()`

**Responsibilities**:
- Waits for MongoDB container to be running
- Finds which worker node MongoDB is running on
- Reads credentials from Docker secrets (`/run/secrets/mongo_*`)
- Creates application user if it doesn't exist
- Restarts processor service to pick up new credentials

**Security Benefits**:
- ✅ No hardcoded credentials anywhere in codebase
- ✅ All credentials read from Docker secrets at runtime
- ✅ Works for both fresh deployments and existing installations
- ✅ Handles multi-node Swarm deployments correctly

### 3. Updated Files

#### `/CA4/cloud-site/scripts/create-configs.sh`
```bash
# MongoDB Initialization - REMOVED
# NOTE: MongoDB user creation is now handled by verify_mongodb_users() in deploy-all.sh
# This ensures users are created with credentials from Docker secrets
echo "ℹ MongoDB users will be created by deploy-all.sh verify_mongodb_users()"
```

#### `/CA4/cloud-site/docker-compose.yml`
```yaml
mongodb:
  # Removed configs section - no init script needed
  secrets:
    - mongo_root_username
    - mongo_root_password
    - mongo_app_username
    - mongo_app_password
```

#### `/CA4/scripts/deploy-all.sh`
- `verify_mongodb_users()` function reads all credentials from secrets
- Executes on the actual node where MongoDB is running
- Creates user with proper authentication

## Testing Results

### Before Fix
```
plant-monitoring_processor    0/1    Authentication failed
MongoDB Error: User 'plant_app' not found
```

### After Fix
```
plant-monitoring_processor    1/1    Running
✅ All services connected successfully
✅ MongoDB user 'plant_app' created
✅ Processor publishing MQTT discovery messages
```

## Future Deployments

For future fresh deployments, the flow is now:

1. **Terraform** → Deploy infrastructure
2. **Swarm Init** → Initialize cluster
3. **create-secrets.sh** → Create Docker secrets with credentials
4. **create-configs.sh** → Create simple configs (Mosquitto, Home Assistant)
5. **docker stack deploy** → Deploy services
6. **verify_mongodb_users()** → Create MongoDB user from secrets
7. **Processor starts** → Connects successfully

## Security Checklist

- [x] No hardcoded credentials in any script
- [x] All MongoDB credentials read from Docker secrets
- [x] Root credentials use secrets (not hardcoded)
- [x] App credentials use secrets (not hardcoded)
- [x] Connection string uses secrets
- [x] Works across multi-node Swarm deployments
- [x] Automatic user verification on every deployment

## Key Principle

**No EOF Logic in Scripts**: All configuration is now either:
1. Simple single-line configs (Mosquitto, Home Assistant)
2. Dynamic user creation via direct `mongosh` commands in `deploy-all.sh`

This keeps the codebase clean, maintainable, and secure.

---

**Status**: ✅ FIXED - All services running, processor connected to MongoDB with proper credentials from secrets
**Date**: November 23, 2025
