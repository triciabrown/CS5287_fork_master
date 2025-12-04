# CA4 Failure Drills

This directory contains automated failure resilience testing scripts for the CA4 plant monitoring system.

## Overview

These drills demonstrate the system's resilience to various failure scenarios by:
1. Injecting controlled failures
2. Observing system behavior
3. Verifying graceful degradation
4. Restoring normal operation
5. Confirming automatic recovery

## Available Drills

### 1. VPN Failure Drill (`vpn-failure.sh`)

**Purpose:** Test resilience to VPN tunnel failures

**What it does:**
- Stops the WireGuard VPN tunnel (`wg-quick down wg0`)
- Verifies edge sensors detect connection loss
- Confirms sensors handle errors gracefully (no crashes)
- Restarts the VPN tunnel
- Verifies automatic reconnection and data flow resumption

**Usage:**
```bash
cd /home/tricia/dev/CS5287_fork_master/CA4/failure-drills
./vpn-failure.sh
```

**Requirements:**
- Must run on edge machine (where VPN client is configured)
- WireGuard VPN must be active (`wg0` interface)
- Edge sensors must be running
- Sudo access for `wg-quick` commands

**Expected Results:**
- ✅ Sensors detect VPN failure
- ✅ Sensors remain running (no crash)
- ✅ VPN restoration succeeds
- ✅ Sensors automatically reconnect
- ✅ Data flow resumes

**Duration:** ~2-3 minutes

---

### 2. Kafka Failure Drill (`kafka-failure.sh`)

**Purpose:** Test resilience to message broker failures

**What it does:**
- Scales Kafka service to 0 replicas (simulates broker crash)
- Observes processor behavior (should detect connection loss)
- Verifies processor doesn't crash during Kafka outage
- Checks edge sensor error handling
- Restarts Kafka service (scale to 1)
- Verifies consumer group reconnection
- Confirms message backlog processing

**Usage:**
```bash
cd /home/tricia/dev/CS5287_fork_master/CA4/failure-drills
./kafka-failure.sh
```

**Requirements:**
- Manager IP configured in `CA4/.manager-ip`
- SSH key at `~/.ssh/docker-swarm-key`
- Access to cloud manager node
- Kafka service running in `plant-monitoring` stack

**Expected Results:**
- ✅ Processor detects Kafka unavailability
- ✅ Processor remains running (error handling)
- ✅ Edge sensors detect publishing failures
- ✅ Kafka restarts successfully (~30-60s)
- ✅ Consumer group auto-reconnects
- ✅ Message backlog processed
- ✅ Zero data loss

**Duration:** ~3-4 minutes

---

### 3. Network Partition Drill (`network-partition.sh`)

**Purpose:** Test resilience to network-layer failures

**What it does:**
- Creates network partition using iptables DROP rules
- Blocks outbound traffic to cloud gateway (10.20.0.1)
- Blocks traffic through VPN tunnel interface (wg0)
- Observes sensor error handling during partition
- Removes iptables rules to restore connectivity
- Verifies automatic recovery

**Usage:**
```bash
cd /home/tricia/dev/CS5287_fork_master/CA4/failure-drills
./network-partition.sh
```

**Requirements:**
- Must run on edge machine
- Sudo access for iptables manipulation
- WireGuard VPN active
- iptables command available

**Expected Results:**
- ✅ Network partition successfully created
- ✅ Sensors detect connection failures
- ✅ Sensors remain running during partition
- ✅ VPN tunnel survives (interface stays up)
- ✅ Connectivity restored by removing rules
- ✅ Sensors automatically reconnect

**Simulates:**
- Firewall misconfiguration
- Cloud provider network issues
- ISP routing problems
- DDoS protection blocking traffic

**Duration:** ~2-3 minutes

---

## Drill Comparison

| Drill | Failure Type | Impact Scope | Recovery Method | Data Loss |
|-------|--------------|--------------|-----------------|-----------|
| **VPN Failure** | VPN tunnel down | Edge-to-cloud only | VPN restart | None (Kafka queues) |
| **Kafka Failure** | Message broker down | All data flow | Service restart | None (persistence) |
| **Network Partition** | Network layer block | Edge-to-cloud only | Remove iptables | None (Kafka queues) |

