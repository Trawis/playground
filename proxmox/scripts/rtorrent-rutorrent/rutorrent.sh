#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Novik/ruTorrent | https://rakshasa.github.io/rtorrent/

APP="ruTorrent"
var_tags="${var_tags:-torrent;downloads}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# Optional: mount one or more host paths into the container.
# For unprivileged LXC all host paths must be owned by UID/GID 101000 (maps to container UID 1000).
#
# Single mount (maps to /data):
#   HDD_PATH=/mnt/hdd bash rutorrent.sh
#
# Multiple mounts — space-separated, each entry is hostpath:containerpath.
# Container paths default to /data, /data2, /data3 ... if omitted:
#   HDD_PATHS="/mnt/hdd1 /mnt/hdd2:/downloads" bash rutorrent.sh
#
# HDD_PATH is kept for backward compatibility and is equivalent to
# adding /mnt/path:/data as the first entry in HDD_PATHS.
HDD_PATH="${HDD_PATH:-}"
HDD_PATHS="${HDD_PATHS:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/www/rutorrent || ! -f /home/torrent/.rtorrent.rc ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP} (apt)"
  $STD apt-get update
  $STD apt-get -y dist-upgrade
  msg_ok "Updated base packages"

  msg_info "Updating ruTorrent"
  if [[ -d /var/www/rutorrent/.git ]]; then
    git -C /var/www/rutorrent fetch --all -q
    git -C /var/www/rutorrent reset --hard origin/master -q
  else
    rm -rf /var/www/rutorrent
    $STD git clone https://github.com/Novik/ruTorrent.git /var/www/rutorrent
  fi
  chown -R www-data:www-data /var/www/rutorrent
  msg_ok "Updated ruTorrent"

  msg_info "Restarting services"
  systemctl restart php*-fpm nginx rtorrent
  msg_ok "Services restarted"

  exit
}

INSTALL_URL="https://raw.githubusercontent.com/Trawis/playground/refs/heads/main/proxmox/scripts/rtorrent-rutorrent/rutorrent-install.sh"

start
build_container

msg_info "Running ruTorrent installer"
lxc-attach -n "$CTID" -- bash -c "$(curl -fsSL ${INSTALL_URL})"
msg_ok "Installer complete"

# Build the final list of mounts: HDD_PATH (legacy) prepended to HDD_PATHS
MOUNT_LIST=""
[[ -n "${HDD_PATH}" ]] && MOUNT_LIST="${HDD_PATH}:/data"
[[ -n "${HDD_PATHS}" ]] && MOUNT_LIST="${MOUNT_LIST:+${MOUNT_LIST} }${HDD_PATHS}"

CONFIGURED_MOUNTS=()
if [[ -n "${MOUNT_LIST}" ]]; then
  MP_INDEX=0
  DEFAULT_CT_PATHS=(/data /data2 /data3 /data4 /data5 /data6 /data7 /data8)

  for ENTRY in ${MOUNT_LIST}; do
    HOST_PATH="${ENTRY%%:*}"
    # Use explicit container path if provided, else fall back to /data, /data2, ...
    if [[ "${ENTRY}" == *:* ]]; then
      CT_PATH="${ENTRY##*:}"
    else
      CT_PATH="${DEFAULT_CT_PATHS[${MP_INDEX}]:-/data${MP_INDEX}}"
    fi

    if [[ ! -d "${HOST_PATH}" ]]; then
      msg_error "Mount ${MP_INDEX}: '${HOST_PATH}' does not exist on host — skipping"
      MP_INDEX=$((MP_INDEX + 1))
      continue
    fi

    msg_info "Mount mp${MP_INDEX}: setting host ownership on ${HOST_PATH} (UID/GID 101000)"
    chown -R 101000:101000 "${HOST_PATH}"
    msg_ok "Host ownership set on ${HOST_PATH}"

    msg_info "Mount mp${MP_INDEX}: ${HOST_PATH} -> ${CT_PATH} in CT ${CTID}"
    pct set "${CTID}" -mp${MP_INDEX} "${HOST_PATH},mp=${CT_PATH}"
    msg_ok "Bind mount mp${MP_INDEX} configured"

    CONFIGURED_MOUNTS+=("${HOST_PATH} -> ${CT_PATH}")
    MP_INDEX=$((MP_INDEX + 1))
  done
fi

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/${CL}"
echo -e "${INFO}${YW} Credentials are printed at the end of the install log.${CL}"
echo -e "${INFO}${YW} Primary download dir inside container: /data${CL}"

if [[ ${#CONFIGURED_MOUNTS[@]} -gt 0 ]]; then
  echo -e "${INFO}${GN} Bind mounts configured:${CL}"
  for M in "${CONFIGURED_MOUNTS[@]}"; do
    echo -e "${TAB}  ${M}${CL}"
  done
else
  echo -e "${INFO}${YW} No bind mounts configured. To add storage later, run on the Proxmox host:${CL}"
  echo -e "${TAB}  chown -R 101000:101000 /mnt/your/path${CL}"
  echo -e "${TAB}  pct set ${CTID} -mp0 /mnt/your/path,mp=/data${CL}"
fi
