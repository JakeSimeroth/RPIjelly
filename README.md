# RPIjelly 🍓📺

A Dockerized, **always-on home media appliance for the Raspberry Pi 5**. Boots
straight into Jellyfin and is reachable securely from anywhere — no
port-forwarding.

| Service | Port | What it does |
|---|---|---|
| **Jellyfin** | `8096` | Movie / TV library + streaming server |
| **qBittorrent** | `8080`, `6881` | Download client |
| **Sonarr** | `8989` | TV library manager + automation |
| **Prowlarr** | `9696` | Indexer manager — feeds search sources to Sonarr |
| **Tailscale** | — | Secure remote access (private mesh VPN) |

> **Indexers:** Prowlarr ships with **none** preconfigured. You choose what to
> add — use **legal sources only** (public-domain / Creative-Commons libraries,
> content you own). See [Searching & downloading](#searching--downloading).

Ad blocking is handled in-browser by **uBlock Origin in Firefox** (set up by the
kiosk script). See [Ad blocking](#ad-blocking).

---

## Hardware

- **Raspberry Pi 5** + official active cooler
- **256 GB microSD**

### Storage plan

**First implementation (now): everything on the 256 GB microSD.** Simple, works
out of the box. Budget roughly **30–50 1080p movies** (or a few TV seasons)
after the OS takes its share.

**Upgrade later: add a 1–2 TB SSD.** You do **not** need an M.2 HAT for 1080p —
storage speed is not the bottleneck for streaming. Two options:

| Option | Need HAT? | Notes |
|---|---|---|
| **microSD boot + USB 3.0 SSD** | No | Plug into the Pi 5's blue USB-3 port. ~400 MB/s — plenty for 1080p, even several streams at once. Cheapest, simplest. |
| **M.2 HAT + NVMe** | Yes | Tidiest (internal, no cable), fastest (~800+ MB/s), and you can *boot* from it to spare the SD card. Best long-term. |

> **Why bother upgrading?** Capacity (256 GB fills fast) and **longevity** — this
> stack writes constantly (databases, logs), and microSD cards wear out under
> that load. When you add the SSD, point both `MEDIA_ROOT` *and* `DATA_ROOT`
> (app data) at it: that gives you space *and* spares the card from the writes.

To switch to the SSD: mount it (e.g. at `/mnt/ssd`), repoint the three `*_ROOT`
paths in `.env` at it, and re-run `./scripts/install.sh`.

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

# 1) First run: installs Docker, creates folders + .env
./scripts/install.sh

# 2) Edit your config (storage paths, Tailscale key)
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
| `DATA_ROOT` | App configs/DBs, default `/srv/rpijelly` (microSD) |
| `MEDIA_ROOT` | Library root, default `/srv/media` (`movies/`, `tv/` auto-created) |
| `DOWNLOADS_ROOT` | qBittorrent downloads, default `/srv/downloads` |
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

### Searching & downloading

Once everything is wired up (one-time setup below), the loop is automatic:

```
add a show in Sonarr → Sonarr searches your Prowlarr indexers
   → grabs a release → qBittorrent downloads to /downloads
   → Sonarr renames + files it into /tv → Jellyfin shows it
```

**One-time wiring (do once, in this order):**

1. **qBittorrent** (`http://<pi>:8080`) — get the temp password with
   `docker logs qbittorrent | grep -i password`, log in, change it under
   *Settings → Web UI*.

2. **Prowlarr** (`http://<pi>:9696`) — set a login, then:
   - *Indexers → Add Indexer* → add your **legal** sources (Prowlarr ships with
     none). Public-domain / Creative-Commons libraries and content you own only.
   - *Settings → Download Clients → add qBittorrent*: host `qbittorrent`, port
     `8080`, your username/password.
   - *Settings → Apps → add Sonarr*: Prowlarr URL `http://prowlarr:9696`, Sonarr
     URL `http://sonarr:8989`, and paste Sonarr's API key (Sonarr →
     *Settings → General → API Key*). Prowlarr now **pushes every indexer to
     Sonarr automatically** — you never add indexers in Sonarr by hand.

3. **Sonarr** (`http://<pi>:8989`) — *Settings → Download Clients → add
   qBittorrent*: host `qbittorrent`, port `8080`, your username/password. Set the
   TV root folder to `/tv`.

**Daily use:** in Sonarr, *Series → Add New*, pick the show, choose root folder
`/tv`, a **1080p** quality profile (keeps it direct-play), and Monitor. Sonarr
searches the synced indexers, sends the best release to qBittorrent, and once
it finishes, renames + files it into `/tv` where Jellyfin picks it up.
**Use legal sources only.**

> Want movies too? Add **Radarr** the same way (Prowlarr → Apps → Radarr) — see
> the roadmap below.

### Tailscale — remote access from anywhere
Once the `tailscale` container authenticates with your key, install Tailscale on
your phone/laptop and reach the Pi over its tailnet IP — e.g. open
`http://<tailscale-ip>:8096` for Jellyfin while away from home. No
port-forwarding, works behind CGNAT, and it's private (unlike Plex, which
paywalled remote streaming in 2025). Remote video quality is limited by your
**home upload speed** — another reason to keep media as 1080p H.264.

