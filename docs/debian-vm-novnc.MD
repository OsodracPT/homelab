# Debian 12 VM Setup — Remote Desktop with noVNC

A complete guide to setting up a Debian 12 VM with XFCE desktop, TigerVNC, noVNC, and messaging apps (Signal Desktop + WhatsApp Web via Chromium), accessible from a web browser.

---

## 1. System Update & Desktop Environment

```bash
apt update && apt upgrade -y

# XFCE4 lightweight desktop
apt install -y xfce4 xfce4-goodies dbus-x11 at-spi2-core
```

---

## 2. Create a Non-Root User

```bash
adduser satoshi
usermod -aG sudo satoshi
```

---

## 3. Expand Disk (if partition is smaller than disk)

Check current layout:

```bash
lsblk
df -h /
fdisk -l /dev/sda
```

If the partition doesn't fill the disk, resize it with `fdisk`. Note the **start sector** of `/dev/sda1` from the output of `fdisk -l`, then:

```bash
fdisk /dev/sda
```

Inside fdisk:

```
p          # print table, note sda1 start sector
d          # delete partition
1          # partition 1
n          # new partition
p          # primary
1          # partition number 1
[ENTER]    # SAME start sector as before (critical!)
[ENTER]    # default end (uses all space)
N          # do NOT remove the ext4 signature
w          # write and exit
```

Then resize the filesystem:

```bash
partprobe /dev/sda
resize2fs /dev/sda1
df -h /
```

---

## 4. OpenSSH Server

```bash
apt install -y openssh-server
systemctl enable --now ssh
```

### Harden SSH

Edit `/etc/ssh/sshd_config`:

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
Port 2222
```

Copy your public key **from your local machine**:

```bash
ssh-copy-id -p 22 satoshi@VM_IP
```

Then restart SSH on the VM:

```bash
systemctl restart ssh
```

### Install fail2ban

```bash
apt install -y fail2ban
systemctl enable --now fail2ban
```

---

## 5. Firewall (UFW)

```bash
apt install -y ufw
ufw allow 2222/tcp    # SSH
ufw allow 6080/tcp    # noVNC (remove once behind Pangolin)
ufw enable
```

---

## 6. TigerVNC Server

```bash
apt install -y tigervnc-standalone-server tigervnc-common
```

Switch to your user:

```bash
su - satoshi
```

Set VNC password and create startup script:

```bash
vncpasswd

mkdir -p ~/.vnc
cat > ~/.vnc/xstartup << 'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
chmod +x ~/.vnc/xstartup
```

Test it:

```bash
vncserver :1 -geometry 1920x1080 -depth 24
```

To kill it:

```bash
vncserver -kill :1
```

---

## 7. noVNC (Browser-Based VNC Client)

```bash
# Run as root
apt install -y git
git clone https://github.com/novnc/noVNC.git /opt/noVNC
git clone https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify
```

Launch noVNC:

```bash
/opt/noVNC/utils/novnc_proxy --vnc localhost:5901 --listen 6080
```

Access the desktop in your browser at:

```
http://VM_IP:6080/vnc.html
```

---

## 8. Systemd Services (Auto-Start on Boot)

### VNC Server Service

Create `/etc/systemd/system/vncserver@.service`:

```ini
[Unit]
Description=TigerVNC server on display %i
After=network.target

[Service]
Type=forking
User=satoshi
ExecStart=/usr/bin/vncserver :%i -geometry 1920x1080 -depth 24
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
```

### noVNC Service

Create `/etc/systemd/system/novnc.service`:

```ini
[Unit]
Description=noVNC websocket proxy
After=vncserver@1.service

[Service]
Type=simple
ExecStart=/opt/noVNC/utils/novnc_proxy --vnc localhost:5901 --listen 6080
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable both:

```bash
systemctl enable --now vncserver@1
systemctl enable --now novnc
```

---

## 9. Install Messaging Apps

### Signal Desktop

```bash
wget -qO- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > /usr/share/keyrings/signal-desktop-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main" > /etc/apt/sources.list.d/signal.list

apt update && apt install -y signal-desktop
```

### Chromium (for WhatsApp Web)

```bash
apt install -y chromium
```

Open Chromium and navigate to `https://web.whatsapp.com` to link your phone.

---

## 10. Pangolin Integration

Once Pangolin is configured, point it to `http://VM_IP:6080` as a backend service. Pangolin handles TLS termination and authentication.

After Pangolin is live, lock down noVNC so it only accepts local connections or connections from the Pangolin host:

```bash
ufw delete allow 6080/tcp
ufw allow from PANGOLIN_IP to any port 6080
```

---

## Architecture Overview

```
Internet → Pangolin (auth + TLS) → noVNC (:6080) → TigerVNC (:5901) → XFCE Desktop
                                                                        ├── Signal Desktop
                                                                        └── Chromium (WhatsApp Web)
```

---

## Useful Commands

| Action | Command |
|---|---|
| Start VNC manually | `vncserver :1 -geometry 1920x1080 -depth 24` |
| Kill VNC | `vncserver -kill :1` |
| Start noVNC manually | `/opt/noVNC/utils/novnc_proxy --vnc localhost:5901 --listen 6080` |
| Check VNC status | `systemctl status vncserver@1` |
| Check noVNC status | `systemctl status novnc` |
| SSH into VM | `ssh -p 2222 satoshi@VM_IP` |
| Check disk usage | `df -h /` |
| Change VNC resolution | Edit `-geometry` flag or use `xrandr` inside session |
