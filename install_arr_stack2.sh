#!/bin/bash
# ------------------------------------------------------------
# Minimal “fire-and-forget” media-server installer (UPDATED)
# ------------------------------------------------------------
set -e

# ------------------------------------------------------------
# 1️⃣  System update & prerequisites
# ------------------------------------------------------------

echo "🔧 Updating system..."
apt update && apt upgrade -y

echo "📦 Installing prerequisites..."
apt install -y curl git apt-transport-https ca-certificates gnupg \
               lsb-release cifs-utils

# ------------------------------------------------------------
# 2️⃣  Docker Engine & compose-plugin
# ------------------------------------------------------------

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
# 3️⃣  Mount network shares (CIFS)
# ------------------------------------------------------------

echo "📁 Mounting CIFS shares..."
# Use consistent, case-correct paths
mkdir -p /mnt/Arrdownload /mnt/Media

# Arrdownload share
if ! grep -q "/mnt/Arrdownload" /etc/fstab; then
  echo "//192.168.1.101/Arrdownload /mnt/Arrdownload cifs \
username=arr,password=Crystal121,iocharset=utf8,uid=1000,gid=1000,\
file_mode=0777,dir_mode=0777,noperm 0 0" >> /etc/fstab
fi

# Media share
if ! grep -q "/mnt/Media" /etc/fstab; then
  echo "//192.168.1.101/Media /mnt/Media cifs \
username=arr,password=Crystal121,iocharset=utf8,uid=1000,gid=1000,\
file_mode=0777,dir_mode=0777,noperm 0 0" >> /etc/fstab
fi

# Reload systemd to pick up new fstab entries, then mount
systemctl daemon-reload
mount -a
echo "✅ Shares mounted!"

# ------------------------------------------------------------
# 4️⃣  Optional: Portainer (web UI for Docker)
# ------------------------------------------------------------

echo "🚀 Installing Portainer..."
docker volume create portainer_data
docker run -d --name portainer --restart=always \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

# ------------------------------------------------------------
# 5️⃣  Create ARR-stack compose file
# ------------------------------------------------------------

echo "📦 Creating ARR stack (with VPN, qBittorrent & SABnzbd)..."
mkdir -p ~/arr-stack && cd ~/arr-stack

cat <<'YML' > docker-compose.yml
# ... [unchanged docker-compose.yml content] ...
YML

# ------------------------------------------------------------
# 6️⃣  Launch!
# ------------------------------------------------------------

echo "🛁 Starting containers…"
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