---

## Ad blocking

Ads are blocked **in the browser with uBlock Origin in Firefox**, which the
kiosk script force-installs. Use Firefox (not Chromium) for YouTube / web
browsing — uBlock there blocks in-page pop-ups, cosmetic junk, and YouTube
video ads.

> Firefox is used deliberately — Chrome's **Manifest V3** crippled uBlock Origin.

This build intentionally has **no Pi-hole** (no network-wide DNS blocking). If
you later want ads blocked across every device on your network (phones, smart
TVs, etc.), Pi-hole is the usual add-on — it can be reintroduced as another
container.

---

## The kiosk desktop

`setup-kiosk.sh` configures:

- **Boot → desktop → autologin** (via `raspi-config`).
- **Chromium fullscreen on Jellyfin** at login. It uses `--start-fullscreen`
  **(not `--kiosk`)** *on purpose* so **Alt+Tab** to Firefox still works.
- **Firefox + uBlock Origin** (force-installed via Firefox enterprise policy).

Switch apps with **Alt+Tab**; leave Chromium fullscreen with **F11**.

> Targets Raspberry Pi OS (Bookworm) on the Pi 5, which uses the **labwc**
> Wayland compositor by default. The script also wires up wayfire and XDG
> autostart as fallbacks.

---

## Running 24/7

Leave it on — power draw is roughly **$7–13/year**. A few tips:

- **Clean shutdown** any time with the **Pi 5's onboard power button** (single
  press → graceful shutdown).
- **Spin down an external HDD** (if you ever add one) with
  [`hd-idle`](https://github.com/adelolmo/hd-idle) to save power and noise.
- All app data lives under `DATA_ROOT`, so containers are disposable —
  `docker compose pull && docker compose up -d` upgrades in place.

---

## Common commands

```bash
docker compose ps                 # status of all services
docker compose logs -f jellyfin   # follow one service's logs
docker compose pull && docker compose up -d   # update everything
docker compose restart sonarr     # restart a single service
docker compose down               # stop the stack (data is preserved)
```

---

## Roadmap / optional add-ons

- **Radarr** — movie library manager (the film counterpart to Sonarr).
- **Jellyseerr** — a friendly "request a title" UI in front of Sonarr/Radarr.
- **Pi-hole** — network-wide DNS ad blocking, if you want coverage beyond the
  browser.

Each drops into `docker-compose.yml` as an additional service.

---

## Legal

For **legal content only**. Prowlarr ships with **no indexers preconfigured** —
which sources you add is entirely your choice and your responsibility. Use only
legal sources: public-domain and Creative-Commons libraries, or content you own.
Do not use this project to infringe copyright.