## Key Resilience Characteristics Demonstrated

### 1. Graceful Degradation
- Services handle failures without crashing
- Error messages logged appropriately
- Retry logic with backoff implemented

### 2. Service Isolation
- Kafka failure doesn't crash processor
- VPN failure doesn't affect cloud services
- Edge failures don't cascade to cloud

### 3. Automatic Recovery
- Services reconnect when connectivity restored
- No manual intervention required
- Consumer groups rebalance automatically

### 4. Data Preservation
- Kafka retains messages during outages
- Message backlog processed after recovery
- Zero data loss in all scenarios

### 5. Monitoring & Observability
- Clear error messages in logs
- Service health visible in Docker Swarm
- Network statistics available (WireGuard, iptables)

## Drill Logs

Each drill creates a log file in this directory:
- `vpn-failure-drill.log`
- `kafka-failure-drill.log`
- `network-partition-drill.log`

Logs include:
- Timestamps for all events
- Pre-flight check results
- Baseline metrics
- Failure observations
- Recovery verification
- Summary report

## Best Practices

### Before Running Drills
1. Ensure all services are healthy
2. Verify end-to-end data flow is working
3. Note current system state
4. Have monitoring dashboard open (if available)

### During Drills
1. Don't interrupt drills mid-execution
2. Let automated recovery complete
3. Observe service logs in real-time (optional)
4. Note any unexpected behavior

### After Drills
1. Review drill logs for errors
2. Verify all services are healthy
3. Check data flow resumed normally
4. Document any issues discovered

## Troubleshooting

### VPN Failure Drill Issues

**VPN won't restart:**
```bash
sudo wg-quick down wg0
sudo wg-quick up wg0
```

**Permission denied:**
```bash
sudo -v  # Refresh sudo credentials
```

### Kafka Failure Drill Issues

**Cannot connect to manager:**
```bash
# Verify manager IP
cat /home/tricia/dev/CS5287_fork_master/CA4/.manager-ip

# Test SSH
ssh -i ~/.ssh/docker-swarm-key ubuntu@$(cat /home/tricia/dev/CS5287_fork_master/CA4/.manager-ip) "docker service ls"
```

**Kafka won't start:**
```bash
# Check Kafka logs on manager
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP> \
  "docker service logs plant-monitoring_kafka --tail 50"

# Force update
ssh -i ~/.ssh/docker-swarm-key ubuntu@<MANAGER_IP> \
  "docker service update --force plant-monitoring_kafka"
```

### Network Partition Drill Issues

**iptables rules persist:**
```bash
# List rules
sudo iptables -L OUTPUT -n -v

# Remove specific rule
sudo iptables -D OUTPUT -d 10.20.0.1 -j DROP
sudo iptables -D OUTPUT -o wg0 -j DROP

# Flush all OUTPUT rules (use carefully)
sudo iptables -F OUTPUT
```

**No sudo access:**
```bash
# Add user to sudo group
sudo usermod -aG sudo $USER
# Then logout and login again
```

## Safety Features

All drill scripts include:

1. **Pre-flight checks** - Verify prerequisites before starting
2. **Cleanup handlers** - Restore state if interrupted (Ctrl+C)
3. **Verification steps** - Confirm recovery before completing
4. **Detailed logging** - Full audit trail of all actions
5. **Error handling** - Graceful failure if issues detected

## Integration with Runbook

These drills validate the procedures documented in the RUNBOOK.md:
- Detection methods work as described
- Recovery procedures are accurate
- Verification steps confirm resolution
- Timing estimates are realistic

## Recommendations

1. **Run drills regularly** - Monthly or after major changes
2. **Vary drill timing** - Test during different load conditions
3. **Document findings** - Note any unexpected behavior
4. **Update procedures** - Refine runbook based on drill results
5. **Automate monitoring** - Implement alerts for failure conditions

## Related Documentation

- `../RUNBOOK.md` - Incident response procedures
- `../NETWORK_ARCHITECTURE.md` - Network topology and segmentation
- `../data-flow-diagram.puml` - Data flow visualization
- `../README.md` - Overall system documentation

---

**Note:** These drills are designed for testing and demonstration purposes. Always ensure you have a way to restore services if something goes wrong.
