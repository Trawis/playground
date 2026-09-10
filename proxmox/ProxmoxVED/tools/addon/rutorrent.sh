#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trawis
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
load_functions

function header_info() {
  clear
  cat <<"EOF"
                 _____                          _
  _ __ _   _   |_   _|__  _ __ _ __ ___ _ __ | |_
 | '__| | | |    | |/ _ \| '__| '__/ _ \ '_ \| __|
 | |  | |_| |    | | (_) | |  | | |  __/ | | | |_
 |_|   \__,_|    |_|\___/|_|  |_|  \___|_| |_|\__|
                  Reconfigure
EOF
}

root_check

if [[ ! -d /var/www/rutorrent ]]; then
  msg_error "No ruTorrent installation found. Run this script inside the ruTorrent container."
  exit 1
fi

NGINX_CONF=/etc/nginx/sites-available/rutorrent
HTPASSWD=/etc/nginx/.rutorrent_htpasswd
PLUGINS_INI=/var/www/rutorrent/conf/plugins.ini
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.4")
PHP_UPLOAD_INI=/etc/php/${PHP_VER}/fpm/conf.d/99-rutorrent-upload.ini
FILEDROP_CONF=/var/www/rutorrent/plugins/filedrop/conf.php
RTORRENT_RC=/root/.rtorrent.rc
TLS_CERT=/etc/nginx/rutorrent-selfsigned.crt
TLS_KEY=/etc/nginx/rutorrent-selfsigned.key

detect_upload_limit() {
  grep -oP 'client_max_body_size \K[0-9]+' "$NGINX_CONF" 2>/dev/null || echo "32"
}

detect_port() {
  grep -oP 'network\.port_range\.set = \K[0-9]+' "$RTORRENT_RC" 2>/dev/null || echo "50000"
}

detect_storage_base() {
  local download_dir
  download_dir=$(grep -oP 'directory\.default\.set = \K.*' "$RTORRENT_RC" 2>/dev/null)
  [[ -n "$download_dir" ]] && dirname "$download_dir" || echo "/var/lib/rtorrent"
}

wait_for_rtorrent_socket() {
  local i
  for i in $(seq 1 20); do
    [[ -S /run/rtorrent/rtorrent.sock ]] && return 0
    sleep 1
  done
  return 1
}

detect_rpc2() {
  grep -q 'location /RPC2' "$NGINX_CONF" 2>/dev/null && echo "yes" || echo "no"
}

detect_real_ip() {
  grep -q 'set_real_ip_from' "$NGINX_CONF" 2>/dev/null && echo "yes" || echo "no"
}

detect_tls() {
  grep -q 'listen 443 ssl' "$NGINX_CONF" 2>/dev/null && echo "yes" || echo "no"
}

ensure_selfsigned_cert() {
  [[ -f "$TLS_CERT" && -f "$TLS_KEY" ]] && return 0

  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$TLS_KEY" -out "$TLS_CERT" -days 3650 \
    -subj "/CN=rutorrent" &>/dev/null
  chmod 600 "$TLS_KEY"
}

