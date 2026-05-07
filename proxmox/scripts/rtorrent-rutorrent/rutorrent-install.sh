#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Novik/ruTorrent | https://rakshasa.github.io/rtorrent/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

TORRENT_USER="torrent"
TORRENT_HOME="/home/${TORRENT_USER}"
DOWNLOAD_DIR="/data"
WATCH_DIR="${TORRENT_HOME}/watch"
SESSION_DIR="${TORRENT_HOME}/.session"
RUTORRENT_DIR="/var/www/rutorrent"
SCGI_PORT="5000"

# Passed in from ct script via lxc-attach env
RUTORRENT_USER="${RUTORRENT_USER:-torrent}"
# Space-separated list of plugins to enable. All others are disabled via plugins.ini.
RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS:-}"
# Expose nginx /RPC2 (rTorrent XMLRPC/SCGI). Off by default.
RUTORRENT_ENABLE_RPC2="${RUTORRENT_ENABLE_RPC2:-0}"
# Max .torrent upload size in MiB — sets PHP limits, nginx body size, filedrop plugin.
RUTORRENT_MAX_UPLOAD_MB="${RUTORRENT_MAX_UPLOAD_MB:-32}"
# Install vsftpd FTP server with a separate user/password. Off by default.
INSTALL_FTP="${INSTALL_FTP:-0}"
FTP_USER="${FTP_USER:-rutorrentftp}"

msg_info "Installing dependencies"
$STD apt-get install -y \
  ca-certificates \
  curl \
  git \
  openssl \
  nginx \
  apache2-utils \
  php-fpm \
  php-cli \
  php-curl \
  php-mbstring \
  php-xml \
  php-zip \
  rtorrent \
  screen \
  unzip \
  procps \
  mediainfo \
  ffmpeg \
  python3 \
  python-is-python3 \
  sox
msg_ok "Installed dependencies"

msg_info "Creating torrent user"
if ! id -u "${TORRENT_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${TORRENT_USER}"
fi
msg_ok "Created torrent user"

msg_info "Preparing directories"
mkdir -p "${WATCH_DIR}" "${SESSION_DIR}"
for DATA_DIR in /data /data2 /data3 /data4 /data5 /data6 /data7 /data8; do
  if mountpoint -q "${DATA_DIR}" 2>/dev/null; then
    chown "${TORRENT_USER}:${TORRENT_USER}" "${DATA_DIR}"
  elif [[ "${DATA_DIR}" == "/data" ]]; then
    mkdir -p "${DATA_DIR}"
    chown "${TORRENT_USER}:${TORRENT_USER}" "${DATA_DIR}"
  fi
done
chown -R "${TORRENT_USER}:${TORRENT_USER}" "${TORRENT_HOME}"
msg_ok "Prepared directories"

msg_info "Installing ruTorrent"
RUTORRENT_VERSION="$(curl -fsSL https://api.github.com/repos/Novik/ruTorrent/releases/latest | grep '"tag_name":' | cut -d'"' -f4)"
$STD git clone --depth 1 --branch "${RUTORRENT_VERSION}" https://github.com/Novik/ruTorrent.git "${RUTORRENT_DIR}"
echo "${RUTORRENT_VERSION}" > /opt/ruTorrent_version.txt

msg_info "Configuring filedrop upload limit"
if [[ -f "${RUTORRENT_DIR}/plugins/filedrop/conf.php" ]]; then
  sed -i "s/\$maxfilesize\s*=\s*[0-9]\+;/\$maxfilesize = ${RUTORRENT_MAX_UPLOAD_MB};/" \
    "${RUTORRENT_DIR}/plugins/filedrop/conf.php"
fi
msg_ok "Set filedrop upload limit to ${RUTORRENT_MAX_UPLOAD_MB} MiB"

msg_info "Configuring plugins"
# Internal system plugins — always enabled regardless of selection
KEEP_ALWAYS="_cloudflare _task _getdir _noty _noty2"
# Disabled by default when no explicit list is given
DISABLED_DEFAULT="throttle dump"
# Not yet implemented by this installer (warn if selected)
NOT_IMPLEMENTED="geoip2 pausewebui quotaspace retrackers rutracker_check uploadeta"

PLUGINS_INI="${RUTORRENT_DIR}/conf/plugins.ini"
: > "${PLUGINS_INI}"

