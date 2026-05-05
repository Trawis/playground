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

msg_info "Installing dependencies"
$STD apt-get install -y \
  ca-certificates \
  curl \
  git \
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
  ffmpeg
msg_ok "Installed dependencies"

msg_info "Creating torrent user"
if ! id -u "${TORRENT_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${TORRENT_USER}"
fi
msg_ok "Created torrent user"

msg_info "Preparing directories"
mkdir -p "${WATCH_DIR}" "${SESSION_DIR}"
if mountpoint -q "${DOWNLOAD_DIR}" 2>/dev/null; then
  # Already a bind mount (configured before install) — just fix permissions
  chown "${TORRENT_USER}:${TORRENT_USER}" "${DOWNLOAD_DIR}"
else
  mkdir -p "${DOWNLOAD_DIR}"
  chown "${TORRENT_USER}:${TORRENT_USER}" "${DOWNLOAD_DIR}"
fi
chown -R "${TORRENT_USER}:${TORRENT_USER}" "${TORRENT_HOME}"
msg_ok "Prepared directories"

msg_info "Installing ruTorrent"
$STD git clone https://github.com/Novik/ruTorrent.git "${RUTORRENT_DIR}"
chown -R www-data:www-data "${RUTORRENT_DIR}"
msg_ok "Installed ruTorrent"

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

# SCGI for ruTorrent
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
ExecStop=/usr/bin/screen -S rtorrent -X quit
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
htpasswd -bc /etc/nginx/.rutorrent.htpasswd torrent "${RUTORRENT_PASS}" &>/dev/null
msg_ok "Created HTTP credentials (user: torrent)"

msg_info "Configuring nginx"
PHP_SOCK="$(find /run/php -name 'php*-fpm.sock' 2>/dev/null | head -n1)"
if [[ -z "${PHP_SOCK}" ]]; then
  # php-fpm may not have started yet; derive path from installed version
  PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"
fi

rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/rutorrent <<EOF
server {
    listen 80 default_server;
    server_name _;
    root ${RUTORRENT_DIR};
    index index.php index.html;

    auth_basic "ruTorrent";
    auth_basic_user_file /etc/nginx/.rutorrent.htpasswd;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location /RPC2 {
        auth_basic off;
        include scgi_params;
        scgi_pass 127.0.0.1:${SCGI_PORT};
    }

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
$STD systemctl enable php*-fpm
$STD systemctl enable nginx
$STD systemctl restart php*-fpm
$STD systemctl restart nginx
$STD systemctl restart rtorrent
msg_ok "Services enabled and started"

motd_ssh
customize

echo "" >>/etc/motd
echo "  ruTorrent credentials:" >>/etc/motd
echo "    URL:      http://$(hostname -I | awk '{print $1}')/" >>/etc/motd
echo "    User:     torrent" >>/etc/motd
echo "    Password: ${RUTORRENT_PASS}" >>/etc/motd
echo "    Downloads: ${DOWNLOAD_DIR}" >>/etc/motd

msg_ok "ruTorrent installation complete"
msg_info "Access URL: http://$(hostname -I | awk '{print $1}')/"
msg_info "Username:   torrent"
msg_info "Password:   ${RUTORRENT_PASS}"
msg_info "Downloads:  ${DOWNLOAD_DIR}"
msg_info "Watch dir:  ${WATCH_DIR} (drop .torrent files here)"

cleanup_lxc