write_nginx_conf() {
  local upload_mb="$1" enable_rpc2="$2" enable_real_ip="$3" enable_tls="${4:-no}"
  local rpc2_block="" real_ip_block="" tls_block=""

  if [[ "$enable_tls" == "yes" ]]; then
    ensure_selfsigned_cert
    tls_block="
    listen 443 ssl;
    ssl_certificate ${TLS_CERT};
    ssl_certificate_key ${TLS_KEY};
"
  fi

  if [[ "$enable_rpc2" == "yes" ]]; then
    rpc2_block="
    location /RPC2 {
        include scgi_params;
        scgi_pass unix:///run/rtorrent/rtorrent.sock;
    }
"
  fi

  if [[ "$enable_real_ip" == "yes" ]]; then
    real_ip_block="
    set_real_ip_from 127.0.0.1;
    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 192.168.0.0/16;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;
"
  fi

  local backup="${NGINX_CONF}.bak.$$"
  if [[ -f "$NGINX_CONF" ]]; then
    cp "$NGINX_CONF" "$backup"
  fi

  cat <<EOF >"$NGINX_CONF"
server {
    listen 80;
    server_name _;
${tls_block}

    root /var/www/rutorrent;
    index index.html index.php;

    client_max_body_size ${upload_mb}M;

    auth_basic "ruTorrent";
    auth_basic_user_file /etc/nginx/.rutorrent_htpasswd;
${real_ip_block}${rpc2_block}
    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/rutorrent-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

  if ! nginx -t &>/dev/null; then
    if [[ -f "$backup" ]]; then
      mv "$backup" "$NGINX_CONF"
      msg_error "nginx config test failed — reverted to previous config"
    else
      rm -f "$NGINX_CONF"
      msg_error "nginx config test failed — no previous config to revert to, removed invalid config"
    fi
    return 1
  fi

  rm -f "$backup"
}

action_change_password() {
  header_info
  local users username newpass

  users=$(awk -F: '{print $1}' "$HTPASSWD" 2>/dev/null | tr '\n' '  ')

  username=$(whiptail --inputbox \
    "Username to update (or new username to add):\n\nExisting: ${users}" \
    10 60 "" --title "Change Password" 3>&1 1>&2 2>&3) || return
  [[ -z "$username" ]] && return

  newpass=$(whiptail --passwordbox \
    "New password for '${username}':\n\n(leave blank to generate random)" \
    10 55 "" --title "Change Password" 3>&1 1>&2 2>&3) || return

  [[ -z "$newpass" ]] && newpass=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)

  htpasswd -b "$HTPASSWD" "$username" "$newpass" &>/dev/null
  systemctl reload nginx

  msg_ok "Password updated for '${username}'"
  msg_info "New password: ${newpass}"
  echo ""
  read -rp "Press Enter to continue..."
}

action_toggle_rpc2() {
  header_info
  local current rpc2_new
  current=$(detect_rpc2)

  if [[ "$current" == "yes" ]]; then
    whiptail --yesno "/RPC2 is currently ENABLED.\n\nDisable it?" \
      9 55 --title "Toggle /RPC2" 3>&1 1>&2 2>&3 || return
    rpc2_new="no"
  else
    whiptail --yesno "/RPC2 is currently DISABLED.\n\nEnable it?\n(required for Sonarr, Radarr, autodl-irssi)" \
      10 58 --title "Toggle /RPC2" 3>&1 1>&2 2>&3 || return
    rpc2_new="yes"
  fi

  write_nginx_conf "$(detect_upload_limit)" "$rpc2_new" "$(detect_real_ip)" "$(detect_tls)" || {
    read -rp "Press Enter to continue..."
    return
  }
  systemctl reload nginx
  msg_ok "/RPC2 endpoint $([ "$rpc2_new" = "yes" ] && echo "enabled" || echo "disabled")"
  echo ""
  read -rp "Press Enter to continue..."
}

action_toggle_real_ip() {
  header_info
  local current real_ip_new
  current=$(detect_real_ip)

  if [[ "$current" == "yes" ]]; then
    whiptail --yesno "Real IP forwarding is currently ENABLED.\n\nDisable it?" \
      9 58 --title "Toggle Real IP" 3>&1 1>&2 2>&3 || return
    real_ip_new="no"
  else
    whiptail --yesno "Real IP forwarding is currently DISABLED.\n\nEnable it?\n(only for reverse proxy setups: Traefik, Cloudflare, NPM)" \
      11 62 --title "Toggle Real IP" 3>&1 1>&2 2>&3 || return
    real_ip_new="yes"
  fi

  write_nginx_conf "$(detect_upload_limit)" "$(detect_rpc2)" "$real_ip_new" "$(detect_tls)" || {
    read -rp "Press Enter to continue..."
    return
  }
  systemctl reload nginx
  msg_ok "Real IP forwarding $([ "$real_ip_new" = "yes" ] && echo "enabled" || echo "disabled")"
  echo ""
  read -rp "Press Enter to continue..."
}

