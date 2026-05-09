# CLAUDE.md — homelab repo guide

Personal homelab: provisioning + hardening scripts and ops runbooks. The goal is that any new machine (Proxmox host or Debian/Ubuntu VM) can be fully configured by a single idempotent script.

## Layout

- `scripts/homelab_harden.sh` — idempotent hardening for Debian/Proxmox. Single source of truth for security baseline.
- `docs/setup/` — step-by-step provisioning guides (read top-to-bottom).
- `docs/troubleshooting/` — incident cheat sheets (reach for during an outage).
- `docs/README.md` — index with one-line hooks per doc. Keep it in sync when adding/removing docs.

## Fixed-user model

Two and only two users on every machine:

| User | Role | Auth |
|---|---|---|
| `satoshi` | Human admin, sudo with password | YubiKey FIDO2 (primary + backup) |
| `termix` | Bastion container user, `NOPASSWD: ALL` sudo | ed25519 key stored as Docker secret |

Don't introduce a third user without a clear reason. The hardening script enforces this list via `AllowUsers`.

## SSH auth

- Primary: `sk-ssh-ed25519@openssh.com` resident keys on YubiKey 5 (FIDO2, `application=ssh:homelab`, PIN+touch).
- Backup: a second YubiKey provisioned the same way. Public key lives in `YUBIKEY2_PUBLIC_KEY` in `homelab_harden.sh`.
- Bastion: ed25519 (no passphrase, secret-managed) so `termix` can run unattended.
- Recovery: `ssh-keygen -K` re-derives stubs from a YubiKey on any machine — no need to ship key files around.

Root SSH login is always disabled. Root password is set only for emergency Proxmox console recovery.

## Hardening script — `scripts/homelab_harden.sh`

Idempotent. Re-running is safe and is the intended way to push config changes to existing hosts.

Key flags:
- `--ssh-port N` (default 22)
- `--no-fail2ban`
- `--no-upgrades`
- `--skip-password` (when `satoshi` already has a password)

Distro detection (`/etc/os-release`, `/etc/issue`) sets `$DISTRO` to `proxmox` or `debian`. Currently informational — the rest of the logic is portable. Branch on `$DISTRO` only when behavior actually needs to differ.

Conventions when extending the script:
- **Idempotent or it doesn't ship.** Every section must be safe to re-run. Use `grep -qF` before appending; check `id user` before `useradd`; check `passwd -S` before setting passwords; etc.
- **Validate before reload.** SSH uses `sshd -t`, sudoers uses `visudo -c`, unattended-upgrades uses `--dry-run`. Never reload a service with an unvalidated config — it can lock you out.
- **Drop-ins, not edits.** Prefer `/etc/ssh/sshd_config.d/99-homelab-hardening.conf` and `/etc/sudoers.d/99-homelab` over editing the main files. The script does sweep conflicting drop-ins for SSH to handle Ubuntu cloud-init's `PasswordAuthentication yes`.
- **Explicit > implicit.** When a package default would silently change behavior, write the policy file ourselves (see the unattended-upgrades section).

## Proxmox-specific gotchas

- **NFS storage:** add via `/etc/fstab` with `soft,timeo=30,retrans=3,_netdev,nofail`, then re-add as a Directory storage in the PVE UI. Never use PVE-managed NFS — a dead NAS hangs `ps`, the web UI, and SSH. See `docs/troubleshooting/proxmox-nfs-hang-recovery.md`.
- **Unattended upgrades:** PVE/Ceph packages are explicitly blacklisted in `50unattended-upgrades`. Kernel and PVE upgrades stay manual because they need reboots and interact with running VMs. Don't remove the blacklist without a strong reason.
- **Auto-reboot is off** (`Unattended-Upgrade::Automatic-Reboot "false"`). The host runs VMs; surprise reboots are unacceptable.

## Ingress

Pangolin terminates TLS and handles auth in front of internal services (e.g. noVNC at `:6080`). The pattern: bind the service to localhost or open the port to the LAN, then add a UFW rule scoped to the Pangolin host (`ufw allow from PANGOLIN_IP to any port N`) once Pangolin is wired up.

## Doc style

- Each cheat sheet starts with diagnosis commands, ends with a fix or prevention.
- Use tables for option/flag explanations.
- Keep the `docs/README.md` index entry to one line, ~150 chars max.
- Setup guides go in `docs/setup/`, runbooks in `docs/troubleshooting/`. Don't add a third top-level subfolder without a reason.

## Don't

- Don't commit secrets. Public keys are fine; private keys, FIDO2 stubs, and Docker secrets are not.
- Don't add a third user, a third doc subfolder, or a new "framework" without an actual need — this repo stays small on purpose.
- Don't bypass the validation steps in the hardening script. A locked-out host is the worst possible failure mode.
