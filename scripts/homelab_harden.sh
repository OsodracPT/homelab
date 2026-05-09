#!/usr/bin/env bash
# homelab-harden.sh — Idempotent hardening script for Debian/Proxmox
#
# Usage:
#   sudo ./homelab-harden.sh
#   sudo ./homelab-harden.sh --ssh-port 2222
#   sudo ./homelab-harden.sh --no-fail2ban --no-upgrades
#   sudo ./homelab-harden.sh --skip-password   (if satoshi password already set)
#
# Fixed users: satoshi (admin), termix (bastion)
# Public key:  YubiKey FIDO2 resident key (yubikey-homelab-202602)

set -euo pipefail

# ─── Color helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Fixed users ──────────────────────────────────────────────────────────────
ADMIN_USER="satoshi"
BASTION_USER="termix"

# ─── Public keys ──────────────────────────────────────────────────────────────
# YubiKey FIDO2 resident key — for satoshi (human admin)
# Generated with: ssh-keygen -t ed25519-sk -O resident -O application=ssh:homelab
YUBIKEY_PUBLIC_KEY="sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIL3e7JF8FjxaxgpP8ATHIjgY8KkBzhtFEDD8hCQW0B1/AAAAC3NzaDpob21lbGFi yubikey-homelab-202602"

# YubiKey 2 FIDO2 resident key — backup hardware key
# Generated with: ssh-keygen -t ed25519-sk -O resident -O application=ssh:homelab
# Replace the placeholder below with your actual second YubiKey public key
YUBIKEY2_PUBLIC_KEY=""  # ← paste yubikey2_homelab.pub contents here

# ed25519 key — for termix bastion container (no passphrase, stored as Docker secret)
TERMIX_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJxtDvFjvEyys0O3bDW6xcjKA54osftDHFKsS53XEhAd termix-bastion-202602"

# ─── Defaults ─────────────────────────────────────────────────────────────────
SSH_PORT=22
INSTALL_FAIL2BAN=true
INSTALL_UNATTENDED_UPGRADES=true
SKIP_PASSWORD=false

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --ssh-port)        SSH_PORT="$2";      shift 2 ;;
    --no-fail2ban)     INSTALL_FAIL2BAN=false;            shift ;;
    --no-upgrades)     INSTALL_UNATTENDED_UPGRADES=false; shift ;;
    --skip-password)   SKIP_PASSWORD=true;                shift ;;
    *) error "Unknown argument: $1" ;;
  esac
done

# ─── Validation ───────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || error "Must run as root"

# ─── Detect distro ────────────────────────────────────────────────────────────
if grep -qi proxmox /etc/os-release 2>/dev/null || \
   grep -qi proxmox /etc/issue 2>/dev/null; then
  DISTRO="proxmox"
else
  DISTRO="debian"
fi
info "Detected distro: $DISTRO"

# ─── 1. Update package lists ──────────────────────────────────────────────────
info "Updating package lists..."
apt-get update -qq

# ─── 2. Install required packages ────────────────────────────────────────────
PACKAGES=(sudo curl wget chrony auditd)
$INSTALL_FAIL2BAN              && PACKAGES+=(fail2ban)
$INSTALL_UNATTENDED_UPGRADES   && PACKAGES+=(unattended-upgrades)

info "Installing packages: ${PACKAGES[*]}"
apt-get install -y -qq "${PACKAGES[@]}"

# ─── 3. Create admin user: satoshi ───────────────────────────────────────────
info "Ensuring admin user: $ADMIN_USER"
if ! id "$ADMIN_USER" &>/dev/null; then
  useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
  info "Created user $ADMIN_USER"
else
  usermod -aG sudo "$ADMIN_USER"
  info "User $ADMIN_USER already exists — ensured sudo membership"
fi

# Set satoshi password — required for sudo (will prompt interactively)
# If already set and you want to keep it, press Ctrl+C and re-run with --skip-password
if [[ "$SKIP_PASSWORD" != "true" ]]; then
  # Check if satoshi already has a password set
  if passwd -S "$ADMIN_USER" 2>/dev/null | grep -q " NP "; then
    info "Setting password for $ADMIN_USER (required for sudo)..."
    until passwd "$ADMIN_USER"; do
      warn "Passwords did not match or were too weak — try again"
    done
  else
    info "Password already set for $ADMIN_USER — skipping"
  fi
