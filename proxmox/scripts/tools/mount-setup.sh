#!/usr/bin/env bash
# Run this script on the Proxmox host to add bind mounts to a ruTorrent LXC container.

set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLD='\033[1m'
RST='\033[0m'

die()  { echo -e "${RED}Error: $*${RST}" >&2; exit 1; }
info() { echo -e "${BLD}==> $*${RST}"; }
ok()   { echo -e "${GRN}  ✓ $*${RST}"; }
warn() { echo -e "${YLW}  ! $*${RST}"; }

require_cmd() { command -v "$1" &>/dev/null || die "'$1' not found. Run this script on the Proxmox host."; }
require_cmd pct
require_cmd findmnt

echo
echo -e "${BLD}ruTorrent LXC — Mount Point Setup${RST}"
echo "--------------------------------------"
echo

# ── 1. Pick a container ───────────────────────────────────────────────────────
info "Available LXC containers:"
pct list
echo
read -r -p "Enter container ID: " CTID
[[ "${CTID}" =~ ^[0-9]+$ ]] || die "Invalid container ID."
pct status "${CTID}" &>/dev/null   || die "Container ${CTID} not found."

CT_STATUS=$(pct status "${CTID}" | awk '{print $2}')
info "Container ${CTID} is ${CT_STATUS}."

# ── 2. Detect existing mount points ───────────────────────────────────────────
NEXT_MP=0
for i in $(seq 0 7); do
  if pct config "${CTID}" | grep -q "^mp${i}:"; then
    NEXT_MP=$(( i + 1 ))
  fi
done
info "Next available mount point index: mp${NEXT_MP}"

# ── 3. Host path ──────────────────────────────────────────────────────────────
echo
read -r -p "Host path to mount (e.g. /mnt/data): " HOST_PATH
[[ -n "${HOST_PATH}" ]]    || die "Host path cannot be empty."
[[ -d "${HOST_PATH}" ]]    || die "'${HOST_PATH}' does not exist on the host."

# ── 4. Container path ─────────────────────────────────────────────────────────
DEFAULT_CT_PATH="/data"
[[ ${NEXT_MP} -gt 0 ]] && DEFAULT_CT_PATH="/data${NEXT_MP}"
read -r -p "Container mount path [${DEFAULT_CT_PATH}]: " CT_PATH
[[ -z "${CT_PATH}" ]] && CT_PATH="${DEFAULT_CT_PATH}"

# ── 5. Detect filesystem — skip chown for network FS ─────────────────────────
FS_TYPE=$(findmnt -no FSTYPE "${HOST_PATH}" 2>/dev/null || echo "unknown")
info "Detected filesystem: ${FS_TYPE}"

NETWORK_FS=0
if [[ "${FS_TYPE}" =~ ^(cifs|nfs|nfs4|smb|fuse\.sshfs)$ ]]; then
  NETWORK_FS=1
  warn "Network filesystem detected (${FS_TYPE})."
  warn "Skipping chown — set uid/gid in your mount options instead:"
  echo
  echo "  For CIFS/SMB, add to /etc/fstab mount options:"
  echo "    uid=100999,gid=100999,file_mode=0664,dir_mode=0775"
  echo
  echo "  For NFS, configure anonuid/anongid on the NAS export, or use:"
  echo "    anonuid=100999,anongid=100999,sec=sys"
  echo
fi

# ── 6. Resolve container torrent UID on the host ──────────────────────────────
if [[ ${NETWORK_FS} -eq 0 ]]; then
  # Read the LXC UID map from the container config
  UID_BASE=$(grep -E '^lxc\.idmap.*u' "/etc/pve/lxc/${CTID}.conf" 2>/dev/null \
    | awk '{print $4}' | head -1)
  # Fall back to /etc/subuid for unprivileged default
  if [[ -z "${UID_BASE}" ]]; then
    UID_BASE=$(awk -F: '/^root/{print $2}' /etc/subuid 2>/dev/null | head -1)
  fi
  [[ -z "${UID_BASE}" ]] && UID_BASE=100000

  # The torrent user inside the container — detect from running container
  TORRENT_UID=999
  if [[ "${CT_STATUS}" == "running" ]]; then
    TORRENT_UID=$(pct exec "${CTID}" -- id -u torrent 2>/dev/null || echo 999)
  fi

  HOST_UID=$(( UID_BASE + TORRENT_UID ))
  HOST_GID=${HOST_UID}

  info "Container 'torrent' user: UID ${TORRENT_UID}  →  host UID ${HOST_UID}"
  echo
  CURRENT_OWNER=$(stat -c '%u:%g' "${HOST_PATH}")
  echo "  Current owner of ${HOST_PATH}: ${CURRENT_OWNER}"
  echo

  read -r -p "Recursively chown ${HOST_PATH} to ${HOST_UID}:${HOST_GID}? [y/N]: " DO_CHOWN
  if [[ "${DO_CHOWN}" =~ ^[Yy]$ ]]; then
    info "Setting ownership on ${HOST_PATH}..."
    chown -R "${HOST_UID}:${HOST_GID}" "${HOST_PATH}"
    ok "Ownership set to ${HOST_UID}:${HOST_GID}"
  else
    warn "Skipped chown. Make sure the container can write to ${HOST_PATH}."
  fi
fi

# ── 7. Stop container if running ──────────────────────────────────────────────
echo
if [[ "${CT_STATUS}" == "running" ]]; then
  read -r -p "Container is running. Stop it to apply the mount? [Y/n]: " DO_STOP
  if [[ ! "${DO_STOP}" =~ ^[Nn]$ ]]; then
    info "Stopping container ${CTID}..."
    pct stop "${CTID}"
    ok "Container stopped."
    RESTART_AFTER=1
  else
    warn "Mount will be applied but may not take effect until next restart."
    RESTART_AFTER=0
  fi
else
  RESTART_AFTER=0
fi

# ── 8. Apply the bind mount ───────────────────────────────────────────────────
info "Applying bind mount mp${NEXT_MP}: ${HOST_PATH} → ${CT_PATH}"
pct set "${CTID}" "-mp${NEXT_MP}" "${HOST_PATH},mp=${CT_PATH}"
ok "Bind mount configured."

# ── 9. Start the container ────────────────────────────────────────────────────
if [[ "${RESTART_AFTER}" -eq 1 ]]; then
  info "Starting container ${CTID}..."
  pct start "${CTID}"
  ok "Container started."
fi

# ── 10. Summary ───────────────────────────────────────────────────────────────
echo
echo -e "${BLD}Done.${RST}"
echo
echo "  Container : ${CTID}"
echo "  Mount     : ${HOST_PATH} → ${CT_PATH} (mp${NEXT_MP})"
if [[ ${NETWORK_FS} -eq 0 ]]; then
  echo "  Host UID  : ${HOST_UID}:${HOST_GID}"
fi
echo
echo "To point rTorrent at this path, edit inside the container:"
echo "  /var/lib/rtorrent/.rtorrent.rc"
echo "  directory.default.set = ${CT_PATH}"
echo
echo "Then restart rTorrent:"
echo "  systemctl restart rtorrent"
echo
