#!/usr/bin/env bash
set -euo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

for cmd in pct findmnt systemctl systemd-analyze flock timeout awk sed grep sort; do
    command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd" >&2; exit 1; }
done

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

install -d -m 0755 /etc/pve-ip-mount-gate
install -m 0750 "$SRC_DIR/pve-ip-mount-gate" /usr/local/sbin/pve-ip-mount-gate

if [[ ! -e /etc/default/pve-ip-mount-gate ]]; then
    install -m 0644 "$SRC_DIR/pve-ip-mount-gate.default" /etc/default/pve-ip-mount-gate
fi

install -m 0644 "$SRC_DIR/systemd/pve-ip-mount-gate-enroll.service" /etc/systemd/system/pve-ip-mount-gate-enroll.service
install -m 0644 "$SRC_DIR/systemd/pve-ip-mount-gate.service" /etc/systemd/system/pve-ip-mount-gate.service
install -m 0644 "$SRC_DIR/systemd/pve-ip-mount-gate.timer" /etc/systemd/system/pve-ip-mount-gate.timer

bash -n /usr/local/sbin/pve-ip-mount-gate
systemd-analyze verify \
    /etc/systemd/system/pve-ip-mount-gate-enroll.service \
    /etc/systemd/system/pve-ip-mount-gate.service \
    /etc/systemd/system/pve-ip-mount-gate.timer

systemctl daemon-reload

# Enroll current matching onboot=1 CTs now, but intentionally do not start
# stopped guests during installation. /run is reset at the next reboot, where
# the pre-pve-guests service builds the real boot pending set.
/usr/local/sbin/pve-ip-mount-gate --enroll
mkdir -p /run/pve-ip-mount-gate
: > /run/pve-ip-mount-gate/pending

systemctl enable pve-ip-mount-gate-enroll.service
systemctl enable --now pve-ip-mount-gate.timer

echo
echo "Installed pve-ip-mount-gate."
echo "No stopped CT was started by the installer."
echo
echo "Status:"
/usr/local/sbin/pve-ip-mount-gate --status
echo
echo "Logs: journalctl -fu pve-ip-mount-gate.service"
echo "Timer: systemctl status pve-ip-mount-gate.timer"
echo "To start one gated CT now: pve-ip-mount-gate --start-now CTID"
