# Changelog

## 1.1.0 - 2026-09-24

- **Safety fix:** mount readiness verification now checks the complete
  expected remote source (e.g. `//203.0.113.10/media` or
  `203.0.113.20:/exports/media`), not just the server's IP address. A
  different share or export on the same server, a different server, or an
  unrelated local filesystem occupying the target are all now correctly
  rejected as `unexpected-source` instead of being accepted because the
  server address happened to match.
- The mount database record format gained a `source`/`kind` distinction
  (`target|source|kind|origin`) in place of the previous `target|ip|origin`,
  so full remote-resource identity can be retained where it's known.
  Proxmox `nfs:`/`cifs:` storage.cfg entries reconstruct the full source
  from their documented `export`/`share` fields, `cifs:` including an
  optional `subdir` (Proxmox appends it directly after the share, so
  `//server/share/subdir` is reconstructed the same way as a plain
  `//server/share`). Only a storage.cfg entry missing the field it needs
  (an `nfs:` with no `export`, or a `cifs:` with no `share`) falls back to
  the weaker server-address-only check.
- The exact-match check accepts one narrow exception, mirroring Proxmox's
  own NFS/CIFS source validation (effectively `^expected/?$`): the live
  source may equal the expected source with one additional trailing `/`
  appended, regardless of whether the expected source already ends in
  one. Nothing broader is normalized.
- The server-address-only check (used only where full identity genuinely
  isn't available) is now an exact match on the extracted address rather
  than a substring check, fixing a related false-positive where a shorter
  address could be matched as a prefix of a longer, different one (e.g.
  `203.0.113.24` no longer matches `203.0.113.241`).
- A remembered custom mount from the previous (pre-1.1.0) database format
  is migrated automatically on first refresh after upgrading, rather than
  being silently reinterpreted or discarded. The migration/warning
  diagnostics this logs now go to stderr, since the same function's
  stdout is read as mounts.db records by its caller - they no longer risk
  being piped into the database as if they were data, and are visible in
  the service journal.
- The Proxmox storage.cfg parser is now a standalone function
  (`parse_storage_cfg`) rather than inlined, so `tests/unit.sh` exercises
  the exact production parser against fixture files instead of a
  duplicated copy.
- Added `tests/unit.sh`, covering source-identity matching (including the
  trailing-slash exception), storage.cfg reconstruction, legacy database
  migration end-to-end through `refresh_mount_db()` (including that its
  diagnostics stay out of `mounts.db`), and existing enrollment/pending-set
  behavior; `tests/smoke.sh` no longer masks real `systemd-analyze verify`
  failures.

## 1.0.0 - 2026-09-10

- Initial repository version.
- IPv4-backed mount discovery from fstab, Proxmox NFS/CIFS storage, and live mounts.
- Automatic enrollment of dependent `onboot=1` LXCs using the `ipmount-gated` Proxmox tag.
- Boot-time enrollment ordered before `pve-guests.service`.
- Per-boot pending set so manually stopped LXCs are not restarted by the 60-second timer.
- Multiple external mount dependencies per LXC.
- Persistent memory for custom external mounts.
- Install, uninstall, status, discovery, manual start-now, unenroll, and forget-mount commands.