action_toggle_tls() {
  header_info
  local current tls_new

  current=$(detect_tls)

  if [[ "$current" == "yes" ]]; then
    whiptail --yesno "HTTPS is currently ENABLED.\n\nDisable it? (HTTP on port 80 stays available either way)" \
      10 60 --title "Toggle HTTPS" 3>&1 1>&2 2>&3 || return
    tls_new="no"
  else
    whiptail --yesno "HTTPS is currently DISABLED.\n\nEnable it?\n\nUses a self-signed certificate — browsers will show a\nwarning until you accept/trust it. HTTP on port 80\nstays available alongside it." \
      13 62 --title "Toggle HTTPS" 3>&1 1>&2 2>&3 || return
    tls_new="yes"
  fi

  write_nginx_conf "$(detect_upload_limit)" "$(detect_rpc2)" "$(detect_real_ip)" "$tls_new" || {
    read -rp "Press Enter to continue..."
    return
  }
  systemctl reload nginx
  msg_ok "HTTPS $([ "$tls_new" = "yes" ] && echo "enabled (self-signed cert)" || echo "disabled")"
  echo ""
  read -rp "Press Enter to continue..."
}

action_change_upload_limit() {
  header_info
  local current_mb new_mb

  current_mb=$(detect_upload_limit)

  new_mb=$(whiptail --inputbox \
    "Maximum upload file size in MiB:\n(applied to nginx, PHP, and filedrop plugin)" \
    10 58 "$current_mb" --title "Upload Limit" 3>&1 1>&2 2>&3) || return
  [[ -z "$new_mb" ]] && return

  if ! [[ "$new_mb" =~ ^[0-9]+$ ]] || [[ "$new_mb" -lt 1 ]]; then
    msg_error "Invalid value — must be a positive integer"
    read -rp "Press Enter to continue..."
    return
  fi

  write_nginx_conf "$new_mb" "$(detect_rpc2)" "$(detect_real_ip)" "$(detect_tls)" || {
    read -rp "Press Enter to continue..."
    return
  }

  cat <<EOF >"$PHP_UPLOAD_INI"
upload_max_filesize = ${new_mb}M
post_max_size = ${new_mb}M
EOF

  if [[ -f "$FILEDROP_CONF" ]]; then
    local upload_bytes filedrop_pat
    upload_bytes=$(( new_mb * 1024 * 1024 ))
    filedrop_pat='\(\$maxFileSize\s*=\s*\)'
    sed -i "s/${filedrop_pat}[0-9]*/\1${upload_bytes}/" "$FILEDROP_CONF"
  fi

  systemctl reload nginx
  systemctl restart "php${PHP_VER}-fpm"
  msg_ok "Upload limit set to ${new_mb} MiB"
  echo ""
  read -rp "Press Enter to continue..."
}

