#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$ROOT/pve-ip-mount-gate"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"
echo "Shell syntax OK"
if command -v systemd-analyze >/dev/null; then
    systemd-analyze verify \
        "$ROOT/systemd/pve-ip-mount-gate-enroll.service" \
        "$ROOT/systemd/pve-ip-mount-gate.service" \
        "$ROOT/systemd/pve-ip-mount-gate.timer" || true
fi
