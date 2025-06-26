#!/bin/bash

set -e

echo "🔧 Updating system..."
sudo apt update && sudo apt upgrade -y

echo "📦 Installing dependencies..."
sudo apt install -y curl git apt-transport-https ca-certificates gnupg lsb-release cifs-utils

echo "🐳 Installing Docker..."
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "✅ Docker installed!"
sudo systemctl enable docker

echo "📁 Mounting network share..."
sudo mkdir -p /mnt/arrdownloads
echo "//192.168.1.101/Arrdownload /mnt/arrdownloads cifs username=arr,password=Crystal121,iocharset=utf8,uid=1000,gid=1000,file_mode=0777,dir_mode=0777,noperm 0 0" | sudo tee -a /etc/fstab
sudo mount -a

echo "🚀 Installing Portainer..."
sudo docker volume create portainer_data
sudo docker run -d \
  -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

echo "📦 Creating ARR stack with qBittorrent..."

mkdir -p ~/arr-stack && cd ~/arr-stack

cat <<EOF > docker-compose.yml
version: '3.8'
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
      - /mnt/arrdownloads:/downloads
      - ./config/qbittorrent:/config
    ports:
      - 8080:8080
      - 6881:6881
      - 6881:6881/udp
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
      - /mnt/arrdownloads:/downloads
    ports:
      - 8989:8989
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
      - /mnt/arrdownloads:/downloads
    ports:
      - 7878:7878
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
      - /mnt/arrdownloads:/downloads
    ports:
      - 8686:8686
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
      - /mnt/arrdownloads:/downloads
    ports:
      - 9696:9696
    restart: unless-stopped
EOF

echo "📡 Starting ARR stack..."
docker compose up -d

echo "✅ Setup complete!"
echo ""
echo "🔗 Access your services:"
echo "  - Portainer:   https://$(hostname -I | awk '{print $1}'):9443"
echo "  - qBittorrent: http://$(hostname -I | awk '{print $1}'):8080"
echo "  - Sonarr:      http://$(hostname -I | awk '{print $1}'):8989"
echo "  - Radarr:      http://$(hostname -I | awk '{print $1}'):7878"
echo "  - Lidarr:      http://$(hostname -I | awk '{print $1}'):8686"
echo "  - Prowlarr:    http://$(hostname -I | awk '{print $1}'):9696"
