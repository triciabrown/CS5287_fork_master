# Scaling Test Script Fixes

**Date:** October 18, 2025  
**File:** `scaling-test.sh`

## Issues Identified

### 1. SSH Banner Pollution
**Problem:** SSH connections were showing Ubuntu welcome messages mixed with command output:
```
Total messages in topic: Welcome to Ubuntu 22.04.5 LTS...
```

**Root Cause:** SSH by default shows MOTD (Message of the Day) and login banners

**Fix:**  
- Added `-q` (quiet mode) to suppress warnings
- Added `-T` (disable pseudo-terminal) to suppress login messages
- Added `2>/dev/null` to redirect stderr

**Example:**
```bash
# Before
ssh -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP} 'command'

# After
ssh -q -T -i ~/.ssh/docker-swarm-key ubuntu@${MANAGER_IP} 'command' 2>/dev/null
```

### 2. Variable Parsing with Newlines
**Problem:** Variables contained newlines causing integer comparison errors:
```
./scaling-test.sh: line 77: [: 0
0: integer expression expected
```

**Root Cause:** SSH output included newlines that were captured in variables

**Fix:** Trim whitespace and newlines using `tr` and `xargs`:
```bash
# Before
COUNT=$(ssh ... 'command')

# After  
COUNT=$(ssh ... 'command')
COUNT=$(echo "$COUNT" | tr -d '\n\r' | xargs)
```

### 3. Integer Validation Before Comparison
**Problem:** Bash tried to compare non-numeric strings as integers

**Fix:** Added regex validation before arithmetic:
```bash
# Before
if [ "$LOG_COUNT" -gt 0 ]; then

# After
if [[ "$LOG_COUNT" =~ ^[0-9]+$ ]] && [ "$LOG_COUNT" -gt 0 ]; then
```

### 4. Service Name Filter
**Problem:** `--filter name=sensor` returned no results

**Root Cause:** Full service name is `plant-monitoring_sensor` (includes stack prefix)

**Fix:** Changed all filters:
```bash
# Before
docker service ls --filter name=sensor

# After
docker service ls --filter name=plant-monitoring_sensor
```

## Testing Results

### Before Fixes
- SSH banners polluted all output
- Variables contained malformed data
- Integer comparisons failed
- Service queries returned empty results

### After Fixes
- Clean output without SSH messages
- Variables properly trimmed
- All comparisons work correctly
- Service queries return correct data

## Files Modified
1. `scaling-test.sh` - All SSH commands updated with `-q -T` and `2>/dev/null`
2. `scaling-test.sh` - Variable trimming added to `count_messages()` function
3. `scaling-test.sh` - Integer validation added before comparisons
4. `scaling-test.sh` - Service filters updated to full name

## Validation
Run the script to verify:
```bash
./scaling-test.sh
```

Expected output:
- No Ubuntu welcome messages
- Clean service status tables
- Proper message counts
- Successful scaling operations

## Related Issues

### Processor Service Crash
Noticed during testing: `plant-monitoring_processor` shows 0/1 replicas

**Investigation needed:**
```bash
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP> \
  'docker service logs plant-monitoring_processor --tail 50'
```

**Possible causes:**
- MongoDB connection issues (authentication)
- Kafka connection timeout
- Missing secrets
- Container startup error

**Note:** This is separate from scaling script issues and should be investigated independently.
