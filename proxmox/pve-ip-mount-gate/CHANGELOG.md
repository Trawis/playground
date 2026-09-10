# Changelog

## 1.0.0 - 2026-09-10

- Initial repository version.
- IPv4-backed mount discovery from fstab, Proxmox NFS/CIFS storage, and live mounts.
- Automatic enrollment of dependent `onboot=1` LXCs using the `ipmount-gated` Proxmox tag.
- Boot-time enrollment ordered before `pve-guests.service`.
- Per-boot pending set so manually stopped LXCs are not restarted by the 60-second timer.
- Multiple external mount dependencies per LXC.
- Persistent memory for custom external mounts.
- Install, uninstall, status, discovery, manual start-now, unenroll, and forget-mount commands.
