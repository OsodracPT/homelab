# Proxmox: NFS Hang Recovery

## Symptoms
- `ps aux` hangs
- Web UI unreachable
- SSH slow or unresponsive
- `dmesg` shows: `nfs: server X.X.X.X not responding, still trying`
- `dmesg` shows: `task blocked for more than 122 seconds`

## Diagnosis
```bash
dmesg | tail -50
dmesg | grep -iE 'nfs|hung|blocked|timeout'
cat /proc/mounts | grep nfs
```

## Fix: Force unmount the frozen NFS share
```bash
# -f = force, -l = lazy detach even with busy processes
umount -f -l /mnt/pve/<storage-name>

# Verify it's gone
cat /proc/mounts | grep nfs

# ps should work again now
ps aux | grep vzdump
```

## Clean up after the backup job
```bash
qm list              # find the VM that was being backed up
qm unlock <VMID>     # remove stuck lock
pct unlock <VMID>    # for containers

# Remove leftover snapshot if backup was snapshot-mode
qm listsnapshot <VMID>
qm delsnapshot <VMID> vzdump
```

## Restart PVE services
```bash
systemctl restart pvedaemon pveproxy pvestatd
```

> If systemd shows "Transaction is destructive" errors, a shutdown is already in progress.
> Cancel it with `shutdown -c` or just run `reboot` cleanly.

---

## Prevention: Use fstab instead of PVE-managed NFS

Remove NFS from PVE storage, add to `/etc/fstab`:
```
192.168.X.X:/export/path  /mnt/pve/<name>  nfs  soft,vers=4.2,timeo=30,retrans=3,_netdev,nofail  0  0
```
Re-add as **Directory** storage in PVE UI pointing to the same path.

Key options:
| Option | Effect |
|--------|--------|
| `soft` | Times out instead of hanging forever |
| `timeo=30` | 3 second timeout per retry |
| `retrans=3` | 3 retries before giving up |
| `nofail` | Proxmox boots even if NFS is down |
| `_netdev` | Waits for network before mounting |
