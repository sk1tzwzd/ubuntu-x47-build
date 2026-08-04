# Changelog

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
