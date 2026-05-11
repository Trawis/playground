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

# Web UI auth username — set here or answered interactively in Advanced mode.
# Example: RUTORRENT_USER=admin bash rutorrent.sh
RUTORRENT_USER="${RUTORRENT_USER:-torrent}"

# Space-separated whitelist of ruTorrent plugins to enable after install.
# Set via env to skip interactive prompts entirely, e.g.:
#   RUTORRENT_PLUGINS="autotools ratio unpack" bash rutorrent.sh
RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS:-}"

# Expose nginx /RPC2 endpoint (rTorrent XMLRPC/SCGI).
# Off by default — enable only if you need external XMLRPC access.
# When enabled it is still protected by HTTP basic auth.
# Example: RUTORRENT_ENABLE_RPC2=1 bash rutorrent.sh
RUTORRENT_ENABLE_RPC2="${RUTORRENT_ENABLE_RPC2:-0}"

# Set to 1 to allow the installer to chown the host mount path to UID/GID 101000.
# Leave at 0 for CIFS/NFS/Synology shares — set uid/gid in mount options instead.
# Example: CHOWN_MOUNTS=1 HDD_PATH=/mnt/data bash rutorrent.sh
CHOWN_MOUNTS="${CHOWN_MOUNTS:-0}"

# Max .torrent upload size in MiB — applied to PHP, nginx, and ruTorrent filedrop.
# Example: RUTORRENT_MAX_UPLOAD_MB=64 bash rutorrent.sh
RUTORRENT_MAX_UPLOAD_MB="${RUTORRENT_MAX_UPLOAD_MB:-32}"

# Install vsftpd FTP server. Off by default. Creates a separate FTP user/password.
# Example: INSTALL_FTP=1 bash rutorrent.sh
INSTALL_FTP="${INSTALL_FTP:-0}"

# ── Plugin catalogue ──────────────────────────────────────────────────────────
# Format: "name|description|default_on|requires_privileged"
#   default_on:          "on"  = selected by default
#                        "off" = not selected by default
#   requires_privileged: 1    = needs privileged LXC (kernel feature)
#                        0    = works in unprivileged container
PLUGIN_DEFS=(
  "autotools|Auto-tools: labels and move-on-completion|on|0"
  "bulk_magnet|Bulk magnet link handler|on|0"
  "chunks|Piece/chunk map viewer|on|0"
  "cookies|Cookie manager for private trackers|on|0"
  "create|Create .torrent files|on|0"
  "data|Torrent data view|on|0"
  "datadir|Per-torrent data directory|on|0"
  "edit|Edit tracker URLs|on|0"
  "erasedata|Erase data on removal|on|0"
  "extsearch|External search engines|on|0"
  "extratio|Extended ratio rules|on|0"
  "feeds|RSS feeds manager|on|0"
  "filedrop|Drag-and-drop .torrent upload|on|0"
  "filemanager|File manager|on|0"
  "filemanager-media|File manager media preview|on|0"
  "history|Download history|on|0"
  "httprpc|HTTP RPC for mobile clients|on|0"
  "ipad|iPad-optimised interface|on|0"
  "loginmgr|Login manager|on|0"
  "lookat|Open file/directory on server|on|0"
  "mediainfo|Media information display|on|0"
  "ratio|Ratio groups|on|0"
  "rss|RSS downloader|on|0"
  "rssurlrewrite|RSS URL rewrite rules|on|0"
  "scheduler|Speed scheduler|on|0"
  "screenshots|Screenshot generator|on|0"
  "seedingtime|Seeding time column|on|0"
  "show_peers_like_wtorrent|Extended peer list|on|0"
  "source|Torrent source display|on|0"
  "spectrogram|Audio spectrogram (requires sox)|on|0"
  "theme|Theme selector|on|0"
  "tracklabels|Tracker-based labels|on|0"
  "trafic|Traffic chart|on|0"
  "unpack|Auto-unpack archives (requires unrar/7z)|on|0"
  "xmpp|XMPP/Jabber notifications|off|0"
  "throttle|Speed throttle (requires privileged LXC)|off|1"
  "dump|Dump torrent info (not available on Debian 10+)|off|0"
  "geoip2|GeoIP2 peer location (not yet implemented)|off|0"
  "pausewebui|Pause web UI (not yet implemented)|off|0"
  "quotaspace|Disk quota manager (not yet implemented)|off|0"
  "retrackers|Russian retrackers (not yet implemented)|off|0"
  "rutracker_check|Rutracker.org checker (not yet implemented)|off|0"
  "uploadeta|Upload ETA display (not yet implemented)|off|0"
)

