# Filen WebDAV LXC

Filen WebDAV exposes your [Filen](https://filen.io) cloud storage as a standard WebDAV
endpoint inside an LXC container. Any WebDAV-capable client — macOS Finder, Windows
Explorer, rclone, Infuse, Cyberduck — can mount the share directly without installing
anything else.

---

## Modes

| Mode | Description |
|------|-------------|
| **Proxy** (default) | Each WebDAV client authenticates with its own Filen email and password. No credentials are stored on the container. |
| **Standalone** | A single Filen account is pre-configured. All WebDAV clients share that account. Credentials are written to `/opt/filen-webdav/server.js`. |

---

## Installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/ct/filen-webdav.sh)"
```

The installer prompts for:
- Server mode (proxy or standalone)
- Filen account credentials (standalone only)
- WebDAV listen port (default `1900`)

**Default resources**

| Resource | Default |
|----------|---------|
| CPU | 1 core |
| RAM | 512 MB |
| Disk | 4 GB |
| OS | Debian 13 |

---

## Connecting a Client

### macOS Finder

**Go → Connect to Server** (`⌘K`):

```
http://<container-ip>:1900
```

Enter your Filen email and password when prompted.

### Windows Explorer

Map a network drive, choose **Connect to a website…**, and enter:

```
http://<container-ip>:1900
```

### rclone

```bash
rclone config
# Type: webdav
# URL:  http://<container-ip>:1900
# Vendor: Other
# User: your Filen email
# Pass: your Filen password
```

---

## Key File Locations

| Purpose | Path (inside container) |
|---------|------------------------|
| Server script | `/opt/filen-webdav/server.js` |
| npm package | `/opt/filen-webdav/node_modules/` |
| systemd unit | `/etc/systemd/system/filen-webdav.service` |

---

## Service Management

```bash
systemctl status filen-webdav
systemctl restart filen-webdav
journalctl -u filen-webdav -f
```

---

## Updating

Re-run the installer and select **Update**, or inside the container:

```bash
cd /opt/filen-webdav && npm install @filen/webdav@latest
systemctl restart filen-webdav
```

---

## HTTPS / Reverse Proxy

HTTPS is not enabled by default. If the server is reachable outside your LAN, place a
reverse proxy in front:

**Caddy** (simplest — auto-TLS):

```
webdav.example.com {
    reverse_proxy localhost:1900
}
```

**nginx** (manual cert):

```nginx
server {
    listen 443 ssl;
    server_name webdav.example.com;
    ssl_certificate     /etc/ssl/certs/your.crt;
    ssl_certificate_key /etc/ssl/private/your.key;

    location / {
        proxy_pass http://127.0.0.1:1900;
        proxy_set_header Host $host;
    }
}
```

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| Service fails to start | Wrong credentials in standalone mode | Check `journalctl -u filen-webdav` and update `server.js` |
| Client gets 401 | Wrong Filen password | Verify credentials at [filen.io](https://filen.io) |
| Port already in use | Another service on 1900 | Change port in `server.js` and restart |
| Slow file listing | Normal — Filen API latency | No fix; consider rclone VFS cache for large directories |
