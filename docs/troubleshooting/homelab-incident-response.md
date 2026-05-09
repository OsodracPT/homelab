# Homelab: Incident Response Cheat Sheet

## System completely unresponsive (SSH still works)

### Step 1 — what's the kernel saying?
```bash
dmesg | tail -50
dmesg | grep -iE 'error|hung|timeout|blocked|oom|nfs|iscsi'
```

### Step 2 — is something in D-state (uninterruptible sleep)?
```bash
# If ps aux hangs, something is blocked at kernel level
# Common causes: hung NFS, dead iSCSI, failed disk
cat /proc/loadavg          # still works even when ps hangs
cat /proc/mounts           # find suspect mounts
```

### Step 3 — force unmount suspect network share
```bash
umount -f -l /mount/point
```

### Step 4 — if system is shutting itself down
```bash
systemctl list-jobs        # see what's queued
shutdown -c                # try to cancel
# If can't cancel: sync && reboot
```

### Step 5 — nuclear option (SysRq)
```bash
echo 1 > /proc/sys/kernel/sysrq
echo w > /proc/sysrq-trigger   # dump blocked tasks to dmesg
echo s > /proc/sysrq-trigger   # sync disks
echo u > /proc/sysrq-trigger   # unmount filesystems
echo b > /proc/sysrq-trigger   # reboot
```

---

## Post-incident: read the timeline
```bash
# What happened and when
journalctl --since "yesterday" | grep -iE "error|fail|nfs|oom|killed" | head -50

# Was there a reboot?
last | head -10

# OOM killer activity?
journalctl --since "yesterday" | grep -i "oom\|killed process"
```

---

## Network share best practices

| Option | Why |
|--------|-----|
| `soft` | Won't hang forever if server dies |
| `nofail` | System boots even if share is down |
| `_netdev` | Waits for network before mounting |
| `timeo=30` | 3s timeout per retry |
| `retrans=3` | 3 retries then give up |

---

## Key log locations
| Service | Log |
|---------|-----|
| Kernel | `dmesg` or `journalctl -k` |
| Proxmox backup | `journalctl -u pve-daily-update` |
| Unattended upgrades | `/var/log/unattended-upgrades/` |
| TrueNAS | `/var/log/messages` |
| Docker | `docker logs <name>` or `/var/lib/docker/containers/*/` |
