# ruTorrent LXC — Proxmox Installer

Installs **rTorrent + ruTorrent** inside a Debian 12 LXC container on Proxmox VE,
following the [Community Scripts](https://github.com/community-scripts/ProxmoxVE) conventions.

## Quick start

Run on the **Proxmox host**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Trawis/playground/main/proxmox/scripts/rtorrent-rutorrent/rutorrent.sh)"
```

You will be asked to choose **Default** or **Advanced** mode.

| Mode | Container | Username | Plugins | /RPC2 |
|---|---|---|---|---|
| Default | Unprivileged | `torrent` | Standard set | Disabled |
| Advanced | Your choice | Your choice | whiptail checklist | Your choice |

### Environment variable overrides

All prompts can be bypassed by setting variables before running:

```bash
RUTORRENT_USER=admin \
RUTORRENT_PLUGINS="autotools ratio unpack filemanager" \
RUTORRENT_ENABLE_RPC2=0 \
CHOWN_MOUNTS=0 \
HDD_PATH=/mnt/data \
bash rutorrent.sh
```

---

## nginx /RPC2 endpoint

**`/RPC2` is disabled by default.**

This endpoint exposes the rTorrent XMLRPC/SCGI interface over HTTP. Enabling it
lets external tools (autodl-irssi, Sonarr, Radarr, etc.) talk to rTorrent directly.

When enabled it is **still protected by HTTP basic auth** — the same credentials
used for the ruTorrent web UI. There is no unauthenticated access.

To enable:

```bash
RUTORRENT_ENABLE_RPC2=1 bash rutorrent.sh
```

Or select **Advanced** mode and answer `y` to the `/RPC2` prompt.

> `config.php` always sets `$XMLRPCMountPoint = "/RPC2"` so ruTorrent itself can
> communicate with rTorrent internally over SCGI. The nginx route controls whether
> that endpoint is reachable from outside the container.

---

## Storage — bind-mounting a host disk

To make a host path available inside the container as `/data`, pass `HDD_PATH`:

```bash
HDD_PATH=/mnt/data bash rutorrent.sh
```

Multiple disks (space-separated, `host:container` pairs):

```bash
HDD_PATHS="/mnt/hdd1 /mnt/hdd2:/data2" bash rutorrent.sh
```

The script configures the bind mount with `pct set` and restarts the container so
the mount is active immediately.

### Ownership for unprivileged LXC

In an unprivileged container, the `torrent` user (UID 1000 inside) maps to UID
**101000** on the host. The host path must be writable by that UID.

**For a dedicated local ext4 folder** — enable recursive chown:

```bash
CHOWN_MOUNTS=1 HDD_PATH=/mnt/data bash rutorrent.sh
```

Or manually beforehand:

```bash
chown -R 101000:101000 /mnt/your/path
```

> ⚠️ **Do not use `CHOWN_MOUNTS=1` or `chown -R` on a Synology share, CIFS mount,
> or any path that contains other users' data.** Recursive chown on a broad media
> library will reassign ownership of every file on that share.

**For CIFS / NFS / Synology / Samba mounts** — set ownership in the mount options
instead of using `chown`:

```
uid=101000,gid=101000,file_mode=0664,dir_mode=0775
```

Example `/etc/fstab` entry for a Synology SMB share:

```
//192.168.1.x/torrents /mnt/torrents cifs credentials=/etc/samba/synology.cred,uid=101000,gid=101000,file_mode=0664,dir_mode=0775 0 0
```

### Adding storage to an existing container

```bash
pct stop <CTID>
pct set <CTID> -mp0 /mnt/your/path,mp=/data
pct start <CTID>
```

---

## ⚠️ ext4 reserved blocks — reclaim space on large data disks

> **This is a manual step.** The installer does not touch filesystem reserved blocks.

By default, `ext4` reserves **5% of total capacity** for the root user to prevent
the filesystem from completely filling up. On a system/boot disk this is sensible.
On a **dedicated data disk** it wastes significant space:

| Disk size | Space wasted at 5% |
|---|---|
| 1 TB | ~51 GB |
| 4 TB | ~205 GB |
| 10 TB | ~512 GB |

### Check how much is reserved

```bash
tune2fs -l /dev/sdX | grep -E "Block count|Reserved block count"
```

Divide *Reserved block count* by *Block count* and multiply by 100 to get the percentage.

### Set reserved blocks to 0% (pure data disk)

```bash
tune2fs -m 0 /dev/sdX
```

### Set to 1% (small safety margin)

```bash
tune2fs -m 1 /dev/sdX
```

**When to use 0%:** The disk is dedicated to torrent downloads — no OS, no root
processes that need emergency space. If the disk fills up completely rTorrent will
just stop writing; nothing will break on the host.

**When to keep some reserved space:** The disk is shared with other services, or
you want a safety buffer so you notice a full disk before losing writes.

> Run `lsblk` or `findmnt` to identify the correct device before running `tune2fs`.
> Only `ext2/3/4` filesystems support reserved blocks; `xfs`, `btrfs`, and `zfs`
> handle this differently.

---

## Plugins

Plugins are **disabled through `conf/plugins.ini`**, not by deleting plugin
directories. Plugin files are always preserved on disk so they can be re-enabled
at any time by editing `conf/plugins.ini` or re-running the installer.

The following plugins ship with ruTorrent and are **enabled by default**:

`autotools` `bulk_magnet` `chunks` `cookies` `create` `data` `datadir` `edit`
`erasedata` `extsearch` `extratio` `feeds` `filedrop` `filemanager`
`filemanager-media` `history` `httprpc` `ipad` `loginmgr` `lookat` `mediainfo`
`ratio` `rss` `rssurlrewrite` `scheduler` `screenshots` `seedingtime`
`show_peers_like_wtorrent` `source` `spectrogram` `theme` `tracklabels` `trafic`
`unpack`

**Disabled by default:**

| Plugin | Reason |
|---|---|
| `throttle` | Requires privileged LXC (kernel traffic control — `tc`) |
| `dump` | Requires `dumptorrent`, not available on Debian 10+ |
| `xmpp` | Requires an external XMPP/Jabber server |

**Not yet implemented** (shown in Advanced checklist, kept disabled if selected):

`geoip2` `pausewebui` `quotaspace` `retrackers` `rutracker_check` `uploadeta`

To customise after install, edit `/var/www/rutorrent/conf/plugins.ini` inside the
container and restart nginx.

---

## Credentials

After install, credentials are shown in the terminal output and stored in `/etc/motd`
inside the container:

```bash
pct exec <CTID> -- cat /etc/motd
```

To change the password:

```bash
pct exec <CTID> -- htpasswd /etc/nginx/.rutorrent.htpasswd <username>
pct exec <CTID> -- systemctl restart nginx
```

---

## Updating

Re-run the script against the existing container — it will detect the installation
and run `update_script()` to pull the latest ruTorrent release and update system packages.
