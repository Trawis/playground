#!/usr/bin/env bash
set -euo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

for cmd in findmnt systemctl systemd-escape systemd-analyze logger; do
    command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd" >&2; exit 1; }
done

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

install -m 0755 "$SRC_DIR/pve-ip-mount-retry" /usr/local/sbin/pve-ip-mount-retry
install -m 0644 "$SRC_DIR/systemd/pve-ip-mount-retry.service" /etc/systemd/system/pve-ip-mount-retry.service
install -m 0644 "$SRC_DIR/systemd/pve-ip-mount-retry.timer" /etc/systemd/system/pve-ip-mount-retry.timer

bash -n /usr/local/sbin/pve-ip-mount-retry
systemd-analyze verify \
    /etc/systemd/system/pve-ip-mount-retry.service \
    /etc/systemd/system/pve-ip-mount-retry.timer

# daemon-reload also reruns systemd generators, including fstab mount-unit
# generation, so a newly added fstab entry gets a .mount unit before
# anything below relies on one existing.
systemctl daemon-reload

systemctl enable --now pve-ip-mount-retry.timer

# pve-ip-mount-gate is a separate, optional companion project. Only touch
# its timer/service if it is actually installed on this node.
GATE_TIMER="pve-ip-mount-gate.timer"
GATE_SERVICE="pve-ip-mount-gate.service"
gate_installed=0
if systemctl cat "$GATE_TIMER" >/dev/null 2>&1; then
    gate_installed=1
    systemctl enable --now "$GATE_TIMER"
fi

echo
echo "Triggering an immediate mount retry..."
systemctl start pve-ip-mount-retry.service

echo "Waiting a few seconds for network mount activation..."
sleep 5

if [[ $gate_installed -eq 1 ]]; then
    echo "Kicking pve-ip-mount-gate now instead of waiting for its next timer..."
    systemctl start "$GATE_SERVICE" || true
    sleep 3
fi

echo
echo "================================================================"
echo " IP-BACKED NETWORK MOUNTS"
echo "================================================================"
# TARGET/SOURCE/FSTYPE only - OPTIONS is deliberately omitted since a CIFS
# mount's options can carry a credentials= file path or embedded
# username=/password= and this summary is meant for diagnosis, not for
# echoing mount configuration.
findmnt -t cifs,nfs,nfs4 -o TARGET,SOURCE,FSTYPE || true

echo
echo "================================================================"
echo " FAILED UNITS"
echo "================================================================"
systemctl --failed --no-pager || true

echo
echo "================================================================"
echo " RETRY TIMER"
echo "================================================================"
systemctl status pve-ip-mount-retry.timer --no-pager || true

if [[ $gate_installed -eq 1 ]]; then
    echo
    echo "================================================================"
    echo " LXC GATE TIMER"
    echo "================================================================"
    systemctl status "$GATE_TIMER" --no-pager || true
fi

echo
echo "================================================================"
echo " RECENT MOUNT RETRY LOG"
echo "================================================================"
journalctl -u pve-ip-mount-retry.service -n 30 --no-pager || true

if [[ $gate_installed -eq 1 ]]; then
    echo
    echo "================================================================"
    echo " RECENT LXC GATE LOG"
    echo "================================================================"
    journalctl -u "$GATE_SERVICE" -n 30 --no-pager || true
fi

echo
echo "================================================================"
echo " CONTAINERS"
echo "================================================================"
if command -v pct >/dev/null; then
    pct list
else
    echo "  (pct not available)"
fi
