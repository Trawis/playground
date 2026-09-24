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
  from their documented `export`/`share` fields when possible; a `cifs:`
  entry with a `subdir` (whose resulting live source can't be reliably
  reconstructed here) keeps the previous, weaker server-address-only
  check.
- The server-address-only check (used only where full identity genuinely
  isn't available) is now an exact match on the extracted address rather
  than a substring check, fixing a related false-positive where a shorter
  address could be matched as a prefix of a longer, different one (e.g.
  `203.0.113.24` no longer matches `203.0.113.241`).
- A remembered custom mount from the previous (pre-1.1.0) database format
  is migrated automatically on first refresh after upgrading, rather than
  being silently reinterpreted or discarded.
- Added `tests/unit.sh`, covering source-identity matching, storage.cfg
  reconstruction, legacy database migration, and existing enrollment/
  pending-set behavior; `tests/smoke.sh` no longer masks real
  `systemd-analyze verify` failures.

## 1.0.0 - 2026-09-10

- Initial repository version.
- IPv4-backed mount discovery from fstab, Proxmox NFS/CIFS storage, and live mounts.
- Automatic enrollment of dependent `onboot=1` LXCs using the `ipmount-gated` Proxmox tag.
- Boot-time enrollment ordered before `pve-guests.service`.
- Per-boot pending set so manually stopped LXCs are not restarted by the 60-second timer.
- Multiple external mount dependencies per LXC.
- Persistent memory for custom external mounts.
- Install, uninstall, status, discovery, manual start-now, unenroll, and forget-mount commands.