bootstrap_plugins_ini() {
  local plugins_dir=/var/www/rutorrent/plugins
  [[ -d "$plugins_dir" ]] || return 1

  : >"$PLUGINS_INI"
  local plugin_dir slug
  for plugin_dir in "${plugins_dir}"/*/; do
    slug=$(basename "$plugin_dir")
    [[ -f "${plugin_dir}/init.js" ]] || continue
    if [[ "$slug" == _* ]]; then
      printf '[%s]\nenabled = yes\n\n' "$slug" >>"$PLUGINS_INI"
    else
      printf '[%s]\nenabled = no\n\n' "$slug" >>"$PLUGINS_INI"
    fi
  done
  chown www-data:www-data "$PLUGINS_INI"
}

action_manage_plugins() {
  header_info

  if [[ ! -f "$PLUGINS_INI" ]]; then
    msg_info "No plugins.ini found — initializing from installed plugins"
    if ! bootstrap_plugins_ini; then
      msg_error "plugins directory not found — is ruTorrent installed correctly?"
      read -rp "Press Enter to continue..."
      return
    fi
    msg_ok "Initialized plugins.ini (internal plugins enabled by default)"
  fi

  local -a slugs states
  local current_slug=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
      current_slug="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^enabled[[:space:]]*=[[:space:]]*(yes|no) ]] && [[ -n "$current_slug" ]]; then
      slugs+=("$current_slug")
      states+=("${BASH_REMATCH[1]}")
      current_slug=""
    fi
  done <"$PLUGINS_INI"

  if [[ ${#slugs[@]} -eq 0 ]]; then
    msg_error "No plugins found in $PLUGINS_INI"
    read -rp "Press Enter to continue..."
    return
  fi

  local checklist_items=()
  for i in "${!slugs[@]}"; do
    local state="OFF"
    [[ "${states[$i]}" == "yes" ]] && state="ON"
    checklist_items+=("${slugs[$i]}" "${slugs[$i]}" "$state")
  done

  local TERM_LINES max_visible
  TERM_LINES=$(tput lines 2>/dev/null || echo 24)
  max_visible=$(( TERM_LINES - 8 ))
  [[ $max_visible -lt 5 ]] && max_visible=5
  [[ $max_visible -gt ${#slugs[@]} ]] && max_visible=${#slugs[@]}

  local selected
  selected=$(whiptail --checklist "Enable/disable plugins (Space to toggle):" \
    $(( max_visible + 7 )) 62 "$max_visible" \
    "${checklist_items[@]}" \
    --title "Plugin Manager" 3>&1 1>&2 2>&3) || return

  local -A enabled_set=()
  local sel_slug
  for sel_slug in $(echo "$selected" | tr -d '"'); do
    enabled_set["$sel_slug"]=1
  done

  : >"$PLUGINS_INI"
  for slug in "${slugs[@]}"; do
    if [[ "${enabled_set[$slug]+_}" ]]; then
      printf '[%s]\nenabled = yes\n\n' "$slug" >>"$PLUGINS_INI"
    else
      printf '[%s]\nenabled = no\n\n' "$slug" >>"$PLUGINS_INI"
    fi
  done
  chown www-data:www-data "$PLUGINS_INI"

  msg_ok "plugins.ini updated — reload the ruTorrent browser tab to apply"
  echo ""
  read -rp "Press Enter to continue..."
}

action_change_port() {
  header_info
  local current_port new_port

  current_port=$(detect_port)

  new_port=$(whiptail --inputbox \
    "BitTorrent listen port:\n\n(forward this port on your router/firewall if downloading from outside your LAN)" \
    11 60 "$current_port" --title "BitTorrent Port" 3>&1 1>&2 2>&3) || return
  [[ -z "$new_port" ]] && return

  if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1024 ]] || [[ "$new_port" -gt 65535 ]]; then
    msg_error "Invalid port — must be an integer between 1024 and 65535"
    read -rp "Press Enter to continue..."
    return
  fi

  sed -i "s/^network\.port_range\.set = .*/network.port_range.set = ${new_port}-${new_port}/" "$RTORRENT_RC"

  msg_info "Restarting rTorrent"
  systemctl restart rtorrent
  if wait_for_rtorrent_socket; then
    msg_ok "rTorrent restarted on port ${new_port}"
  else
    msg_warn "rTorrent socket not found after restart — check 'systemctl status rtorrent'"
  fi
  echo ""
  read -rp "Press Enter to continue..."
}

action_restart_services() {
  header_info

  msg_info "Restarting rTorrent"
  systemctl restart rtorrent
  if wait_for_rtorrent_socket; then
    msg_ok "rTorrent restarted"
  else
    msg_warn "rTorrent socket not found after restart — check 'systemctl status rtorrent'"
  fi

  msg_info "Restarting nginx"
  if systemctl restart nginx; then
    msg_ok "nginx restarted"
  else
    msg_error "nginx failed to restart — check 'systemctl status nginx'"
  fi

  msg_info "Restarting PHP-FPM"
  if systemctl restart "php${PHP_VER}-fpm"; then
    msg_ok "PHP-FPM restarted"
  else
    msg_error "PHP-FPM failed to restart — check 'systemctl status php${PHP_VER}-fpm'"
  fi

  echo ""
  read -rp "Press Enter to continue..."
}

