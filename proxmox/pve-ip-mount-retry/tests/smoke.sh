#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/pve-ip-mount-retry"
bash -n "$ROOT/install.sh"
echo "Shell syntax OK"

if command -v systemd-analyze >/dev/null; then
    if verify_output="$(systemd-analyze verify \
        "$ROOT/systemd/pve-ip-mount-retry.service" \
        "$ROOT/systemd/pve-ip-mount-retry.timer" 2>&1)"; then
        echo "systemd-analyze verify: OK"
    else
        # In a repo checkout (as opposed to an installed system) ExecStart
        # points at /usr/local/sbin/pve-ip-mount-retry, which doesn't exist
        # there yet. That specific, expected complaint is tolerated; any
        # other verify output is a real problem and must fail this check.
        unexpected="$(printf '%s\n' "$verify_output" | grep -vE 'is not executable: No such file or directory|^$' || true)"
        if [[ -n "$unexpected" ]]; then
            echo "$verify_output" >&2
            echo "systemd-analyze verify failed with unexpected errors" >&2
            exit 1
        fi
        echo "systemd-analyze verify: only the expected uninstalled-binary warning (OK in a repo checkout)"
    fi
else
    echo "systemd-analyze not available; skipping unit verification"
fi

"$ROOT/tests/unit.sh"
