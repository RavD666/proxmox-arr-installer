#!/bin/bash
set -e

# ------------------------------------------------------------
# Minimal media-server installer for Proxmox container or VM
# ------------------------------------------------------------

# 1️⃣ System Update & Prerequisites

echo "🔧 Updating system..."
apt update && apt upgrade -y

echo "📦 Installing prerequisites..."
apt install -y curl git apt-transport-https ca-certificates gnupg \
               lsb-release cifs-utils

# 2️⃣ Docker Engine & Compose Plugin

echo "🐳 Ensuring Docker Engine & compose‑plugin are present..."
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

echo "✅ Docker installed or already present"

# 3️⃣ Mount Network Shares (CIFS)

echo "📁 Mounting CIFS shares..."
mkdir -p /mnt/Arrdownload /mnt/Media

add_fstab() {
  local SHARE="$1" MNT="$2"
  if ! grep -q "${MNT}$" /etc/fstab; then
    echo "//192.168.1.101/${SHARE} ${MNT} cifs username=arr,password=Crystal121,iocharset=utf8,uid=1000,gid=1000,file_mode=0777,dir_mode=0777,noperm 0 0" >> /etc/fstab
  fi
}

add_fstab "Arrdownload" "/mnt/Arrdownload"
add_fstab "Media" "/mnt/Media"

systemctl daemon-reload
mount -a || echo "⚠️  Mount failed. If using LXC, mount on host and bind into container."

echo "✅ Shares mounted (or already mounted)"

# 4️⃣ Deploy Portainer

echo "🚀 (Re)deploying Portainer..."
docker rm -f portainer 2>/dev/null || true
docker volume create portainer_data >/dev/null 2>&1

docker run -d --name portainer --restart=always \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

echo "✅ Portainer running at https://<VM-IP>:9443"

# 5️⃣ Generate ARR Stack Compose File

echo "📦 Generating ARR stack..."
mkdir -p ~/arr-stack && cd ~/arr-stack
rm -f docker-compose.yml

cat > docker-compose.yml <<'YML'
services:

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - WEBUI_PORT=8080
    volumes:
      - /mnt/Arrdownload:/downloads
      - ./config/qbittorrent:/config
    ports:
      - "8080:8080"
    restart: unless-stopped

  sabnzbd:
    image: lscr.io/linuxserver/sabnzbd:latest
    container_name: sabnzbd
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - /mnt/Arrdownload:/downloads
      - ./config/sabnzbd:/config
    ports:
      - "8085:8080"
    restart: unless-stopped

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

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - ./config/sonarr:/config
      - /mnt/Arrdownload:/downloads
      - /mnt/Media/TV:/tv
      - /mnt/Media:/media
    ports:
      - "8989:8989"
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - ./config/radarr:/config
      - /mnt/Arrdownload:/downloads
      - /mnt/Media/Movies:/movies
      - /mnt/Media:/media
    ports:
      - "7878:7878"
    restart: unless-stopped

  lidarr:
    image: lscr.io/linuxserver/lidarr:latest
    container_name: lidarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - ./config/lidarr:/config
      - /mnt/Arrdownload:/downloads
      - /mnt/Media/Music:/music
      - /mnt/Media:/media
    ports:
      - "8686:8686"
    restart: unless-stopped

  readarr:
    image: lscr.io/linuxserver/readarr:latest
    container_name: readarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - ./config/readarr:/config
      - /mnt/Arrdownload:/downloads
      - /mnt/Media/Books:/books
      - /mnt/Media:/media
    ports:
      - "8787:8787"
    restart: unless-stopped

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
      - "8096:8096"
      - "8920:8920"
    restart: unless-stopped
YML

# 6️⃣ Launch the Stack

echo "♻️  Re‑creating ARR containers…"
docker compose down --volumes --remove-orphans 2>/dev/null || true
docker compose pull --quiet
docker compose up -d

echo ""
IP=$(hostname -I | awk '{print $1}')
echo "✅ Setup complete!"
echo "🔗 Access your services:"
echo "  - Portainer:   https://$IP:9443"
echo "  - qBittorrent: http://$IP:8080"
echo "  - SABnzbd:     http://$IP:8085"
echo "  - Sonarr:      http://$IP:8989"
echo "  - Radarr:      http://$IP:7878"
echo "  - Lidarr:      http://$IP:8686"
echo "  - Prowlarr:    http://$IP:9696"
echo "  - Readarr:     http://$IP:8787"
echo "  - Jellyfin:    http://$IP:8096"