action_view_logs() {
  header_info
  local source

  source=$(whiptail --menu "View logs (last 200 lines):" 14 55 4 \
    "1" "rTorrent (journald)" \
    "2" "nginx access log" \
    "3" "nginx error log" \
    "4" "PHP-FPM (journald)" \
    --title "Log Viewer" 3>&1 1>&2 2>&3) || return

  local tmp
  tmp=$(mktemp)

  case "$source" in
    1) journalctl -u rtorrent -n 200 --no-pager >"$tmp" 2>&1 ;;
    2) tail -n 200 /var/log/nginx/access.log >"$tmp" 2>&1 ;;
    3) tail -n 200 /var/log/nginx/error.log >"$tmp" 2>&1 ;;
    4) journalctl -u "php${PHP_VER}-fpm" -n 200 --no-pager >"$tmp" 2>&1 ;;
  esac

  whiptail --scrolltext --title "Log Viewer" --textbox "$tmp" 25 100
  rm -f "$tmp"
}


action_change_storage_path() {
  header_info
  local current_base new_base

  current_base=$(detect_storage_base)

  new_base=$(whiptail --inputbox \
    "Base directory for downloads, session, and watch data:\n\nCurrent: ${current_base}\n\n(existing data will be moved here — this can take a while for large libraries)" \
    13 65 "$current_base" --title "Storage Path" 3>&1 1>&2 2>&3) || return
  [[ -z "$new_base" ]] && return

  if [[ "$new_base" != /* ]]; then
    msg_error "Path must be absolute (start with /)"
    read -rp "Press Enter to continue..."
    return
  fi

  if [[ "$new_base" == "$current_base" ]]; then
    msg_error "New path is the same as the current path — nothing to do"
    read -rp "Press Enter to continue..."
    return
  fi

  if [[ "$new_base" == "$current_base"/* || "$current_base" == "$new_base"/* ]]; then
    msg_error "New path cannot be nested inside the current path (or vice versa)"
    read -rp "Press Enter to continue..."
    return
  fi

  mkdir -p "$new_base" || {
    msg_error "Could not create ${new_base}"
    read -rp "Press Enter to continue..."
    return
  }

  local used_kb avail_kb
  used_kb=$(du -sk "$current_base" 2>/dev/null | awk '{print $1}')
  avail_kb=$(df -Pk "$new_base" 2>/dev/null | awk 'NR==2 {print $4}')
  if [[ -n "$used_kb" && -n "$avail_kb" ]] && (( avail_kb < used_kb )); then
    msg_error "Not enough free space at ${new_base} (need ~$((used_kb / 1024)) MiB, have $((avail_kb / 1024)) MiB)"
    read -rp "Press Enter to continue..."
    return
  fi

  whiptail --yesno \
    "This will:\n\n  1. Stop rTorrent\n  2. Move downloads/session/watch data from\n     ${current_base} to ${new_base}\n  3. Update rTorrent's configuration\n  4. Restart rTorrent\n\nThis cannot be easily undone if it fails partway.\nContinue?" \
    15 65 --title "Confirm Storage Migration" --defaultno 3>&1 1>&2 2>&3 || return

  local rc_backup="${RTORRENT_RC}.bak.$$"
  cp "$RTORRENT_RC" "$rc_backup"

  msg_info "Stopping rTorrent"
  systemctl stop rtorrent
  msg_ok "Stopped rTorrent"

  msg_info "Moving data to ${new_base}"
  local moved=()
  local sub
  for sub in downloads session .watch; do
    if [[ -d "${current_base}/${sub}" ]]; then
      mv "${current_base}/${sub}" "${new_base}/${sub}"
      moved+=("$sub")
    else
      mkdir -p "${new_base}/${sub}"
    fi
  done
  msg_ok "Moved data to ${new_base}"

  sed -i \
    -e "s#^directory\.default\.set = .*#directory.default.set = ${new_base}/downloads#" \
    -e "s#^session\.path\.set = .*#session.path.set = ${new_base}/session#" \
    -e "s#load\.start=[^[:space:]]*/\.watch/#load.start=${new_base}/.watch/#" \
    "$RTORRENT_RC"

  msg_info "Starting rTorrent"
  systemctl start rtorrent
  if wait_for_rtorrent_socket; then
    msg_ok "rTorrent started on ${new_base}"
    rm -f "$rc_backup"
  else
    msg_error "rTorrent failed to start — rolling back"
    systemctl stop rtorrent 2>/dev/null
    mv "$rc_backup" "$RTORRENT_RC"
    local s
    for s in "${moved[@]}"; do
      rm -rf "${current_base}/${s}"
      mv "${new_base}/${s}" "${current_base}/${s}"
    done
    systemctl start rtorrent
    if wait_for_rtorrent_socket; then
      msg_ok "Rolled back to ${current_base} — rTorrent running again"
    else
      msg_error "Rollback also failed to start rTorrent — check 'systemctl status rtorrent' manually"
    fi
  fi
  echo ""
  read -rp "Press Enter to continue..."
}


action_show_status() {
  header_info
  local rpc2 real_ip upload_mb port tls
  rpc2=$(detect_rpc2)
  real_ip=$(detect_real_ip)
  upload_mb=$(detect_upload_limit)
  port=$(detect_port)
  tls=$(detect_tls)

  msg_info "Configuration"
  printf "  %-20s %s\n" "Upload limit:"    "${upload_mb} MiB"
  printf "  %-20s %s\n" "/RPC2 endpoint:"  "${rpc2}"
  printf "  %-20s %s\n" "Real IP forward:" "${real_ip}"
  printf "  %-20s %s\n" "BitTorrent port:" "${port}"
  printf "  %-20s %s\n" "HTTPS:"           "${tls}"
  printf "  %-20s %s\n" "Storage path:"    "$(detect_storage_base)"
  printf "  %-20s %s\n" "PHP version:"     "${PHP_VER}"
  printf "  %-20s %s\n" "ruTorrent:"       "$(cat ~/.rutorrent 2>/dev/null || echo unknown)"
  echo ""
  msg_info "Services"
  for svc in rtorrent nginx "php${PHP_VER}-fpm"; do
    if systemctl is-active --quiet "$svc"; then
      msg_ok "${svc}"
    else
      msg_error "${svc}"
    fi
  done
  echo ""
  msg_info "Web UI users"
  awk -F: '{print "  "$1}' "$HTPASSWD" 2>/dev/null || msg_error "$HTPASSWD not found"
  echo ""
  read -rp "Press Enter to continue..."
}

# --- Main ---

header_info

while true; do
  RPC2=$(detect_rpc2)
  REAL_IP=$(detect_real_ip)
  UPLOAD=$(detect_upload_limit)
  PORT=$(detect_port)
  TLS=$(detect_tls)

  CHOICE=$(whiptail --title "ruTorrent Reconfigure" \
    --menu "upload=${UPLOAD}MiB  rpc2=${RPC2}  real-ip=${REAL_IP}  port=${PORT}  https=${TLS}" \
    25 65 12 \
    "1" "Change web UI password" \
    "2" "Toggle /RPC2 endpoint         [${RPC2}]" \
    "3" "Toggle real IP forwarding      [${REAL_IP}]" \
    "4" "Toggle HTTPS (self-signed)      [${TLS}]" \
    "5" "Change upload size limit       [${UPLOAD} MiB]" \
    "6" "Change BitTorrent port          [${PORT}]" \
    "7" "Move storage path" \
    "8" "Manage plugins" \
    "9" "View logs" \
    "10" "Restart services" \
    "11" "Show status" \
    "0" "Exit" \
    3>&1 1>&2 2>&3) || break

  case "$CHOICE" in
    1) action_change_password ;;
    2) action_toggle_rpc2 ;;
    3) action_toggle_real_ip ;;
    4) action_toggle_tls ;;
    5) action_change_upload_limit ;;
    6) action_change_port ;;
    7) action_change_storage_path ;;
    8) action_manage_plugins ;;
    9) action_view_logs ;;
    10) action_restart_services ;;
    11) action_show_status ;;
    0) break ;;
  esac

  header_info
done

msg_ok "Done."