header_info "$APP"
variables
color
catch_errors

# ── Installation mode ─────────────────────────────────────────────────────────
# Skip prompts entirely if RUTORRENT_PLUGINS was set in the environment.
if [[ -z "${RUTORRENT_PLUGINS}" ]]; then
  echo ""
  echo -e "${INFO}${YW} Installation mode:${CL}"
  echo -e "${TAB}  1) Default  — unprivileged container, standard plugin set, username: torrent"
  echo -e "${TAB}  2) Advanced — choose container type, username, and plugins"
  read -r -p "   Select [1/2, default: 1]: " _MODE

  if [[ "${_MODE}" == "2" ]]; then
    # ── Advanced mode ──────────────────────────────────────────────────────────
    read -r -p "   Privileged container? [y/N]: " _PRIV
    [[ "${_PRIV}" =~ ^[Yy]$ ]] && var_unprivileged=0

    read -r -p "   Web UI username [torrent]: " _USER
    [[ -n "${_USER}" ]] && RUTORRENT_USER="${_USER}"

    read -r -p "   Expose /RPC2 over nginx (XMLRPC access)? [y/N]: " _RPC2
    [[ "${_RPC2}" =~ ^[Yy]$ ]] && RUTORRENT_ENABLE_RPC2=1

    if [[ -n "${HDD_PATH}" || -n "${HDD_PATHS}" ]]; then
      read -r -p "   Recursively chown host mount path(s) to UID/GID 101000? [y/N]: " _CHOWN
      [[ "${_CHOWN}" =~ ^[Yy]$ ]] && CHOWN_MOUNTS=1
    fi

    read -r -p "   Max .torrent upload size in MiB [32]: " _UPLOAD_MB
    [[ "${_UPLOAD_MB}" =~ ^[0-9]+$ ]] && RUTORRENT_MAX_UPLOAD_MB="${_UPLOAD_MB}"

    read -r -p "   Install FTP server (vsftpd, separate user/password)? [y/N]: " _FTP
    [[ "${_FTP}" =~ ^[Yy]$ ]] && INSTALL_FTP=1

    # Build whiptail checklist
    _WHIP_ITEMS=()
    for _DEF in "${PLUGIN_DEFS[@]}"; do
      IFS='|' read -r _PNAME _PDESC _PDEF _PPRIV <<< "${_DEF}"
      if [[ "${_PPRIV}" == "1" && "${var_unprivileged}" == "1" ]]; then
        _PDEF="off"
        _PDESC="${_PDESC} [privileged only]"
      fi
      _WHIP_ITEMS+=("${_PNAME}" "${_PDESC}" "${_PDEF}")
    done

    _LIST_H=$(( ${#PLUGIN_DEFS[@]} < 20 ? ${#PLUGIN_DEFS[@]} : 20 ))
    _BOX_H=$(( _LIST_H + 8 ))

    _SEL="$(whiptail --title "ruTorrent — Plugin Selection" \
      --checklist "Space to toggle, Enter to confirm" \
      "${_BOX_H}" 76 "${_LIST_H}" \
      "${_WHIP_ITEMS[@]}" 3>&1 1>&2 2>&3)" || true

    RUTORRENT_PLUGINS="$(echo "${_SEL}" | tr -d '"')"

  else
    # ── Default / silent mode ──────────────────────────────────────────────────
    for _DEF in "${PLUGIN_DEFS[@]}"; do
      IFS='|' read -r _PNAME _PDESC _PDEF _PPRIV <<< "${_DEF}"
      [[ "${_PPRIV}" == "1" && "${var_unprivileged}" == "1" ]] && continue
      [[ "${_PDEF}" == "on" ]] && RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS} ${_PNAME}"
    done
    RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS# }"
  fi
fi

# Strip any privileged-only plugin if the container is unprivileged
if [[ "${var_unprivileged}" == "1" ]]; then
  _FILTERED=""
  for _P in ${RUTORRENT_PLUGINS}; do
    _REQ=0
    for _DEF in "${PLUGIN_DEFS[@]}"; do
      IFS='|' read -r _PNAME _ _ _PPRIV <<< "${_DEF}"
      [[ "${_PNAME}" == "${_P}" && "${_PPRIV}" == "1" ]] && { _REQ=1; break; }
    done
    if [[ "${_REQ}" == "1" ]]; then
      msg_warn "Plugin '${_P}' requires a privileged container — skipping"
    else
      _FILTERED="${_FILTERED} ${_P}"
    fi
  done
  RUTORRENT_PLUGINS="${_FILTERED# }"
fi

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/www/rutorrent || ! -f /home/torrent/.rtorrent.rc ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CURRENT_VERSION="$(cat /opt/ruTorrent_version.txt 2>/dev/null || echo 'unknown')"
  LATEST_VERSION="$(curl -fsSL https://api.github.com/repos/Novik/ruTorrent/releases/latest | grep '"tag_name":' | cut -d'"' -f4)"

  if [[ "${CURRENT_VERSION}" == "${LATEST_VERSION}" ]]; then
    msg_ok "ruTorrent is already up to date (${CURRENT_VERSION})"
  else
    msg_info "Updating ruTorrent ${CURRENT_VERSION} -> ${LATEST_VERSION}"
    if [[ -d /var/www/rutorrent/.git ]]; then
      # Shallow clone from install won't have tags; unshallow before fetching
      git -C /var/www/rutorrent fetch --unshallow -q 2>/dev/null || true
      git -C /var/www/rutorrent fetch --tags -q
      git -C /var/www/rutorrent checkout -q "${LATEST_VERSION}"
    else
      rm -rf /var/www/rutorrent
      $STD git clone --depth 1 --branch "${LATEST_VERSION}" https://github.com/Novik/ruTorrent.git /var/www/rutorrent
    fi
    echo "${LATEST_VERSION}" > /opt/ruTorrent_version.txt
    chown -R www-data:www-data /var/www/rutorrent
    msg_ok "Updated ruTorrent to ${LATEST_VERSION}"
  fi

  msg_info "Updating base packages"
  $STD apt-get update
  $STD apt-get -y dist-upgrade
  msg_ok "Updated base packages"

  msg_info "Ensuring all dependencies are installed"
  $STD apt-get install -y \
    python3 python-is-python3 sox \
    mediainfo ffmpeg apache2-utils \
    php-curl php-mbstring php-xml php-zip
  msg_ok "Dependencies up to date"

  msg_info "Restarting services"
  systemctl restart php*-fpm nginx rtorrent
  msg_ok "Services restarted"

  exit
}

start
build_container

# NOTE: The lxc-attach block below is required when running from a fork because
# build.func fetches the install script from community-scripts/ProxmoxVE (hardcoded)
# and 404s since this script is not yet in the official repo.
# When submitted upstream, build.func will find and run the install script
# automatically — remove this block before opening a PR to community-scripts.
INSTALL_URL="https://raw.githubusercontent.com/Trawis/playground/refs/heads/main/proxmox/scripts/rtorrent-rutorrent/rutorrent-install.sh"
msg_info "Running ruTorrent installer"
lxc-attach -n "$CTID" -- env \
  RUTORRENT_USER="${RUTORRENT_USER}" \
  RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS}" \
  RUTORRENT_ENABLE_RPC2="${RUTORRENT_ENABLE_RPC2}" \
  RUTORRENT_MAX_UPLOAD_MB="${RUTORRENT_MAX_UPLOAD_MB}" \
  INSTALL_FTP="${INSTALL_FTP}" \
  bash -c "$(curl -fsSL ${INSTALL_URL})"
