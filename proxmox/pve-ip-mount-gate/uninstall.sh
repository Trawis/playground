#!/usr/bin/env bash
set -euo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

RESTORE=0
[[ "${1:-}" == "--restore-onboot" ]] && RESTORE=1

GATE_TAG="ipmount-gated"
[[ -r /etc/default/pve-ip-mount-gate ]] && source /etc/default/pve-ip-mount-gate

if [[ $RESTORE -eq 1 && -x /usr/local/sbin/pve-ip-mount-gate ]]; then
    # Restore only local CTs carrying the configured gate tag.
    mapfile -t CTS < <(
        pct list 2>/dev/null | awk 'NR>1 {print $1}' | while read -r id; do
            tags="$(pct config "$id" 2>/dev/null | awk -F': ' '$1 == "tags" {print $2; exit}')"
            tr ';' '\n' <<<"$tags" | grep -qxF "$GATE_TAG" && echo "$id" || true
        done
    )
    for id in "${CTS[@]:-}"; do
        [[ -n "$id" ]] || continue
        /usr/local/sbin/pve-ip-mount-gate --unenroll-onboot "$id" || true
    done
fi

systemctl disable --now pve-ip-mount-gate.timer 2>/dev/null || true
systemctl disable pve-ip-mount-gate-enroll.service 2>/dev/null || true
rm -f /etc/systemd/system/pve-ip-mount-gate-enroll.service
rm -f /etc/systemd/system/pve-ip-mount-gate.service
rm -f /etc/systemd/system/pve-ip-mount-gate.timer
rm -f /usr/local/sbin/pve-ip-mount-gate
systemctl daemon-reload

echo "Removed service/timer/script."
if [[ $RESTORE -eq 0 ]]; then
    echo "CT onboot/tag settings were left unchanged."
    echo "Use ./uninstall.sh --restore-onboot before removal if you want tagged local CTs restored to onboot=1."
fi

echo "Persistent state remains in /etc/pve-ip-mount-gate and /etc/default/pve-ip-mount-gate for audit/reinstall."
