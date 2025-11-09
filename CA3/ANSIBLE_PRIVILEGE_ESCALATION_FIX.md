# Ansible Privilege Escalation Timeout - Root Cause and Fix

## Problem
When running `./deploy.sh`, Ansible playbook fails with:
```
[ERROR]: Task failed: Timeout (12s) waiting for privilege escalation prompt:
fatal: [worker4]: UNREACHABLE! => {"changed": false, "msg": "Task failed: Timeout (12s) waiting for privilege escalation prompt:", "unreachable": true}
```

## Root Cause

### Why We Need Privilege Escalation
The playbook has `become: yes` set at the **play level** (lines 8 and 77 in `setup-swarm.yml`), which means **ALL tasks** try to use sudo. This is necessary for tasks like:
- Starting/managing Docker service (`service: name=docker`)
- Running `ethtool` to disable network offloading
- Installing packages or modifying system configuration

### Why It Times Out
However, some tasks **don't need sudo**:
- `docker info` - The ubuntu user is already in the `docker` group
- `docker swarm join-token` - Docker socket permissions allow this
- `docker swarm join` - Swarm operations don't need root

When `become: yes` is set globally, Ansible tries to establish a sudo session for EVERY task. Sometimes:
1. The sudo session hasn't been initialized yet
2. PAM/sudo configuration delays the response
3. Ansible waits for a password prompt that never comes (passwordless sudo is configured, but the timing is off)

This causes the **12-second timeout** defined in `ansible.cfg`:
```ini
[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
become_timeout = 60  # This is the max wait time
```

And at the play level:
```yaml
vars:
  ansible_become_timeout: 30  # Overrides to 30 seconds
```

But the actual timeout error shows **12 seconds**, which suggests a lower-level SSH/PAM timeout is triggering first.

## Solution

Add `become: no` to tasks that **don't require sudo**. Specifically:

### Manager Tasks (lines 37-56)
```yaml
- name: Check if Swarm is already initialized
  command: docker info
  become: no  # ← Added

- name: Initialize Docker Swarm
  command: docker swarm init --advertise-addr {{ ansible_default_ipv4.address }}
  become: no  # ← Added

- name: Get manager join token
  command: docker swarm join-token manager -q
  become: no  # ← Added

- name: Get worker join token
  command: docker swarm join-token worker -q
  become: no  # ← Added
```

### Worker Tasks (lines 89-157)
```yaml
- name: Wait for Docker daemon to be ready
  command: docker info
  become: no  # ← Added

- name: Check if already part of a swarm
  command: docker info
  become: no  # ← Added

- name: Leave existing swarm if in wrong cluster
  command: docker swarm leave --force
  become: no  # ← Added

- name: Re-check swarm status after leaving
  command: docker info
  become: no  # ← Added

- name: Join swarm as worker
  command: docker swarm join ...
  become: no  # ← Added
```

## Why This Works

1. **Docker Group Permissions**: The ubuntu user is added to the `docker` group during cloud-init:
   ```bash
   usermod -aG docker ubuntu
   ```
   This allows running Docker commands without sudo.

2. **Selective Privilege Escalation**: Only tasks that NEED sudo (like managing services, running ethtool, etc.) use it. Docker API operations don't need it.

3. **Faster Execution**: No waiting for sudo session establishment on tasks that don't need it.

4. **More Reliable**: Avoids PAM/sudo timing issues that cause intermittent failures.

## Alternative Solutions (Not Recommended)

### Option 1: Increase timeout globally
```yaml
vars:
  ansible_become_timeout: 120  # Wait longer
```
**Problem**: Doesn't fix the root cause, just masks it. Still slower.

### Option 2: Disable become at play level
```yaml
- name: Configure workers
  hosts: workers
  become: no  # Don't use sudo by default
```
**Problem**: Then you need `become: yes` on EVERY task that needs sudo. More verbose.

### Option 3: Run all Docker commands with sudo
```yaml
- name: Check swarm status
  command: sudo docker info
```
**Problem**: Unnecessary privilege escalation. Bad security practice.

## Verification

After applying the fix, the playbook should:
1. ✅ Not timeout on `docker info` commands
2. ✅ Complete worker join tasks without sudo delays
3. ✅ Still properly execute tasks that DO need sudo (service management, ethtool)

Run `./deploy.sh` to verify the fix works.

## Files Modified
- `ansible/setup-swarm.yml` - Added `become: no` to 9 tasks that don't need sudo
