# pve-ip-mount-retry

A small companion to [`pve-ip-mount-gate`](../pve-ip-mount-gate) that retries
IP-backed CIFS/NFS mounts defined in `/etc/fstab` when they failed, or
hadn't come up yet, at boot.

## What it does

- Requires root; validates that `findmnt`, `systemctl` and
  `systemd-escape` are present before doing anything.
- Reads network shares (`cifs`, `nfs`, `nfs4`) from `/etc/fstab` whose
  `SOURCE` contains an IPv4 address or a bracketed IPv6 address.
  Hostname-only NFS/CIFS sources are ignored.
- For each IP-backed entry, checks the exact mountpoint (`findmnt -M`, not
  a path-resolving lookup) and does exactly one of:
  - **already mounted, expected source** — logs `OK`, leaves it alone.
  - **already mounted, unexpected source** — logs `BLOCKED` and leaves it
    alone. It never mounts over, unmounts, or otherwise "fixes" a
    mountpoint that's occupied by something other than the configured
    remote source; it only reports the mismatch.
  - **missing, generated unit already activating** — logs `WAIT` and does
    nothing this cycle, so it never resets or restarts a mount that's
    already in flight.
  - **missing, no generated `.mount` unit** — logs `WARN` and skips it.
  - **missing, otherwise** — clears any prior failed state and asks
    systemd to start the generated unit (`systemctl start --no-block`),
    logging `RETRY`.
- Never calls `mount`, `umount`, `mount -a`, or edits `/etc/fstab` —
  activation goes entirely through the systemd-generated `.mount` unit for
  that fstab entry (`/mnt/data` → `mnt-data.mount` via
  `systemd-escape --path --suffix=mount`).
- One failed retry is a normal, expected condition (the NAS may simply
  still be offline) — it is logged and the helper still exits `0`.
- Runs once at boot (15s in — slightly ahead of `pve-ip-mount-gate.timer`'s
  ~20s) and then every 60 seconds via a timer, so a NAS that comes up late
  still gets mounted without a reboot.

## Relationship to pve-ip-mount-gate

`pve-ip-mount-gate` gates LXC **startup** until the IP-backed mounts it
depends on are present; it assumes mount management already exists
elsewhere. This project is that piece — it's what actually retries mount
activation:

```text
fstab configuration
       |
systemd generated .mount unit
       |
pve-ip-mount-retry           (this project: gets the mount itself up)
       |
remote mount becomes available
       |
pve-ip-mount-gate             (separate project: decides the LXC is safe to start)
       |
dependent gated LXC starts
```

Both are optional and install independently; `install.sh` here will enable
and kick `pve-ip-mount-gate`'s timer too, but only if that project is
already installed on the node — this project has no hard runtime
dependency on it.

### Mount recovery is not LXC enrollment

Getting a mount back up and having a container start for it are two
separate operations owned by two separate projects. This project never
touches LXC configuration, tags, or `onboot` — it only ever acts on the
mountpoint.

In particular, `pve-ip-mount-retry` fixing a mount says nothing about
whether any given LXC will start. For example:

```text
onboot: 0
tags: community-script;media
mp0: /mnt/data/_media,mp=/media,ro=1
```

This container is **not** managed by `pve-ip-mount-gate` — it doesn't carry
the `ipmount-gated` tag, so the gate ignores it entirely. `onboot: 0` here
may simply mean "don't autostart this container," which is a legitimate,
intentional setting; neither this project nor the gate should ever infer
that an `onboot=0` container is meant to boot. If a container like this
*is* meant to be gated, that's an explicit, separate step using
`pve-ip-mount-gate`'s own command:

```bash
pve-ip-mount-gate --start-now CTID
```

After that, its configuration looks conceptually like:

```text
onboot: 0
tags: community-script;media;ipmount-gated
```

`onboot=0` still prevents ordinary Proxmox autostart, and the
`ipmount-gated` tag is what records that startup is now delegated to the
gate.

## Install

```bash
chmod +x install.sh pve-ip-mount-retry
./install.sh
```

The installer installs the script and timer, reloads systemd, enables the
timer, and triggers one retry pass immediately, then prints a status
summary (mounts, failed units, recent logs, containers). It's safe to
re-run: it only overwrites its own script/unit files, doesn't touch
`/etc/fstab`, doesn't disturb an already-mounted filesystem, and doesn't
restart a running container.

## Normal operation

```bash
systemctl status pve-ip-mount-retry.timer
journalctl -fu pve-ip-mount-retry.service
```

## Safety / limitations

- Only touches mountpoints that already have a systemd `.mount` unit
  generated from `/etc/fstab`; it does not discover or configure new
  mounts, and it never edits `/etc/fstab` or mount options.
- Matches IPv4-address-backed and bracketed-IPv6-backed sources only.
  Hostname-only NFS/CIFS sources are ignored.
- A mountpoint that is already mounted is left alone, even if unhealthy —
  this tool only retries *missing* mounts; it does not detect or repair a
  degraded (mounted-but-stale) filesystem, and it does not stop a running
  LXC if that filesystem later disappears out from under it.
- A successful retry is mount recovery, not LXC enrollment — see
  [Mount recovery is not LXC enrollment](#mount-recovery-is-not-lxc-enrollment)
  above. It never manipulates LXC tags, `onboot`, or any other guest
  configuration.

## Tests

```bash
./tests/smoke.sh
```

Runs shell syntax checks, `systemd-analyze verify` on the unit files (a
"binary not executable" complaint is expected and tolerated when run from
an uninstalled repo checkout; any other verify output fails the check),
and `tests/unit.sh` — behavioral tests (IPv4/IPv6/hostname discovery,
already-mounted vs. unexpected-source handling, activating-unit skip,
missing-unit retry, and that `mount`/`umount` are never invoked) that stub
out `findmnt`/`systemctl`/`systemd-escape`, so they run without a live
Proxmox host or NAS.
