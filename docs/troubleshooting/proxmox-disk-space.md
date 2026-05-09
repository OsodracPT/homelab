# Proxmox: Disk Space Troubleshooting

## Quick health check
```bash
df -h                    # filesystem usage
lvs                      # LVM volumes (check Data% on thin pool)
vgs                      # VG free space
du -sh /var/lib/vz/*     # what's in local storage
du -sh /var/log          # log size
```

## Warning thresholds
| Item | Warning | Critical |
|------|---------|----------|
| `/` (pve-root) | >70% | >85% |
| LVM thin pool Data% | >80% | >90% |
| VG free space | <20GB | <10GB |
| VM disk (lvs) | >85% | >95% |

## Local backup dumps eating space
```bash
ls -lh /var/lib/vz/dump/
# Delete old ones manually or configure prune in storage settings
```

---

## VM disk nearly full (check from Proxmox host)
```bash
qm guest exec <VMID> -- df -h
# or SSH directly into the VM
```

---

## Docker cleanup (inside Ubuntu/Docker VMs)

### Quick overview
```bash
docker system df
du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null | sort -rh | head -10
```

### Safe full cleanup (won't touch running containers)
```bash
docker system prune -af --volumes
```

### Truncate a specific huge log (no downtime)
```bash
truncate -s 0 /var/lib/docker/containers/<container-id>/<container-id>-json.log
```

### Prevent log bloat — set global log rotation
`/etc/docker/daemon.json`:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
```
```bash
systemctl restart docker
```
> Applies to newly started containers only. Existing containers respect it on next restart.

---

## LVM thin pool nearly full
```bash
# Check actual usage per VM disk
lvs -a pve

# Extend thin pool if VG has free space
lvextend -l +100%FREE pve/data
```
