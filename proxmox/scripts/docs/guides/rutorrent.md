# ruTorrent LXC — Setup Guide

ruTorrent is a web frontend for rTorrent, deployed inside a Proxmox LXC container running Debian 13.

## Quick Start

Run from the Proxmox host shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Trawis/playground/main/proxmox/scripts/ct/rutorrent.sh)"
```

The installer will prompt for:
- Web UI username and password
- Plugins to enable
- Whether to expose the `/RPC2` XMLRPC endpoint
- Maximum `.torrent` upload size (default 32 MiB)

Once complete, open `http://<container-ip>/` in your browser. Credentials are saved to `~/rutorrent.creds` inside the container.

---

## Non-interactive / Pre-seeded Install

Pass environment variables to skip all prompts:

```bash
RUTORRENT_USER=admin \
RUTORRENT_PASS=changeme \
RUTORRENT_ENABLE_RPC2=yes \
RUTORRENT_MAX_UPLOAD_MB=64 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Trawis/playground/main/proxmox/scripts/ct/rutorrent.sh)"
```

| Variable | Default | Description |
|---|---|---|
| `RUTORRENT_USER` | `rutorrent` | Web UI username |
| `RUTORRENT_PASS` | *(random)* | Web UI password — leave unset to auto-generate |
| `RUTORRENT_PLUGINS` | *(all on)* | Comma-separated plugin slugs to enable |
| `RUTORRENT_ENABLE_RPC2` | `no` | Set to `yes` to expose `/RPC2` for Sonarr/Radarr/autodl |
| `RUTORRENT_MAX_UPLOAD_MB` | `32` | Max `.torrent` upload size applied to nginx, PHP, and filedrop |

---

## Paths Inside the Container

| Path | Purpose |
|---|---|
| `/var/lib/rtorrent/downloads/` | Default download directory |
| `/var/lib/rtorrent/session/` | rTorrent session data |
| `/var/lib/rtorrent/.watch/` | Drop `.torrent` files here to auto-add |
| `/var/www/rutorrent/` | ruTorrent web root |
| `/var/www/rutorrent/conf/config.php` | ruTorrent main config |
| `/var/www/rutorrent/conf/plugins.ini` | Plugin enable/disable state |
| `/etc/nginx/.rutorrent_htpasswd` | HTTP basic auth credentials |
| `~/rutorrent.creds` | Plain-text credentials file (root only) |

---

## Mount Points — External Storage

The container user is `torrent` (system user, no login shell). For the container to write to a host path, the host path must be owned by the container's mapped UID/GID.

### 1. Find the container UID mapping

In an unprivileged LXC, container UID 0 maps to a high host UID (typically 100000+). The `torrent` user inside the container will have a UID around 999, which maps to approximately `100999` on the host.

Verify the exact UID:
```bash
# Inside the container
id torrent
# → uid=999(torrent) ...

# On the Proxmox host — container UID 999 maps to:
grep lxc /etc/subuid
# → root:100000:65536 means host UID = 100000 + 999 = 100999
```

### 2. Set ownership on the host path

```bash
# On the Proxmox host
chown -R 100999:100999 /mnt/your-disk
```

Skip this step for CIFS/NFS/SMB shares — set `uid=100999,gid=100999` in your mount options instead.

### 3. Add the bind mount

```bash
# Shut down the container first
pct stop <CTID>

# Add the bind mount (maps /mnt/your-disk on host to /data inside container)
pct set <CTID> -mp0 /mnt/your-disk,mp=/data

# Start the container
pct start <CTID>
```

For multiple disks use `-mp1`, `-mp2`, etc.:

```bash
pct set <CTID> -mp0 /mnt/disk1,mp=/data
pct set <CTID> -mp1 /mnt/disk2,mp=/data2
```

### 4. Point rTorrent at the new path

Edit `/var/lib/rtorrent/.rtorrent.rc` inside the container:

```
directory.default.set = /data
```

Then restart rTorrent:

```bash
systemctl restart rtorrent
```

Or update the download directory from the ruTorrent web UI under **Settings → Directory**.

---

## CIFS / SMB Share

Example `/etc/fstab` entry on the Proxmox host:

```
//nas.local/media /mnt/nas cifs credentials=/root/.smb,uid=100999,gid=100999,file_mode=0664,dir_mode=0775 0 0
```

Mount and then bind into the container:

```bash
mount /mnt/nas
pct set <CTID> -mp0 /mnt/nas,mp=/data
```

---

## NFS Share

Example `/etc/fstab` entry on the Proxmox host:

```
nas.local:/volume1/media /mnt/nas nfs defaults,soft,_netdev 0 0
```

NFS honours UID/GID numerically — ensure the NFS export allows `100999` write access, or use `anonuid=100999,anongid=100999` in the export options on the NAS.

---

## Updating ruTorrent

Re-run the ct script from the Proxmox host shell while the container is running. It detects an existing install and runs the update path:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Trawis/playground/main/proxmox/scripts/ct/rutorrent.sh)"
```

The update fetches the latest ruTorrent release tag and does a `git checkout` in-place — no reinstall required.

---

## Reverse Proxy (Nginx Proxy Manager)

The container nginx is already configured to trust `X-Forwarded-For` from private ranges. In NPM, create a Proxy Host pointing to `http://<container-ip>:80` and add the following to the **Advanced** tab:

```nginx
client_max_body_size 32M;
```

Adjust the value to match `RUTORRENT_MAX_UPLOAD_MB` if you changed it.

---

## Troubleshooting

**rTorrent not starting:**
```bash
systemctl status rtorrent
journalctl -u rtorrent -n 50
```

**Socket missing after start:**
```bash
ls -la /run/rtorrent/rtorrent.sock
# If absent, check rtorrent.rc for typos and restart
systemctl restart rtorrent
```

**Permission denied on mount path:**
```bash
# On the Proxmox host — confirm UID mapping
ls -lan /mnt/your-disk
# Owner should be 100999:100999
```

**Check credentials:**
```bash
pct exec <CTID> -- cat /root/rutorrent.creds
```
