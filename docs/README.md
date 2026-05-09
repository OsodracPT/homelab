# Homelab Docs

Operational notes for the homelab — split between one-time setup walkthroughs and reach-for-it-during-an-incident troubleshooting.

## Setup

Step-by-step provisioning guides. Read top-to-bottom when standing something up.

- [Debian 12 VM — Remote Desktop with noVNC](setup/debian-vm-novnc.md) — XFCE + TigerVNC + noVNC for browser-based remote desktop, fronted by Pangolin. Includes Signal Desktop and Chromium for WhatsApp Web.
- [Second YubiKey Setup — Backup Hardware Key](setup/yubikey-second-key-setup.md) — Provisioning a second FIDO2 resident key so either YubiKey can authenticate to all homelab machines.

## Troubleshooting

Cheat sheets for when things break. Each one starts with quick diagnosis commands and ends with a fix.

- [Homelab Incident Response](troubleshooting/homelab-incident-response.md) — General-purpose first-response checklist when a host is unresponsive: dmesg, D-state processes, force-unmounts, SysRq nuclear option, and post-incident timeline reconstruction.
- [Proxmox — Disk Space](troubleshooting/proxmox-disk-space.md) — Diagnose and free space on PVE hosts and inside VMs: LVM thin-pool checks, local backup dump cleanup, Docker log bloat, and global Docker log rotation.
- [Proxmox — NFS Hang Recovery](troubleshooting/proxmox-nfs-hang-recovery.md) — Recover from frozen NFS mounts that hang `ps`, the web UI, and SSH. Force-unmount, clear stuck VM locks, restart PVE services, and prevent recurrence with `fstab` mounts.
- [TrueNAS — NFS Troubleshooting](troubleshooting/truenas-nfs-troubleshooting.md) — Pool health, NFS session-cache exhaustion, slow I/O, SMART checks, and verifying which clients are actually hitting NFS.
