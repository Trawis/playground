# ruTorrent LXC — Proxmox Installer

Installs **rTorrent + ruTorrent** inside a Debian 12 LXC container on Proxmox VE,
following the [Community Scripts](https://github.com/community-scripts/ProxmoxVE) conventions.

## Quick start

Run on the **Proxmox host**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Trawis/playground/main/proxmox/scripts/rtorrent-rutorrent/rutorrent.sh)"
```

You will be asked to choose **Default** or **Advanced** mode.

| Mode | Container | Username | Plugins |
|---|---|---|---|
| Default | Unprivileged | `torrent` | Standard set, no prompts |
| Advanced | Your choice | Your choice | whiptail checklist |

### Environment variable overrides

All prompts can be bypassed by setting variables before running:

```bash
RUTORRENT_USER=admin \
RUTORRENT_PLUGINS="autotools ratio unpack filemanager" \
HDD_PATH=/mnt/data \
bash rutorrent.sh
```

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

The script will:
1. Set ownership of the path to UID/GID `101000` (maps to the `torrent` user inside an unprivileged container)
2. Configure the bind mount with `pct set`
3. Restart the container so the mount is active immediately

> **CIFS / NFS / Samba mounts:** `chown` is skipped automatically. Set ownership
> via mount options instead: `uid=101000,gid=101000,file_mode=0664,dir_mode=0775`

To add storage to an existing container:

```bash
chown -R 101000:101000 /mnt/your/path
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

The following plugins ship with ruTorrent and are enabled by default:

`autotools` `bulk_magnet` `chunks` `cookies` `create` `data` `datadir` `edit`
`erasedata` `extsearch` `extratio` `feeds` `filedrop` `filemanager`
`filemanager-media` `history` `httprpc` `ipad` `loginmgr` `lookat` `mediainfo`
`ratio` `rss` `rssurlrewrite` `scheduler` `screenshots` `seedingtime`
`show_peers_like_wtorrent` `source` `spectrogram` `theme` `tracklabels` `trafic`
`unpack`

Disabled by default:

| Plugin | Reason |
|---|---|
| `throttle` | Requires privileged LXC (kernel traffic control — `tc`) |
| `dump` | Requires `dumptorrent`, not available on Debian 10+ |
| `xmpp` | Requires an external XMPP/Jabber server |

Not yet implemented (shown in Advanced checklist, no-op if selected):

`geoip2` `pausewebui` `quotaspace` `retrackers` `rutracker_check` `uploadeta`

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
systemctl restart nginx   # inside the container
```

---

## Updating

Re-run the script against the existing container — it will detect the installation
and run `update_script()` to pull the latest ruTorrent release and update system packages.
