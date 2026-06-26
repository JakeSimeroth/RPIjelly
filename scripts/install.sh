#!/usr/bin/env bash
#
# RPIjelly installer — Raspberry Pi 5 media server stack.
#
# Run it TWICE:
#   1) First run  -> installs Docker, frees port 53, creates folders, makes .env.
#                    It then stops and asks you to edit .env.
#   2) Second run -> (after editing .env) pulls images and brings the stack up.
#
# Safe to re-run any time — every step is idempotent.

set -euo pipefail

# --- locate repo root regardless of where the script is called from ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"

# --- pretty logging ----------------------------------------------------------
c_grn=$'\e[32m'; c_yel=$'\e[33m'; c_red=$'\e[31m'; c_rst=$'\e[0m'
info()  { printf '%s==>%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$c_yel" "$c_rst" "$*"; }
error() { printf '%s[x]%s %s\n' "$c_red" "$c_rst" "$*" >&2; }

if [[ ${EUID} -eq 0 ]]; then
  error "Don't run this as root. Run as your normal user; it uses sudo where needed."
  exit 1
fi

# =============================================================================
# 1. Docker + compose
# =============================================================================
if ! command -v docker >/dev/null 2>&1; then
  info "Installing Docker Engine (via get.docker.com)…"
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "${USER}"
  warn "Added ${USER} to the 'docker' group. Log out/in (or reboot) for it to take effect."
  warn "Re-run this script after that if Docker permission errors appear."
else
  info "Docker already installed: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1; then
  info "Installing Docker Compose plugin…"
  sudo apt-get update -y
  sudo apt-get install -y docker-compose-plugin
fi

# =============================================================================
# 2. Free up port 53 (Pi-hole needs it; systemd-resolved usually holds it)
# =============================================================================
if sudo ss -lntup 2>/dev/null | grep -q ':53 '; then
  if systemctl is-active --quiet systemd-resolved; then
    info "Port 53 is held by systemd-resolved — disabling its DNS stub listener…"
    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo tee /etc/systemd/resolved.conf.d/rpijelly.conf >/dev/null <<'EOF'
# Managed by RPIjelly — let Pi-hole own port 53.
[Resolve]
DNSStubListener=no
EOF
    # Point the host's own resolver at a real upstream while Pi-hole starts.
    if [[ -L /etc/resolv.conf || -f /etc/resolv.conf ]]; then
      sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
    fi
    sudo systemctl restart systemd-resolved
    info "systemd-resolved stub listener disabled."
  else
    warn "Something other than systemd-resolved is using port 53. Free it before starting Pi-hole."
  fi
else
  info "Port 53 is free."
fi

# =============================================================================
# 3. .env — create from template on first run, then stop and ask for edits
# =============================================================================
if [[ ! -f .env ]]; then
  cp .env.example .env
  info ".env created from .env.example."
  echo
  warn "ACTION NEEDED — edit .env before continuing:"
  warn "    nano ${REPO_DIR}/.env"
  warn "Set at least: PUID/PGID, TZ, the *_ROOT storage paths (on your NVMe),"
  warn "PIHOLE_PASSWORD, and TAILSCALE_AUTHKEY."
  echo
  info "When done, run this script again to bring the stack up."
  exit 0
fi

# Load .env so we can create the storage folders it points at.
set -a; # shellcheck disable=SC1091
source .env; set +a

# Guard against leaving placeholder secrets in place.
if [[ "${PIHOLE_PASSWORD:-}" == "changeme" || "${TAILSCALE_AUTHKEY:-}" == tskey-auth-xxxxxxxxxxxx ]]; then
  warn "It looks like .env still has placeholder values (PIHOLE_PASSWORD / TAILSCALE_AUTHKEY)."
  read -r -p "Continue anyway? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || { info "Edit .env, then re-run."; exit 0; }
fi

# =============================================================================
# 4. Create storage folders on the NVMe
# =============================================================================
info "Creating data directories…"
mkdir -p \
  "${DATA_ROOT}/jellyfin/config" "${DATA_ROOT}/jellyfin/cache" \
  "${DATA_ROOT}/pihole/etc-pihole" \
  "${DATA_ROOT}/qbittorrent/config" \
  "${DATA_ROOT}/sonarr/config" \
  "${DATA_ROOT}/tailscale" \
  "${MEDIA_ROOT}/movies" "${MEDIA_ROOT}/tv" \
  "${DOWNLOADS_ROOT}"

# Make sure the PUID/PGID user owns what the containers will write to.
sudo chown -R "${PUID}:${PGID}" "${DATA_ROOT}" "${MEDIA_ROOT}" "${DOWNLOADS_ROOT}" 2>/dev/null || \
  warn "Could not chown storage paths — check permissions if containers fail to write."

# =============================================================================
# 5. Bring the stack up
# =============================================================================
info "Pulling images (this can take a while on first run)…"
docker compose pull

info "Starting the stack…"
docker compose up -d

echo
info "Stack is up. Services:"
cat <<EOF
  Jellyfin     -> http://localhost:8096
  Pi-hole      -> http://localhost:8081/admin
  qBittorrent  -> http://localhost:8080   (temp password: docker logs qbittorrent)
  Sonarr       -> http://localhost:8989

Next:
  - Grab qBittorrent's first-run password:  docker logs qbittorrent | grep -i password
  - To set up the kiosk desktop:            ./scripts/setup-kiosk.sh  (then reboot)
EOF
