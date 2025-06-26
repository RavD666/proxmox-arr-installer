# Proxmox ARR Stack Installer

This script sets up Docker, Portainer, and the full ARR stack (Sonarr, Radarr, Lidarr, Prowlarr, qBittorrent) on a fresh Debian/Ubuntu VM inside Proxmox. It also mounts a network share for downloads.

---

## 🚀 One-Liner Install

```bash
bash <(curl -sSL https://raw.githubusercontent.com/RavD666/proxmox-arr-installer/main/install_arr_stack.sh)
