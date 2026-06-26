# RPIjelly 🍓📺

A Dockerized, **always-on home media appliance for the Raspberry Pi 5**. Boots
straight into Jellyfin, blocks ads network-wide, and is reachable securely from
anywhere — no port-forwarding.

| Service | Port | What it does |
|---|---|---|
| **Jellyfin** | `8096` | Movie / TV library + streaming server |
| **Pi-hole** | `8081` (admin), `53` (DNS) | Network-wide ad / pop-up blocking |
| **qBittorrent** | `8080`, `6881` | Download client *(no indexers — legal sources only)* |
| **Sonarr** | `8989` | TV library manager *(no indexers — legal sources only)* |
| **Tailscale** | — | Secure remote access (private mesh VPN) |

---

## Hardware

- **Raspberry Pi 5** + official active cooler
- **256 GB microSD** — *only* for the initial OS flash / recovery
- **1–2 TB NVMe SSD + M.2 HAT** — **boot from this**

> **Why boot from NVMe?** This stack writes constantly (databases, logs,
> transcode cache). MicroSD cards wear out fast under that load. Booting from
> the NVMe spares the card and is far faster. A USB HDD is only worth it at
> 4 TB+; below that, NVMe wins on speed and reliability.

---

## ⚠️ Read this first: the Pi 5 transcoding reality