fi

# Set root password for emergency console access via Proxmox
# Root SSH login remains disabled — this is console-only recovery
# If root already has a password set, skip to avoid overwriting it
if passwd -S root 2>/dev/null | grep -q " NP \| L "; then
  info "Setting root password for emergency Proxmox console access..."
  until passwd root; do
    warn "Passwords did not match or were too weak — try again"
  done
else
  info "Root password already set — skipping"
fi

# ─── 4. Create bastion user: termix ──────────────────────────────────────────
info "Ensuring bastion user: $BASTION_USER"
if ! id "$BASTION_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$BASTION_USER"
  info "Created user $BASTION_USER"
else
  info "User $BASTION_USER already exists"
fi

# ─── 5. Install SSH public key for both users (idempotent) ───────────────────
install_pubkey() {
  local target_user="$1"
  local key="$2"
  local home_dir
  home_dir=$(getent passwd "$target_user" | cut -d: -f6)
  local ssh_dir="$home_dir/.ssh"
  local auth_keys="$ssh_dir/authorized_keys"

  install -d -m 700 -o "$target_user" -g "$target_user" "$ssh_dir"
  touch "$auth_keys"
  chown "$target_user:$target_user" "$auth_keys"
  chmod 600 "$auth_keys"

  if ! grep -qF "$key" "$auth_keys"; then
    echo "$key" >> "$auth_keys"
    info "Public key installed for $target_user"
  else
    info "Public key already present for $target_user — skipping"
  fi
}

install_pubkey "$ADMIN_USER"   "$YUBIKEY_PUBLIC_KEY"
install_pubkey "$ADMIN_USER"   "$TERMIX_PUBLIC_KEY"
install_pubkey "$BASTION_USER" "$YUBIKEY_PUBLIC_KEY"
install_pubkey "$BASTION_USER" "$TERMIX_PUBLIC_KEY"

# Install second YubiKey if configured
if [[ -n "$YUBIKEY2_PUBLIC_KEY" ]]; then
  install_pubkey "$ADMIN_USER"   "$YUBIKEY2_PUBLIC_KEY"
  install_pubkey "$BASTION_USER" "$YUBIKEY2_PUBLIC_KEY"
else
  warn "YUBIKEY2_PUBLIC_KEY not set — skipping second YubiKey (add it to the script when ready)"
fi

# ─── 6. Sudo configuration ────────────────────────────────────────────────────
info "Configuring sudoers..."
SUDOERS_DROP="/etc/sudoers.d/99-homelab"

cat > "$SUDOERS_DROP" <<EOF
# Managed by homelab-harden.sh — do not edit manually

# satoshi — full sudo with password
%sudo ALL=(ALL:ALL) ALL

# termix — bastion container user, passwordless sudo (no interactive password available)
$BASTION_USER ALL=(ALL:ALL) NOPASSWD: ALL

# Audit and timeout settings
Defaults timestamp_timeout=15
Defaults logfile="/var/log/sudo.log"
Defaults log_input,log_output
EOF

chmod 440 "$SUDOERS_DROP"
# Validate sudoers before applying
visudo -c -f "$SUDOERS_DROP" || error "sudoers validation failed! Check $SUDOERS_DROP"
info "Sudoers configured for $ADMIN_USER and $BASTION_USER"

# ─── 7. Harden SSH config ─────────────────────────────────────────────────────
info "Hardening SSH configuration..."
DROPIN="/etc/ssh/sshd_config.d/99-homelab-hardening.conf"

# Ensure drop-in directory exists (older Debian may not have it)
mkdir -p /etc/ssh/sshd_config.d

