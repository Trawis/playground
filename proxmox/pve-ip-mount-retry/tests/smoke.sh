#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$ROOT/pve-ip-mount-retry"
bash -n "$ROOT/install.sh"
echo "Shell syntax OK"
if command -v systemd-analyze >/dev/null; then
    systemd-analyze verify \
        "$ROOT/systemd/pve-ip-mount-retry.service" \
        "$ROOT/systemd/pve-ip-mount-retry.timer" || true
fi
