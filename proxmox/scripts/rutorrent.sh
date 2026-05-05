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

# Optional: set HDD_PATH to a host-side path to bind-mount into the container at /data.
# Example: HDD_PATH=/mnt/pve/nas-data bash ct/rutorrent.sh
# For unprivileged LXC the host path must be owned by UID/GID 101000 (maps to container UID 1000).
HDD_PATH="${HDD_PATH:-}"

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

start
build_container

if [[ -n "${HDD_PATH}" ]]; then
  if [[ ! -d "${HDD_PATH}" ]]; then
    msg_error "HDD_PATH '${HDD_PATH}' does not exist on the host — skipping bind mount."
  else
    msg_info "Setting host ownership on ${HDD_PATH} (UID/GID 101000 for unprivileged LXC)"
    chown -R 101000:101000 "${HDD_PATH}"
    msg_ok "Host ownership set"
    msg_info "Adding bind mount: ${HDD_PATH} -> /data in CT ${CTID}"
    pct set "${CTID}" -mp0 "${HDD_PATH},mp=/data"
    msg_ok "Bind mount configured"
  fi
fi

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/${CL}"
echo -e "${INFO}${YW} Credentials are printed at the end of the install log.${CL}"
echo -e "${INFO}${YW} Downloads land in /data inside the container.${CL}"
if [[ -n "${HDD_PATH}" ]]; then
  echo -e "${INFO}${GN} Bind mount configured: ${HDD_PATH} -> /data${CL}"
else
  echo -e "${INFO}${YW} To mount host storage later, run on the Proxmox host:${CL}"
  echo -e "${TAB}  chown -R 101000:101000 /mnt/your/path${CL}"
  echo -e "${TAB}  pct set ${CTID} -mp0 /mnt/your/path,mp=/data${CL}"
fi
