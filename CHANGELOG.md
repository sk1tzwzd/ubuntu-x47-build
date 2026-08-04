# Changelog

## Unreleased

### Desktop looks
- **ASCII duster wallpaper** — the wallpaper renders the X47 knuckle-duster as glowing teal ASCII art, centered small with negative space over the dark-minimal circuit background. Reproducible via `scripts/make-wallpaper.py` from `assets/desktop/x47-ascii.txt` + `assets/desktop/x47-circuit-bg.png`.

### Fixes
- **BTC widget** — set a descriptive User-Agent so CoinGecko stops returning 403 (the ticker was silently blank); HTTP errors now surface on the card.

## v1.6.0 — 2026-08-04

### Installable ISO
- New `scripts/build-iso.sh`: remasters the official Ubuntu 26.04 desktop ISO with the X47 build baked in (autoinstall seed + repo at `/opt/ubuntu-x47-build` + first-login setup terminal). Userspace only (xorriso), no root.
- New *Build X47 ISO* GitHub Actions workflow: builds the ISO and attaches it to a release, split into <2 GB parts (`cat *.part > iso` to rejoin, `SHA256SUMS` included).

### Desktop looks
- **Glitch window animations** — Burn My Windows profile switched from Matrix to the subtler hacker-style Glitch effect (400 ms).
- **Hover-only window controls** — minimize/maximize/close are invisible until the titlebar is hovered, via managed GTK3/GTK4 css blocks (also installed into snap app sandboxes, e.g. Firefox).

### Desktop widgets
- New bundled **X47 Widgets** GNOME extension + `52-widgets.sh` module: digital clocks for London and New York, a live BTC/USD ticker (CoinGecko, 60 s refresh, 24 h change), and system vitals (CPU / RAM / load). Drawn on the wallpaper beneath windows, styled to match the X47 theme. Skipped with `--skip-desktop-fx`.

## v1.5.0 — 2026-08-04

### Desktop looks
- **Matrix window animations** — Burn My Windows now ships a managed profile (`x47.conf`) with the Matrix effect for open/close animations (fire off); empty auto-created profiles are removed.
- **Coverflow tuning** — the 3D Alt-Tab switcher is bound to both window and application switching, hides the panel while switching, and uses the Coverflow style (set via the extension's own schema dir).
- **Blur My Shell** — blurred panel, overview, and dash.
- **Wobbly windows** — Compiz-style window effect (`compiz-windows-effect`).
- **X47 circuit wallpaper** — custom dark-minimal wallpaper (X47 duster on charcoal with subtle circuit traces) bundled at `assets/desktop/wallpapers/x47-circuit.png`, installed to `~/.local/share/backgrounds/` and set for light + dark.
- `ego_install` now also checks the local extensions directory, so already-downloaded extensions aren't re-fetched before the next login.

## v1.4.0 — 2026-08-04

### Desktop looks
- New `51-desktop-fx.sh` module (default, opt out with `--skip-desktop-fx`): moves the Ubuntu Dock to the bottom and installs version-matched 3D effects — Coverflow Alt-Tab (window switcher), Desktop Cube (rotating workspaces, fixed at 4), and Burn My Windows (open/close animations). User-level; requires a Wayland log out/in to load. Main user only.

## v1.3.0 — 2026-08-02

### Performance / debloat
- New `05-debloat.sh` module (default, opt out with `--skip-debloat`): removes non-English language packs and default desktop apps (games, Thunderbird, LibreOffice, media, etc.), cleans caches, and adds perf tweaks (fstrim, zram, swappiness, file indexer off). Fully reversible; core packages protected by a denylist.

### Firefox hardening
- New `12-firefox-hardening.sh` installs a system-wide enterprise policy (`/etc/firefox/policies/policies.json`) for the main browser: telemetry/Pocket/sponsored off, tracking protection (cryptomining + fingerprinting), HTTPS-only, DoH. JavaScript stays on.
- Anon Firefox tightened: DoH hard-off (`network.trr.mode=5`) so DNS cannot bypass Tor, plus safe-negotiation, no beacons, trimmed cross-origin referer. Still Safest/JS-off with no SOCKS proxy.

## v1.2.0 — 2026-07-30

### Amnesia privacy
- **Random MAC spoof** on anon login (`anon-mac-spoof`), restored on logout; boot cleanup clears leftover NetworkManager cloned-MAC overrides (`x47-mac-cleanup.service`).
- **NymVPN** daemon + GUI installed for the amnesia session; daemon started for the GUI (no auto-login/connect). Narrow sudoers for MAC + `nym-vpnd`.

### Documentation
- Project docs site under `docs/` (overview, install, amnesia, support).
- Canonical hosting: GitHub Pages at `https://sk1tzwzd.github.io/ubuntu-x47-build/`.
- Optional VPS mirror via `scripts/deploy-docs.sh`.
- Support / donations: [buymeacoffee.com/sk1tzwzd](https://buymeacoffee.com/sk1tzwzd).

## v1.1.0

- Anon theme, wallets, Kleopatra, KeePassXC, LUKS persistent vault.
- Firefox Safest defaults; Tor / onion browsing fixes.
- VulnScape shared install for amnesia.