**The Pi 5 has *no* H.264 hardware *encoder*** (it can *decode* HEVC, but
Jellyfin's V4L2 path is deprecated). CPU-only H.264 transcoding on the Pi 5 is
weak and will stutter.

**→ This stack is designed for [Direct Play](https://jellyfin.org/docs/general/clients/codec-support).**
Keep your library as **1080p H.264** so clients play files as-is with no
transcoding. That also keeps remote streaming smooth, because remote quality is
capped by your **home upload speed**, not the Pi.

If you ever genuinely need heavy transcoding, the recommended upgrade is an
**Intel N100 mini PC** (Quick Sync handles H.264/HEVC/AV1 effortlessly).

---

## Quick start

```bash
git clone <this-repo> rpijelly && cd rpijelly

# 1) First run: installs Docker, frees DNS port 53, creates folders + .env
./scripts/install.sh

# 2) Edit your config (storage paths on the NVMe, passwords, Tailscale key)
nano .env

# 3) Second run: pulls images and brings the whole stack up
./scripts/install.sh

# 4) Turn the desktop into a Jellyfin kiosk (autologin + fullscreen browser)
./scripts/setup-kiosk.sh

# 5) Reboot into the appliance
sudo reboot
```

After boot the Pi auto-logs-in and opens **Chromium fullscreen on Jellyfin**.
Press **Alt+Tab** to switch to **Firefox** for YouTube / Google.

---

## Configuration (`.env`)

Copy `.env.example` to `.env` (the installer does this for you) and set:

| Variable | What to put |
|---|---|
| `PUID` / `PGID` | Your user's IDs — run `id` (usually `1000` / `1000`) |
| `TZ` | Your timezone, e.g. `America/Denver` |
| `HOST_LAN_IP` | The Pi's LAN IP from `hostname -I` (optional, helps client discovery) |
| `DATA_ROOT` | App configs/DBs on the NVMe, e.g. `/mnt/nvme/rpijelly` |
| `MEDIA_ROOT` | Library root, e.g. `/mnt/nvme/media` (`movies/`, `tv/` auto-created) |
| `DOWNLOADS_ROOT` | qBittorrent downloads, e.g. `/mnt/nvme/downloads` |
| `PIHOLE_PASSWORD` | Admin password for the Pi-hole UI |
| `PIHOLE_DNS` | Upstream resolvers (default Cloudflare `1.1.1.1;1.0.0.1`) |
| `TAILSCALE_AUTHKEY` | Reusable key from the [Tailscale admin console](https://login.tailscale.com/admin/settings/keys) |
| `TS_HOSTNAME` | Name this Pi shows up as in your tailnet |

`.env` is git-ignored — your secrets never get committed.

---

## First-run gotchas

- **qBittorrent temporary password.** On first start a random admin password is
  printed to the container log. Grab it with:
  ```bash
  docker logs qbittorrent | grep -i password
  ```
  Log into `http://<pi>:8080`, then change it under *Settings → Web UI*.

- **Pi-hole needs port 53.** On Raspberry Pi OS, `systemd-resolved` usually owns
  port 53 and will block Pi-hole. `install.sh` detects this and disables the
  stub listener automatically. If you ever start Pi-hole by hand and it fails to
  bind `53`, that's the cause — re-run `./scripts/install.sh` or disable
  `DNSStubListener` manually.

- **`docker` permission denied on first install.** The installer adds you to the
  `docker` group, but group changes only apply after a fresh login. Log out/in
  (or reboot) and re-run the script.

---

## Using it

### Jellyfin (`http://<pi>:8096`)
1. Create your admin account on first launch.
2. Add libraries pointing at the in-container paths:
   - **Movies** → `/data/movies`
   - **TV** → `/data/tv`
3. Keep files as **1080p H.264** for direct play (see the transcoding note above).

### Pi-hole (`http://<pi>:8081/admin`)
Log in with `PIHOLE_PASSWORD`. To actually block ads network-wide, point your
**router's DNS** (or individual devices) at the Pi's LAN IP. Pi-hole stops ads
at the DNS layer; **uBlock Origin in Firefox** handles in-page pop-ups and
YouTube video ads that DNS can't catch.

### qBittorrent (`http://<pi>:8080`) & Sonarr (`http://<pi>:8989`)
General download/library tools, shipped **without any indexers** (and no
Prowlarr). Sonarr sees downloads at `/downloads` and your library at `/tv`.
**Use legal sources only.**

### Tailscale — remote access from anywhere
Once the `tailscale` container authenticates with your key, install Tailscale on
your phone/laptop and reach the Pi over its tailnet IP — e.g. open
`http://<tailscale-ip>:8096` for Jellyfin while away from home. No
port-forwarding, works behind CGNAT, and it's private (unlike Plex, which
paywalled remote streaming in 2025). Remote video quality is limited by your
**home upload speed** — another reason to keep media as 1080p H.264.

---

## The kiosk desktop

`setup-kiosk.sh` configures:

- **Boot → desktop → autologin** (via `raspi-config`).
- **Chromium fullscreen on Jellyfin** at login. It uses `--start-fullscreen`
  **(not `--kiosk`)** *on purpose* so **Alt+Tab** to Firefox still works.
- **Firefox + uBlock Origin** (force-installed via Firefox enterprise policy).
  Firefox is used deliberately — Chrome's **Manifest V3** crippled uBlock Origin.

Switch apps with **Alt+Tab**; leave Chromium fullscreen with **F11**.

> Targets Raspberry Pi OS (Bookworm) on the Pi 5, which uses the **labwc**
> Wayland compositor by default. The script also wires up wayfire and XDG
> autostart as fallbacks.

---

## Running 24/7

Leave it on — power draw is roughly **$7–13/year**. A few tips:

- **Spin down an external HDD** (if you add one) with
  [`hd-idle`](https://github.com/adelolmo/hd-idle) to save power and noise.
- **Clean shutdown** any time with the **Pi 5's onboard power button** (single
  press → graceful shutdown).
- All app data lives under `DATA_ROOT` on the NVMe, so containers are
  disposable — `docker compose pull && docker compose up -d` upgrades in place.

---

## Common commands

```bash
docker compose ps                 # status of all services
docker compose logs -f jellyfin   # follow one service's logs
docker compose pull && docker compose up -d   # update everything
docker compose restart pihole     # restart a single service
docker compose down               # stop the stack (data is preserved)
```

---

## Roadmap / optional add-ons

- **Radarr** — movie library manager (the film counterpart to Sonarr).
- **Jellyseerr** — a friendly "request a title" UI in front of Sonarr/Radarr.

Both drop into `docker-compose.yml` as additional services when you want them.

---

## Legal

For **legal content only**. qBittorrent and Sonarr ship here **without any
indexers** and there is **no Prowlarr** — there is intentionally no piracy
pipeline in this project. Use it with media you own or content that is legally
available.
