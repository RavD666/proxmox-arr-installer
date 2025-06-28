#!/bin/bash
# ------------------------------------------------------------
# Minimal “fire-and-forget” media-server installer
# ------------------------------------------------------------
set -e

echo "🔧 Updating system..."
apt update && apt upgrade -y

echo "📦 Installing prerequisites..."
apt install -y curl git apt-transport-https ca-certificates gnupg \
               lsb-release cifs-utils

echo "🐳 Installing Docker Engine & compose-plugin..."
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg \
  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
 https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
 $(lsb_release -cs) stable" \
| tee /etc/apt/sources.list.d/docker.list >/dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
echo "✅ Docker installed!"

# ------------------------------------------------------------
# Mount network shares
# ------------------------------------------------------------
echo "📁 Mounting CIFS shares..."
mkdir -p /mnt/arrdownloads /mnt/Media

grep -q "/mnt/arrdownloads" /etc/fstab || \
echo "//192.168.1.101/Arrdownload /mnt/arrdownloads cifs \
username=arr,password=Crystal121,iocharset=utf8,uid=1000,gid=1000,\
file_mode=0777,dir_mode=0777,noperm 0 0" >> /etc/fstab

grep -q "/mnt/Media" /etc/fstab || \
echo "//192.168.1.101/media /mnt/Media cifs \
username=arr,password=Crystal121,iocharset=utf8,uid=1000,gid=1000,\
file_mode=0777,dir_mode=0777,noperm 0 0" >> /etc/fstab

mount -a
echo "✅ Shares mounted!"

# ------------------------------------------------------------
# Optional: Portainer (nice web UI for Docker)
# ------------------------------------------------------------
echo "🚀 Installing Portainer..."
docker volume create portainer_data
docker run -d --name portainer --restart=always \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

# ------------------------------------------------------------
# Create ARR-stack compose file
# ------------------------------------------------------------
echo "📦 Creating ARR stack (with VPN, qBittorrent & SABnzbd)..."
mkdir -p ~/arr-stack && cd ~/arr-stack

cat <<'YML' > docker-compose.yml
version: "3.8"

services:

  # ---- VPN --------------------------------------------------
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      - TZ=Etc/UTC
      # ▶️  Supply your own provider or custom .ovpn files:
      - VPN_SERVICE_PROVIDER=custom
      - OPENVPN_USER=YOUR_VPN_USER
      - OPENVPN_PASSWORD=YOUR_VPN_PASS
    volumes:
      - ./config/gluetun:/gluetun
    ports:   # All forwarded ports must be declared here
      - "8080:8080"   # qBittorrent Web UI
      - "6881:6881"
      - "6881:6881/udp"
      - "9090:9090"   # SABnzbd Web UI
    restart: unless-stopped

  # ---- Torrent client --------------------------------------
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    network_mode: "service:gluetun"   # Route via VPN
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - WEBUI_PORT=8080
    volumes:
      - /mnt/arrdownloads:/downloads
      - ./config/qbittorrent:/config
    restart: unless-stopped
    depends_on:
      - gluetun

  # ---- Usenet client ---------------------------------------
  sabnzbd:
    image: lscr.io/linuxserver/sabnzbd:latest
    container_name: sabnzbd
    network_mode: "service:gluetun"   # Route via VPN
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - PORT=9090
    volumes:
      - /mnt/arrdownloads:/downloads
      - ./config/sabnzbd:/config
    restart: unless-stopped
    depends_on:
      - gluetun

  # ---- Indexer / Jackett replacement -----------------------
  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - ./config/prowlarr:/config
    ports:
      - "9696:9696"
    restart: unless-stopped

  # ---- TV ---------------------------------------------------
  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - ./config/sonarr:/config
      - /mnt/arrdownloads:/downloads
      - /mnt/Media/TV:/tv
      - /mnt/Media:/media
    ports:
      - "8989:8989"
    restart: unless-stopped

  # ---- Movies ----------------------------------------------
  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    environment: &arr-env
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - ./config/radarr:/config
      - /mnt/arrdownloads:/downloads
      - /mnt/Media/Movies:/movies
      - /mnt/Media:/media
    ports:
      - "7878:7878"
    restart: unless-stopped

  # ---- Music -----------------------------------------------
  lidarr:
    image: lscr.io/linuxserver/lidarr:latest
    container_name: lidarr
    environment: *arr-env
    volumes:
      - ./config/lidarr:/config
      - /mnt/arrdownloads:/downloads
      - /mnt/Media/Music:/music
      - /mnt/Media:/media
    ports:
      - "8686:8686"
    restart: unless-stopped

  # ---- Books / AudioBooks ----------------------------------
  readarr:
    image: lscr.io/linuxserver/readarr:latest
    container_name: readarr
    environment: *arr-env
    volumes:
      - ./config/readarr:/config
      - /mnt/arrdownloads:/downloads
      - /mnt/Media/Books:/books
      - /mnt/Media:/media
    ports:
      - "8787:8787"
    restart: unless-stopped

  # ---- Adult ------------------------------------------------
  whisparr:
    image: ghcr.io/hotio/whisparr:release
    container_name: whisparr
    environment: *arr-env
    volumes:
      - ./config/whisparr:/config
      - /mnt/arrdownloads:/downloads
      - /mnt/Media/XXX:/whisparr
      - /mnt/Media:/media
    ports:
      - "6969:6969"
    restart: unless-stopped

  # ---- Media server ----------------------------------------
  jellyfin:
    image: lscr.io/linuxserver/jellyfin:latest
    container_name: jellyfin
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - ./config/jellyfin:/config
      - /mnt/Media:/media
    ports:
      - "8096:8096"     # HTTP
      - "8920:8920"     # HTTPS
    restart: unless-stopped

YML

# ------------------------------------------------------------
# Launch!
# ------------------------------------------------------------
echo "📡 Starting containers…"
docker compose up -d

echo ""
echo "✅ All done!  Access your services at:"
IP=$(hostname -I | awk '{print $1}')
cat <<EOF

  Portainer     https://$IP:9443
  qBittorrent   http://$IP:8080  (via VPN)
  SABnzbd       http://$IP:9090  (via VPN)
  Sonarr        http://$IP:8989
  Radarr        http://$IP:7878
  Lidarr        http://$IP:8686
  Readarr       http://$IP:8787
  Whisparr      http://$IP:6969
  Prowlarr      http://$IP:9696
  Jellyfin      http://$IP:8096
EOF