msg_ok "Installer complete"

# Build the final list of mounts: HDD_PATH (legacy) prepended to HDD_PATHS
MOUNT_LIST=""
[[ -n "${HDD_PATH}" ]] && MOUNT_LIST="${HDD_PATH}:/data"
[[ -n "${HDD_PATHS}" ]] && MOUNT_LIST="${MOUNT_LIST:+${MOUNT_LIST} }${HDD_PATHS}"

CONFIGURED_MOUNTS=()
if [[ -n "${MOUNT_LIST}" ]]; then
  MP_INDEX=0
  DEFAULT_MP_CT_PATHS=(/data /data2 /data3 /data4 /data5 /data6 /data7 /data8)

  for ENTRY in ${MOUNT_LIST}; do
    MP_HOST_PATH="${ENTRY%%:*}"
    if [[ "${ENTRY}" == *:* ]]; then
      MP_CT_PATH="${ENTRY##*:}"
    else
      MP_CT_PATH="${DEFAULT_MP_CT_PATHS[${MP_INDEX}]:-/data${MP_INDEX}}"
    fi

    if [[ ! -d "${MP_HOST_PATH}" ]]; then
      msg_error "Mount ${MP_INDEX}: '${MP_HOST_PATH}' does not exist on host — skipping"
      MP_INDEX=$((MP_INDEX + 1))
      continue
    fi

    if [[ "${CHOWN_MOUNTS}" == "1" ]]; then
      MP_FS_TYPE="$(findmnt -no FSTYPE "${MP_HOST_PATH}" 2>/dev/null)"
      if [[ "${MP_FS_TYPE}" =~ ^(cifs|nfs|nfs4|smb|fuse\.sshfs)$ ]]; then
        msg_warn "Skipping chown on ${MP_HOST_PATH} (${MP_FS_TYPE}) — set uid=101000,gid=101000 in your mount options instead"
      else
        msg_info "Mount mp${MP_INDEX}: setting host ownership on ${MP_HOST_PATH} (UID/GID 101000)"
        chown -R 101000:101000 "${MP_HOST_PATH}"
        msg_ok "Host ownership set on ${MP_HOST_PATH}"
      fi
    else
      msg_warn "Skipping chown on ${MP_HOST_PATH} — set CHOWN_MOUNTS=1 to enable, or ensure UID/GID 101000 can write there"
    fi

    msg_info "Mount mp${MP_INDEX}: ${MP_HOST_PATH} -> ${MP_CT_PATH} in CT ${CTID}"
    pct set "${CTID}" -mp${MP_INDEX} "${MP_HOST_PATH},mp=${MP_CT_PATH}"
    msg_ok "Bind mount mp${MP_INDEX} configured"

    CONFIGURED_MOUNTS+=("${MP_HOST_PATH} -> ${MP_CT_PATH}")
    MP_INDEX=$((MP_INDEX + 1))
  done

  if [[ ${#CONFIGURED_MOUNTS[@]} -gt 0 ]]; then
    msg_info "Restarting CT ${CTID} to activate bind mounts"
    pct stop "${CTID}"
    pct start "${CTID}"
    msg_ok "Container restarted — bind mounts are now active"
  fi
fi

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/${CL}"
echo -e "${INFO}${YW} Credentials:${CL}"
pct exec "${CTID}" -- grep -A4 "ruTorrent credentials" /etc/motd 2>/dev/null || echo -e "${TAB}  Run: pct exec ${CTID} -- cat /etc/motd${CL}"
echo -e "${INFO}${YW} Primary download dir inside container: /data${CL}"

if [[ ${#CONFIGURED_MOUNTS[@]} -gt 0 ]]; then
  echo -e "${INFO}${GN} Bind mounts configured:${CL}"
  for M in "${CONFIGURED_MOUNTS[@]}"; do
    echo -e "${TAB}  ${M}${CL}"
  done
else
  echo -e "${INFO}${YW} No bind mounts configured. To add storage later, see README.md${CL}"
fi
