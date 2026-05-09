# TrueNAS: NFS Troubleshooting

## Quick health check
```bash
zpool status pool          # pool health + errors
zpool list                 # usage
last | head -10            # recent reboots/crashes
service nfsd status        # NFS daemon running?
showmount -a               # active NFS clients
```

## NFS session cache exhaustion
Symptom: `/var/log/messages` flooded with:
```
nfsrv_cache_session: no session IPaddr=X.X.X.X
```
Check scale of the problem:
```bash
nfsstat -s | grep -A3 "Cache"
# High "Misses" = session cache being overwhelmed
```
Fix — increase session cache size permanently:
```bash
echo 'vfs.nfsd.sessionhashsize=256' >> /boot/loader.conf
# Takes effect on next reboot
```

## Pool errors / slow I/O
```bash
zpool status pool           # look for DEGRADED, errors, slow devices
zpool clear pool            # clear transient error counters after investigation

# SMART check on a specific drive
smartctl -a /dev/da0 | grep -E "SMART overall|Reallocated|Pending|Uncorrectable|Power_On_Hours|Temperature"
```

> Slow I/O alerts at shutdown/reboot time are usually normal (cache flushing).
> Slow I/O alerts during normal operation = investigate drives immediately.

## Scrub manually
```bash
zpool scrub pool
zpool status pool           # monitor progress
```

## NFS service restart (if clients can't connect)
```bash
service nfsd restart
service mountd restart
rpcinfo -p                  # verify RPC services are registered
```

## Check what's hitting NFS
```bash
# Live traffic on NFS port
tcpdump -i any -n port 2049

# Unexpected clients hitting NFS = check firewall
# Router/unknown IPs should not appear here
```

## Recent errors
```bash
grep -iE "panic|crash|error|fail" /var/log/messages | tail -30
grep -i "nfs" /var/log/messages | tail -30
```
