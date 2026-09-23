# pve-ip-mount-retry

A small companion to [`pve-ip-mount-gate`](../pve-ip-mount-gate) that retries
IP-backed CIFS/NFS mounts defined in `/etc/fstab` when they failed, or
hadn't come up yet, at boot.

## What it does

- Reads network shares (`cifs`, `nfs`, `nfs4`) from `/etc/fstab` whose
  `SOURCE` contains an IPv4 address or a bracketed IPv6 address.
- Skips any mountpoint that is already mounted — it never touches a mount
  that's already up.
- For everything else, resolves the systemd `.mount` unit generated from
  that fstab entry and asks systemd to start it
  (`systemctl start --no-block`), clearing any prior failed state first.
- Never calls `mount`/`umount` directly — activation goes entirely through
  the generated systemd mount unit.
- Runs once at boot (20s in) and then every 60 seconds via a timer, so a NAS
  that comes up late still gets mounted without a reboot.

## Relationship to pve-ip-mount-gate

`pve-ip-mount-gate` gates LXC **startup** until the IP-backed mounts it
depends on are present; it assumes mount management already exists
elsewhere. This project is that piece — it's what actually retries mount
activation. Installed together: this retries the mount, then
`pve-ip-mount-gate` starts the dependent LXC once it sees the mount is up.

Both are optional and install independently; `install.sh` here will enable
and kick `pve-ip-mount-gate`'s timer too, but only if that project is
already installed on the node.

## Install

```bash
chmod +x install.sh pve-ip-mount-retry
./install.sh
```

The installer installs the script and timer, reloads systemd, enables the
timer, and triggers one retry pass immediately, then prints a status
summary (mounts, failed units, recent logs, containers).

## Normal operation

```bash
systemctl status pve-ip-mount-retry.timer
journalctl -fu pve-ip-mount-retry.service
```

## Safety / limitations

- Only touches mountpoints that already have a systemd `.mount` unit
  generated from `/etc/fstab`; it does not discover or configure new
  mounts.
- Matches IPv4-address-backed and bracketed-IPv6-backed sources only.
  Hostname-only NFS/CIFS sources are ignored.
- A mountpoint that is already mounted is left alone, even if unhealthy —
  this tool only retries *missing* mounts; it does not detect or repair a
  degraded one.
