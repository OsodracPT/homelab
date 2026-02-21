# Second YubiKey Setup — Backup Hardware Key

Provisioning a second YubiKey as a backup so either key can authenticate to all homelab machines.

---

## Prerequisites

- First YubiKey already configured and working
- Second YubiKey (any YubiKey 5 series)
- `libfido2` installed on your client machine
- Access to all homelab servers (to deploy the new public key)

```bash
# Arch Linux
sudo pacman -S libfido2 yubikey-manager

# Verify the key is detected
ykman info
fido2-token -L
```

---

## Step 1 — Generate the Key

Unplug your first YubiKey. Plug in **only the second YubiKey**.

```bash
ssh-keygen -t ed25519-sk \
  -O resident \
  -O application=ssh:homelab \
  -O verify-required \
  -C "yubikey2-homelab-$(date +%Y%m)" \
  -f ~/.ssh/yubikey2_homelab
```

| Flag | Purpose |
|---|---|
| `-t ed25519-sk` | FIDO2-backed ed25519 key |
| `-O resident` | Stores key on YubiKey's internal slot (recoverable on any machine) |
| `-O application=ssh:homelab` | Label for the FIDO2 slot — must start with `ssh:` |
| `-O verify-required` | Requires PIN + touch (two factors) |
| `-C` | Comment embedded in the public key for identification |
| `-f` | Where to write the local stub files |

When prompted: touch the YubiKey when it blinks, then enter your FIDO2 PIN.

This creates two files:
```
~/.ssh/yubikey2_homelab      ← stub file (not the private key, just a reference)
~/.ssh/yubikey2_homelab.pub  ← public key — this goes on your servers
```

---

## Step 2 — Get the Public Key

```bash
cat ~/.ssh/yubikey2_homelab.pub
# sk-ssh-ed25519@openssh.com AAAA... yubikey2-homelab-YYYYMM
```

Copy this output — you'll need it for the next steps.

---

## Step 3 — Deploy to Existing Servers

For each server already running in your homelab, append the new public key to `authorized_keys`. Use your **first YubiKey** to authenticate while doing this.

```bash
cat ~/.ssh/yubikey2_homelab.pub | ssh \
  -i ~/.ssh/yubikey_homelab \
  -o IdentityAgent=none \
  satoshi@<server-ip> \
  "cat >> ~/.ssh/authorized_keys && echo 'YubiKey 2 added'"
```

Verify both keys are present:

```bash
ssh -i ~/.ssh/yubikey_homelab -o IdentityAgent=none satoshi@<server-ip> \
  "cat ~/.ssh/authorized_keys"
# Should show two sk-ssh-ed25519@openssh.com entries
```

Repeat for every server in your homelab.

---

## Step 4 — Add to the Hardening Script

Open `homelab-harden.sh` and fill in the `YUBIKEY2_PUBLIC_KEY` variable so all **future** machines automatically get both keys:

```bash
# In homelab-harden.sh — public keys section
YUBIKEY2_PUBLIC_KEY="sk-ssh-ed25519@openssh.com AAAA... yubikey2-homelab-YYYYMM"
```

The script will then install both keys for both `satoshi` and `termix` on every new machine going forward.

---

## Step 5 — Update Your SSH Client Config

Edit `~/.ssh/config` to include both key stubs. SSH will try them in order — whichever YubiKey is plugged in will work.

```
Host X.X.X.*
    User satoshi
    IdentityFile ~/.ssh/yubikey_homelab
    IdentityFile ~/.ssh/yubikey2_homelab
    IdentitiesOnly yes
    IdentityAgent none
```

> **Note on `IdentityAgent none`:** This bypasses the system SSH agent (KDE Wallet, GNOME Keyring, etc.) which can interfere with FIDO2 key signing. The YubiKey handles auth directly without needing an agent.

---

## Step 6 — Recover Keys on a New Machine

Since both keys use resident slots, you can recover the stubs on any machine without carrying files around:

```bash
# Plug in the YubiKey, then:
ssh-keygen -K
# Enter FIDO2 PIN → touch the key

# This exports stubs into the current directory
mv id_ed25519_sk_rk_homelab        ~/.ssh/yubikey_homelab
mv id_ed25519_sk_rk_homelab.pub    ~/.ssh/yubikey_homelab.pub
chmod 600 ~/.ssh/yubikey_homelab
chmod 644 ~/.ssh/yubikey_homelab.pub

# Repeat with second YubiKey and rename to yubikey2_homelab
```

---

## Backup Strategy

FIDO2 private keys **cannot be copied** between YubiKeys by design. The backup strategy is:

| Scenario | Recovery |
|---|---|
| YubiKey 1 lost/stolen | Use YubiKey 2 — already deployed on all servers |
| YubiKey 2 lost/stolen | Use YubiKey 1 — order a replacement, provision a new key |
| Both lost | Use termix bastion key (ed25519) as emergency access, then re-provision |
| New machine setup | Plug in either YubiKey, run `ssh-keygen -K` to recover stubs |

Keep the two YubiKeys **physically separate** — one on your keychain, one in a secure location (safe, drawer, offsite).

---

## Verifying Everything Works

```bash
# Test YubiKey 1
ssh -i ~/.ssh/yubikey_homelab -o IdentityAgent=none satoshi@<server-ip>

# Test YubiKey 2 (swap keys first)
ssh -i ~/.ssh/yubikey2_homelab -o IdentityAgent=none satoshi@<server-ip>

# Test via config (either key plugged in)
ssh satoshi@<server-ip>
```
