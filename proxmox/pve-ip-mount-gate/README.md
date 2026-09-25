# pve-ip-mount-gate

A small Proxmox VE helper that prevents selected LXCs from booting before the external IP-backed host mounts they bind-mount are actually available.

It is designed for the case where mount management already exists. **This project never runs `mount`, `umount`, `mount -a`, or remount operations.**

## What it does

- Discovers IPv4-backed external mounts from:
  - `/etc/fstab`
  - Proxmox `nfs:` / `cifs:` entries in `/etc/pve/storage.cfg`
  - currently-mounted custom filesystems whose `SOURCE` contains an IPv4 address
- Ignores ordinary local filesystems.
- Parses LXC `mp0`, `mp1`, ... bind-mount source paths.
- If an LXC has `onboot=1` and depends on an IP-backed mount:
  - adds the Proxmox tag `ipmount-gated`
  - changes its normal `onboot` setting to `0`
- At boot, builds a pending set of gated LXCs **before `pve-guests.service`**.
- Every 60 seconds, starts a pending LXC only when **all** IP-backed mounts used by that LXC are present, mounted from the *exact* expected remote resource, and responsive.
- Does not restart a CT that you manually stop after it has successfully started that boot.
- Auto-discovers new shares and auto-enrolls new `onboot=1` dependent LXCs. Newly-created/enrolled CTs are scheduled for the **next boot** by default; use `--start-now CTID` if you explicitly want one started during the current boot.

## Why the Proxmox tag?

The gate changes `onboot=1` to `onboot=0`, so it needs a durable marker that says "this CT is still intended to boot, but through the mount gate." Proxmox tags are guest metadata and multiple tags are supported. This also survives guest migration better than a node-local CT-ID list.

Default tag:

```text
ipmount-gated
```

## Install

Clone/copy the repo onto each Proxmox node that should run the gate, then:

```bash
chmod +x install.sh uninstall.sh pve-ip-mount-gate
./install.sh
```

The installer deliberately **does not start currently-stopped CTs**. It enrolls matching CTs and enables the boot service/timer. Normal gated startup begins on the next reboot.

To explicitly start a gated CT now if its dependencies are ready:

```bash
pve-ip-mount-gate --start-now 101
```

## Normal operation

Useful commands:

```bash
pve-ip-mount-gate --status
pve-ip-mount-gate --discover
journalctl -fu pve-ip-mount-gate.service
systemctl status pve-ip-mount-gate.timer
```

The timer runs roughly 20 seconds after boot and then every 60 seconds.

## Example

Host mounts:

```text
/mnt/pve/media      -> 203.0.113.10:/volume1/media
/mnt/pve/downloads  -> 203.0.113.10:/volume2/downloads
/mnt/local-ssd      -> local disk
```

LXC 101:

```text
onboot: 1
mp0: /mnt/pve/media/movies,mp=/movies
```

LXC 105:

```text
onboot: 1
mp0: /mnt/pve/media,mp=/media
mp1: /mnt/pve/downloads,mp=/downloads
```

Result:

- CT 101 starts when `/mnt/pve/media` is ready.
- CT 105 starts only when **both** `/mnt/pve/media` and `/mnt/pve/downloads` are ready.
- `/mnt/local-ssd` does not participate because it is local.

## Mount source verification

**Same server does not mean same remote resource.** Two different shares or
exports on the same NAS are two different dependencies, and a mount gone
wrong (an operator error, a misconfigured storage definition, an unrelated
filesystem left mounted over a target) must never be accepted just because
it happens to live on the right server.

So the readiness check is, in order:

```text
exact target mounted?
       |
       yes
       |
mounted from the exact expected remote source?
       |
       yes
       |
bounded stat() responds in time?
       |
       yes
       |
READY
```

A source mismatch is reported and the dependency stays **not ready** - it
never falls through to the responsiveness check, so an unexpected
filesystem that happens to answer `stat()` quickly is still rejected.

For example, with `/mnt/pve/media` expected to be `//203.0.113.10/media`:

```text
expected: //203.0.113.10/media
actual:   //203.0.113.10/media      -> OK, continues to the responsiveness check
actual:   //203.0.113.10/media/     -> OK (see "the trailing-slash exception" below)
actual:   //203.0.113.10/backups    -> unexpected-source (same server, different share)
actual:   //203.0.113.11/media      -> unexpected-source (different server)
actual:   /dev/sdb1                 -> unexpected-source (unrelated local filesystem)
```

The same applies to NFS exports, e.g. `203.0.113.20:/exports/media` vs.
`203.0.113.20:/exports/backups`, and to a CIFS share's `subdir`, e.g.
`//203.0.113.10/media/movies` vs. `//203.0.113.10/media/tv`.

### The trailing-slash exception

The exact-match check has exactly one deliberately narrow exception,
mirroring Proxmox's own NFS/CIFS source validation (effectively
`^expected/?$`): the live source may equal the expected source with one
additional trailing `/` appended (`//203.0.113.10/media` matches
`//203.0.113.10/media/`; `203.0.113.20:/` matches `203.0.113.20://`, since
the extra slash is appended regardless of whether the expected source
already ends in one). Nothing broader is normalized - not two trailing
slashes, not case, not path segments.

### Where the exact source comes from

- **`/etc/fstab` entries** and **live/custom-discovered mounts**: the
  configured or live `SOURCE` *is* the complete remote resource, so these
  always get the exact-match check above.
- **Proxmox `nfs:` storage.cfg entries**: the documented `export` field
  gives the exact NFS export path, so `server:export` is reconstructed and
  gets the same exact-match check.