# Remove conflicting drop-ins (Ubuntu cloud-init ships PasswordAuthentication yes)
for f in /etc/ssh/sshd_config.d/*.conf; do
  [[ "$f" == "$DROPIN" ]] && continue
  if grep -qi "PasswordAuthentication\|PermitRootLogin\|PubkeyAuthentication" "$f" 2>/dev/null; then
    warn "Removing conflicting drop-in: $f"
    rm -f "$f"
  fi
done

# Neutralize any overrides baked into the main sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/I' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/I' /etc/ssh/sshd_config

cat > "$DROPIN" <<EOF
# Managed by homelab-harden.sh — do not edit manually
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers $ADMIN_USER $BASTION_USER
# Modern crypto only — sntrup761 covers post-quantum for OpenSSH 8.x-9.x servers
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
EOF

# Validate before reloading — avoids lockouts
sshd -t || error "SSH config validation failed! Check $DROPIN"
# Service name differs: Debian/Proxmox = sshd, Ubuntu = ssh
if systemctl is-active --quiet sshd 2>/dev/null || systemctl list-unit-files sshd.service &>/dev/null; then
  systemctl reload sshd
else
  systemctl reload ssh
fi
info "SSH hardened on port $SSH_PORT"

# ─── 8. Configure Fail2ban ────────────────────────────────────────────────────
if $INSTALL_FAIL2BAN; then
  info "Configuring Fail2ban..."
  JAIL_LOCAL="/etc/fail2ban/jail.local"
  if [[ ! -f "$JAIL_LOCAL" ]]; then
    cat > "$JAIL_LOCAL" <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = $SSH_PORT
EOF
    info "jail.local created"
  else
    info "jail.local already exists — skipping (review manually if SSH port changed)"
  fi
  systemctl enable --now fail2ban
fi

# ─── 9. Unattended upgrades ───────────────────────────────────────────────────
if $INSTALL_UNATTENDED_UPGRADES; then
  info "Enabling unattended security upgrades..."

  # Schedule: refresh lists daily, run unattended-upgrade daily, autoclean weekly
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

  # Policy: Debian security + stable-updates only.
  # On Proxmox, blacklist PVE/Ceph packages so kernel/PVE upgrades stay manual
  # (they often require host reboots and can interact with running VMs).
  # On plain Debian the blacklist patterns simply don't match anything.
  cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
// Managed by homelab-harden.sh — do not edit manually

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-updates";
};

// Belt-and-suspenders: never auto-upgrade Proxmox VE / Ceph packages.
Unattended-Upgrade::Package-Blacklist {
    "proxmox-kernel-.*";
    "pve-kernel-.*";
    "pve-manager";
    "proxmox-ve";
    "ceph";
    "ceph-.*";
};

Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

  systemctl enable --now unattended-upgrades

  # Validate the policy parses — bad syntax would silently disable upgrades
  if ! unattended-upgrade --dry-run --debug >/dev/null 2>&1; then
    warn "unattended-upgrade dry-run failed — review /etc/apt/apt.conf.d/50unattended-upgrades"
  fi
fi

# ─── 10. SSH login banner ─────────────────────────────────────────────────────
info "Setting login banner..."
cat > /etc/issue.net <<'EOF'
***************************************************************************
                            AUTHORIZED ACCESS ONLY
  Unauthorized access to this system is forbidden and will be prosecuted.
  All connections are monitored and logged.
***************************************************************************
EOF

# ─── 11. Enable auditd ────────────────────────────────────────────────────────
info "Enabling auditd..."
systemctl enable --now auditd

# ─── 12. Ensure time sync ─────────────────────────────────────────────────────
info "Ensuring time synchronization..."
systemctl enable --now chrony 2>/dev/null || \
  systemctl enable --now systemd-timesyncd 2>/dev/null || \
  warn "Could not enable time sync service — check manually"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Hardening complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
printf "  %-20s %s\n" "Admin user:"   "$ADMIN_USER"
printf "  %-20s %s\n" "Bastion user:" "$BASTION_USER"
printf "  %-20s %s\n" "SSH port:"     "$SSH_PORT"
printf "  %-20s %s\n" "Distro:"       "$DISTRO"
echo ""
warn "VERIFY access in a second terminal BEFORE closing this session!"
warn "  ssh -p $SSH_PORT $ADMIN_USER@<host>"
warn "  ssh -p $SSH_PORT $BASTION_USER@<host>"
echo ""