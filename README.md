# homelab

Infrastructure documentation, hardening scripts, and runbooks for my personal homelab.

---

## Overview

This repo contains everything needed to provision, harden, and maintain machines in my homelab. The goal is that any new machine — Proxmox host or Debian/Ubuntu VM — can be fully configured by running a single script.

### Infrastructure

| Layer | Technology |
|---|---|
| Hypervisor | Proxmox |
| VMs | Debian / Ubuntu |
| Bastion host | Termix (Docker container) |
| SSH auth | YubiKey 5 FIDO2 resident keys |
| Admin user | `satoshi` |
| Bastion user | `termix` |