- **Proxmox `cifs:` storage.cfg entries**: the documented `share` field
  gives the exact share name, and Proxmox's own CIFS mount source
  construction appends an optional `subdir` directly after it, so
  `//server/share` (or `//server/share/subdir`, when a `subdir` is
  configured) is reconstructed and gets the same exact-match check,
  whether or not a `subdir` is set.
- A storage.cfg entry that's missing the field it needs to reconstruct the
  exact resource (an `nfs:` entry with no `export`, or a `cifs:` entry
  with no `share`) falls back to a **weaker, server-address-only** check
  instead of guessing. This is the only case where this project cannot
  guarantee full remote-resource identity from a storage.cfg entry; it's
  still an improvement over versions before this check existed (which
  used a loose substring match that a shorter address could pass by
  matching part of a longer one).
- **Legacy remembered custom mounts** from before this version's mount
  database format are migrated to the same weaker, server-address-only
  check on upgrade (see [Custom mounts](#custom-mounts)), and are
  automatically strengthened to the exact-match check the next time that
  mount is seen live.

Either way, the server-address-only check is always an **exact match on
the extracted address**, never a substring check - so `203.0.113.24` can
never be mistaken for `203.0.113.241`.

## New LXCs and new shares

No reinstall is required.

The recurring cycle refreshes mount discovery and enrolls any new local LXC that:

1. uses an absolute `mpX` source underneath an IP-backed external mount, and
2. currently has `onboot=1`.

The gate adds `ipmount-gated`, changes `onboot` to `0`, and will include it automatically on the next boot.

For an immediate current-boot start:

```bash
pve-ip-mount-gate --start-now CTID
```

## Custom mounts

Configured fstab and Proxmox NFS/CIFS mounts remain discoverable even while offline.

A custom mount that is only visible through the live mount table is remembered in:

```text
/etc/pve-ip-mount-gate/mounts.db
```

This is intentionally conservative: if that remote filesystem later disappears, the gate remembers that the path was external rather than accidentally treating the underlying empty local directory as safe. Because the live source was seen directly, a remembered custom mount always gets the strong, exact-match verification described in [Mount source verification](#mount-source-verification).

Each line is `target|source|kind|origin` - see [Mount source verification](#mount-source-verification) for what `source`/`kind` mean. Configured (`/etc/fstab`/`storage.cfg`) entries are always rediscovered fresh and never need migrating; only remembered custom (`mounted:`-origin) entries persist across a refresh.

**Upgrading from a version before this format:** the previous database format only remembered a target and a bare IP address, with no share/export identity. On first refresh after upgrading, any such remembered custom mount is migrated automatically to the current format's weaker, server-address-only check (never discarded) and logged as migrated; it's strengthened to the full exact-match check automatically the next time that mount is seen live. Configured fstab/storage.cfg entries need no migration since they're rediscovered fresh regardless of format.

If a custom remote mount has been permanently removed, forget it explicitly:

```bash
pve-ip-mount-gate --forget-mount /path/to/old/mount
```

## Unenroll one CT

Keep it stopped at boot:

```bash
pve-ip-mount-gate --unenroll CTID
```

Return it to normal Proxmox autostart:

```bash
pve-ip-mount-gate --unenroll-onboot CTID
```

## Uninstall

Remove the helper but leave CT settings/state unchanged:

```bash
./uninstall.sh
```

Or restore tagged local CTs to normal `onboot=1` first:

```bash
./uninstall.sh --restore-onboot
```

Persistent state is deliberately left under `/etc/pve-ip-mount-gate` for audit/reinstall.

## Safety / limitations

- This version intentionally matches **IPv4-address-backed** shares only. Hostname-only NFS/CIFS sources are ignored.
- LXC dependency detection is for bind-style `mpX` entries whose source is an absolute host path, e.g. `mp0: /mnt/pve/media,mp=/media`.
- The health check confirms the exact mountpoint exists, its live source matches the exact expected remote resource (or, in the narrower cases described in [Mount source verification](#mount-source-verification), at least the expected server address), and a small `stat()` against the mount root completes before the timeout.
- A mounted filesystem can still fail later at runtime. This project gates **startup**; it does not stop running containers when storage disappears.
- This project only verifies mounts; it never retries a failed one. If a dependency shows `not-mounted` or `unexpected-source`, recovering the mount itself (or investigating why something else is occupying the target) is outside this project's scope - see `pve-ip-mount-retry` for automatic retry of missing `/etc/fstab`-defined mounts.
- Install it on every Proxmox node where a gated LXC may live. The `ipmount-gated` tag follows guest configuration, while mount inventory is node-local.
- A CT created with `onboot=1` and immediately followed by a host reboot before the periodic auto-enrollment has ever run is an edge case. The enabled boot enrollment service is ordered before `pve-guests.service` so it can catch that CT and clear `onboot` before Proxmox's normal guest autostart path.

## Implementation notes / references

Proxmox documents `onboot` as the flag that starts a container during host boot, `pct start CTID` as the explicit container start operation, and absolute host paths in `mpX` as bind mounts (including host NFS mounts). Proxmox also documents that the `pve-guests` service starts guests with `onboot` set during node startup.

systemd timer units support combining `OnBootSec=` and `OnUnitActiveSec=` for an initial boot-relative trigger followed by regular activations.

`findmnt -M/--mountpoint` checks an exact mountpoint, unlike `-T/--target`, which may resolve a path to a parent filesystem. That distinction is important here because an absent remote mount must not fall through to the underlying local directory.