for PLUGIN_DIR in "${RUTORRENT_DIR}/plugins"/*/; do
  [[ -d "${PLUGIN_DIR}" ]] || continue
  PLUGIN_NAME="$(basename "${PLUGIN_DIR}")"
  ENABLED="no"

  if echo " ${KEEP_ALWAYS} " | grep -q " ${PLUGIN_NAME} "; then
    ENABLED="yes"
  elif [[ -n "${RUTORRENT_PLUGINS}" ]]; then
    echo " ${RUTORRENT_PLUGINS} " | grep -q " ${PLUGIN_NAME} " && ENABLED="yes"
  else
    ENABLED="yes"
    echo " ${DISABLED_DEFAULT} " | grep -q " ${PLUGIN_NAME} " && ENABLED="no"
  fi

  printf '[%s]\nenabled = %s\n\n' "${PLUGIN_NAME}" "${ENABLED}" >> "${PLUGINS_INI}"
done

for PLUGIN in ${RUTORRENT_PLUGINS}; do
  if echo " ${NOT_IMPLEMENTED} " | grep -q " ${PLUGIN} "; then
    msg_warn "Plugin '${PLUGIN}' is not yet implemented — leaving disabled in plugins.ini"
  fi
done

chown www-data:www-data "${PLUGINS_INI}"
msg_ok "Plugins configured"

chown -R www-data:www-data "${RUTORRENT_DIR}"
msg_ok "Installed ruTorrent ${RUTORRENT_VERSION}"

msg_info "Configuring rTorrent"
cat > "${TORRENT_HOME}/.rtorrent.rc" <<EOF
directory.default.set = ${DOWNLOAD_DIR}
session.path.set = ${SESSION_DIR}
schedule2 = watch_directory,5,5,load.start=${WATCH_DIR}/*.torrent

network.port_range.set = 50000-50000
network.port_random.set = no
protocol.encryption.set = allow_incoming,try_outgoing,enable_retry
pieces.hash.on_completion.set = no
dht.mode.set = auto
trackers.use_udp.set = yes

network.scgi.open_port = 127.0.0.1:${SCGI_PORT}
EOF
chown "${TORRENT_USER}:${TORRENT_USER}" "${TORRENT_HOME}/.rtorrent.rc"
msg_ok "Configured rTorrent"

msg_info "Creating rTorrent systemd service"
cat > /etc/systemd/system/rtorrent.service <<EOF
[Unit]
Description=rTorrent
After=network.target

[Service]
Type=forking
User=${TORRENT_USER}
Group=${TORRENT_USER}
ExecStart=/usr/bin/screen -dmS rtorrent /usr/bin/rtorrent
ExecStop=/usr/bin/bash -lc '/usr/bin/screen -S rtorrent -X quit || true'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created rTorrent systemd service"

msg_info "Configuring ruTorrent"
cat > "${RUTORRENT_DIR}/conf/config.php" <<EOF
<?php
\$scgi_port = ${SCGI_PORT};
\$scgi_host = "127.0.0.1";
\$XMLRPCMountPoint = "/RPC2";
\$diskPath = "${DOWNLOAD_DIR}";
\$pathToExternals = array(
  "php"  => "/usr/bin/php",
  "curl" => "/usr/bin/curl",
  "gzip" => "/usr/bin/gzip",
  "id"   => "/usr/bin/id",
  "stat" => "/usr/bin/stat",
);
?>
EOF
chown -R www-data:www-data "${RUTORRENT_DIR}"
msg_ok "Configured ruTorrent"

msg_info "Setting up HTTP basic auth"
RUTORRENT_PASS="$(openssl rand -base64 12)"
htpasswd -bc /etc/nginx/.rutorrent.htpasswd "${RUTORRENT_USER}" "${RUTORRENT_PASS}" &>/dev/null
msg_ok "Created HTTP credentials (user: ${RUTORRENT_USER})"

msg_info "Configuring nginx"
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
# Use a stable socket name via a dedicated FPM pool so nginx config
# survives PHP version upgrades without needing to be rewritten.
PHP_SOCK="/run/php/rutorrent-fpm.sock"
cat > "/etc/php/${PHP_VER}/fpm/pool.d/rutorrent.conf" <<POOL
[rutorrent]
user = www-data
group = www-data
listen = ${PHP_SOCK}
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
POOL

PHP_UPLOAD_SIZE="${RUTORRENT_MAX_UPLOAD_MB}M"
for PHP_SAPI_DIR in "/etc/php/${PHP_VER}/fpm/conf.d" "/etc/php/${PHP_VER}/cli/conf.d"; do
  [[ -d "${PHP_SAPI_DIR}" ]] || continue
  cat > "${PHP_SAPI_DIR}/99-rutorrent-upload.ini" <<PHPINI
upload_max_filesize = ${PHP_UPLOAD_SIZE}
post_max_size = ${PHP_UPLOAD_SIZE}
memory_limit = 256M
max_file_uploads = 20
PHPINI
done

RPC2_BLOCK=""
if [[ "${RUTORRENT_ENABLE_RPC2}" == "1" ]]; then
  RPC2_BLOCK="
    location /RPC2 {
        include scgi_params;
        scgi_pass 127.0.0.1:${SCGI_PORT};
    }
"
fi

rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/rutorrent <<EOF
server {
    listen 80 default_server;
    server_name _;
    client_max_body_size ${RUTORRENT_MAX_UPLOAD_MB}M;
    root ${RUTORRENT_DIR};
    index index.php index.html;

    # Trust reverse proxy headers from private/local ranges only (e.g. Nginx Proxy Manager)
    set_real_ip_from 127.0.0.1;
    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 192.168.0.0/16;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;

    auth_basic "ruTorrent";
    auth_basic_user_file /etc/nginx/.rutorrent.htpasswd;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
${RPC2_BLOCK}
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location ~ /\. {
        deny all;
    }
}
EOF
ln -sf /etc/nginx/sites-available/rutorrent /etc/nginx/sites-enabled/rutorrent
msg_ok "Configured nginx"

msg_info "Enabling and starting services"
systemctl daemon-reload
$STD systemctl enable rtorrent
$STD systemctl enable php${PHP_VER}-fpm
$STD systemctl enable nginx
$STD systemctl restart php${PHP_VER}-fpm
$STD systemctl restart nginx
$STD systemctl restart rtorrent
sleep 3
if ! systemctl is-active --quiet rtorrent; then
  msg_warn "rTorrent service did not start — check: journalctl -u rtorrent"
fi
msg_ok "Services enabled and started"

FTP_PASS=""
if [[ "${INSTALL_FTP}" == "1" ]]; then
  msg_info "Installing FTP server"
  $STD apt-get install -y vsftpd
  FTP_PASS="$(openssl rand -base64 18)"
  if ! id -u "${FTP_USER}" &>/dev/null; then
    useradd -m -d "${DOWNLOAD_DIR}" -s /bin/bash "${FTP_USER}"
  fi
  echo "${FTP_USER}:${FTP_PASS}" | chpasswd
  cat > /etc/vsftpd.conf <<FTPCFG
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
local_root=${DOWNLOAD_DIR}
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.userlist
FTPCFG
  echo "${FTP_USER}" > /etc/vsftpd.userlist
  $STD systemctl enable vsftpd
  $STD systemctl restart vsftpd
  msg_ok "FTP server configured (user: ${FTP_USER})"
fi

motd_ssh
customize

echo "" >> /etc/motd
echo "  ruTorrent credentials:" >> /etc/motd
echo "    URL:      http://$(hostname -I | awk '{print $1}')/" >> /etc/motd
echo "    User:     ${RUTORRENT_USER}" >> /etc/motd
echo "    Password: ${RUTORRENT_PASS}" >> /etc/motd
echo "    Downloads: ${DOWNLOAD_DIR}" >> /etc/motd
if [[ "${INSTALL_FTP}" == "1" && -n "${FTP_PASS}" ]]; then
  echo "  FTP credentials:" >> /etc/motd
  echo "    User:     ${FTP_USER}" >> /etc/motd
  echo "    Password: ${FTP_PASS}" >> /etc/motd
  echo "    Path:     ${DOWNLOAD_DIR}" >> /etc/motd
fi

msg_ok "ruTorrent ${RUTORRENT_VERSION} installation complete"
msg_info "Access URL : http://$(hostname -I | awk '{print $1}')/"
msg_info "Username   : ${RUTORRENT_USER}"
msg_info "Password   : ${RUTORRENT_PASS}"
msg_info "Downloads  : ${DOWNLOAD_DIR}"
msg_info "Watch dir  : ${WATCH_DIR}"

cleanup_lxc
