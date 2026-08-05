# Changelog

## v1.9.6 — 2026-08-05

### Lean desktop (default)
- **Removed entirely** from main + anon: Desktop Cube, Coverflow Alt-Tab, Burn My Windows, Blur My Shell, wobbly windows, `x47-ws-walls`, and GNOME animations (`enable-animations=false`).
- **Dual Visual/HP mode removed** — installer is lean-only; `--desktop-mode` accepted but ignored. Power desktop sync autostart dropped.
- **Kept:** bottom dock (animation-time 0), CTRL-only tiling, notification click-to-focus, X47 wallpapers / Show Apps icon.

## v1.9.5 — 2026-08-05

### High Performance desktop
- **Install choice** — `--desktop-mode both|visual|performance` (first-boot chooser). `both` installs full FX and a lean profile.
- **Power settings sync** — when both are installed, GNOME **Settings → Power → Performance** applies High Performance desktop; Balanced / Power Saver restores Visual. Autostart: `x47-power-desktop-sync`.
- **High Performance cuts** — disables Desktop Cube, Coverflow, Burn My Windows, Blur My Shell, wobbly windows, `x47-ws-walls`, and `enable-animations`. Keeps the bottom dock, CTRL-only tiling, and wallpapers.
- **CLI** — `x47-desktop-mode visual|performance|status|sync-power`; also `x47-settings set desktop_mode …`.

## v1.9.4 — 2026-08-05

### Desktop looks
- **True per-desktop wallpapers** — `x47-ws-walls` now retargets the shell's per-workspace background actors, so the desktop-cube faces show each desktop's own colour *while you drag*, and the overview's previews and selector tabs always show the right one (previously everything showed the current wallpaper until you landed).
- **Colour schemes** (same circuit pattern + crisp ASCII duster everywhere, glow only on teal): WS1 teal on dark, WS2 pink duster on white, WS3 silver duster on carbon fibre, WS4 white duster on medium-dark green. Workspaces beyond 4 get a stable random pick from orange / purple / yellow / red colourways.

### Dock
- **Click a pinned app cycles its windows** (`click-action=cycle-windows`), jumping to other workspaces when the next window lives there.

### Windows-style tiling
- **Tiling Shell** bundled + tuned: drag any window to get snap zones (no modifier key), screen edges tile halves, corners quarters (2x2 grid), top edge maximizes, and it suggests windows to fill the remaining tiles. Ubuntu's built-in tiling-assistant is disabled to avoid fights.
- **Custom X47 layouts** — default is a big main area with a wide terminal strip along the bottom; also code+side-stack, halves, and a 2x2 grid. Pre-selected on all four workspaces (`[workspace][monitor]` shape).
- **CTRL+drag to tile** — plain window drags move freely (no snap zones / edge tiles). Hold **Ctrl** while dragging to show the tile grid. New windows from the dock/launcher open floating. Layout menu picks which zones apply on the next CTRL+drag.
- **GNOME 50 fixes** — layout editor no longer crashes / leaves a stuck blue overlay (`Meta.Cursor` removed in Mutter 18); workspace-switch `_syncStacking` no longer throws when a window appears mid-animation.
- **Tiling stability** — null compositor actors, disposed SnapAssist during work-area changes, and failed preview fade-outs no longer leave stuck overlays; grab-end always tears down visuals; skip Mutter anim-prep that raced Compiz wobbly (`Error in size change accounting`); wobbly *resize* effect off; snap-assist close is instant.
- **No stuck blue tile when dragging to another desktop** — workspace/cube switches mid-drag now close every workspace's tile preview (previously only the destination layout was cleared).
- **Easy off-switch** — flip `tiling` in **X47 Settings** (`x47-settings set tiling off`) to disable CTRL+drag tiling entirely; applies instantly.

### Terminal
- **Sized WezTerm launches** — default terminal matches the reference window (~933×638 outer); app-grid tools open larger (~1340×720); VulnScape opens biggest (~1600×920). Override with `X47_TERM_SIZE=default|tool|large|vulnscape` or `X47_TERM_WIDTH`/`X47_TERM_HEIGHT` (pixels).

### Widgets
- **Linux CMD Helper / X47 Widgets removed** — purged from the build and live installs. `52-widgets.sh` is purge-only and will not reinstall them.

### Window controls
- **Always-visible min/max/close** — removed hover-to-reveal window buttons everywhere (GTK, Firefox, snap sandboxes). WezTerm uses a normal title bar again (no integrated tab-bar buttons that hide until hover).
- **Alt+Tab Desktop guard** — the Desktop entry no longer triggers on a quick first Alt+Tab (which was minimizing windows on single-window desktops); you now have to cycle past the last window deliberately.

### Amnesia (anon) session
- **anon@x47 wallpaper** — black circuit board with blocky ASCII `anon@x47`, same on all four desktops (`scripts/make-wallpaper.py --color anon`).
- **Anon Status card** (`x47-anon-status@x47`) — desktop widget showing connection strength, VPN state (Mullvad / Nym / NetworkManager), `Tor Status: Connected w Bridge`, and a colour-coded security verdict. Refreshes every 10 s, click to refresh.
- **Tor always via obfs4 bridges** — `obfs4proxy` installed, built-in public bridges baked into the anon transparent-Tor config; Tor Browser (if present) is forced onto built-in obfs4 bridges too.
- **NymVPN opens on login** via autostart in the anon skel.

## v1.9.3 — 2026-08-05

### Fixes
- **App menus clickable again** — hover-only window controls no longer sit invisible on top of Firefox (and other CSD) header menus. GTK/Firefox CSS is scoped to min/max/close only and uses `pointer-events: none` while hidden.

### Optional features + Settings
- New **X47 Settings** app/CLI (`x47-settings`) toggles features anytime; values in `~/.config/x47/settings.conf`.
- **PuTTY-style WezTerm clipboard** (select copy, right-click paste, Ctrl+C/V) — default on; `--skip-putty-clipboard` or `x47-settings set putty_clipboard off`.
- **Super+Shift+S** screenshot — default on; `--skip-win-screenshot` or `x47-settings set win_screenshot off` (**Print** always kept).

### Desktop
- **Bottom dock is static** (always visible); hides only in F11 fullscreen (`autohide-in-fullscreen`). F11 bound to toggle-fullscreen.
- **Alt+Tab to desktop** — in Coverflow, one more Alt+Tab past the last window selects **Desktop** (release Alt to minimize all). Tip: press **D** while the switcher is open for the same action.
- **Click notification → app** — `x47-notif-activate@x47` makes a single click on a top banner focus/open the app that sent it (helps snaps/apps that only dismissed the banner).

## v1.9.2 — 2026-08-05

### Desktop looks
- **Per-workspace wallpaper colours** for the desktop cube: workspace 1 teal, 2 green, 3 red, 4 purple ASCII knuckle-duster (subtle circuit tint matches). Bundled `x47-ws-walls@x47` switches on workspace change. Regenerate with `scripts/make-wallpaper.py --all`.

## v1.9.1 — 2026-08-05

### Terminal
- WezTerm spawn sized to the reference window (~128×30 / ~1008×450 inner).
- **No OS title bar** — `INTEGRATED_BUTTONS|RESIZE`; Hide / Maximize / Close sit on the right of the tab bar.
- Docs site hero + WezTerm screenshots refreshed to the current desktop (ASCII wallpaper, CMD Helper, dock).

### Fixes
- Linux CMD Helper stacking confirmed after login (visible top-right above desktop icons).

## v1.9.0 — 2026-08-05

### Desktop widget
- **Linux CMD Helper** replaces the old widget bundle (clocks/BTC/vitals/Reddit/PKG). One sleek dark-glass card: type a question in plain English, get back just the Ubuntu terminal command (Anthropic Claude Haiku), click to copy.
- API key read at runtime from `~/.config/x47-widgets/anthropic.key` (chmod 600) or the `X47_ANTHROPIC_KEY` env var during install — never bundled in this repo.
- Fixed the after-reboot invisibility: the card now stacks just above the desktop-icons window (below app windows), so it stays on the desktop and never overlaps windows. Still hides in fullscreen and snaps to a grid.

### Desktop looks
- **Broken Glass** window close animation (open stays TV Glitch) via split Burn My Windows profiles (`x47-open.conf` / `x47-close.conf`).

### Launchers / icons
- New bespoke icon set for the 19 tools that used the knuckle-duster fallback: a teal/steel **dev-tool** family (bat, delta, eza, fd, http, lazygit, uv, yq, zoxide) and a red/green tactical **pentest** family (dalfox, dnsx, gau, gowitness, interactsh-client, kerbrute, rustscan, tlsx, gitleaks, trufflehog).

### Fixes / tweaks
- **Cursor** opens a single IDE window (`window.restoreWindows: none`) and the update nag is silenced (`update.mode: none`).
- **Mullvad** starts minimized to the tray (`startMinimized`) while keeping autostart + autoconnect; applied by `50-gnome.sh`.

## v1.8.0 — 2026-08-05

### Terminal
- **Larger WezTerm** — default window `160×48` so the X47 knuckle-duster watermark sits on the right with room.
- **GNOME Terminal removed** — purged by debloat; launchers hidden and stripped from favorites. WezTerm remains the only default.

### Amnesia
- **WezTerm default for anon** — shared `/usr/local/bin/wezterm`, skel config + watermark, GNOME Terminal hidden.
- **Anon desktop matches main looks** — dock, Coverflow, Desktop Cube, TV Glitch, Blur My Shell, wobbly windows, wallpaper, hover controls. **No X47 Widgets** on anon.
- ISO first-boot opens **WezTerm** (not GNOME Terminal).

## v1.7.0 — 2026-08-05

### Desktop looks
- **TV Glitch** window open/close (replaces plain Glitch) via the managed Burn My Windows profile.
- **ASCII duster wallpaper** — X47 knuckle-duster as glowing teal ASCII art on a dark circuit background (`scripts/make-wallpaper.py`).

### Desktop widgets
- Cards sit **under app windows** (below `window_group`), **hide in fullscreen**, and **snap to a 16px grid**.
- Drag from the card **title**; positions in `~/.config/x47-widgets/layout.json`.
- **Install / Update helper** — always shows `apt upgrade`, `snap refresh`, `update-cursor`; search returns install or upgrade/refresh commands (click to copy).
- CPU/RAM sparklines, London + New York clocks, BTC ticker, cybersecurity Reddit feed.

### Performance / debloat
- New `06-perf.sh` (opt out with `--skip-perf`): chkrootkit/bettercap off boot path, GRUB timeout 1s, ModemManager masked, ClamAV on-demand, kdump/cloud-init/printing off.
- Debloat also removes **Ubuntu Help** (`yelp` / docs; launcher hidden even if re-pulled), **App Centre**, and **Desktop Security Centre** snaps.

### Firefox
- Keeps the hardened snap (snap→deb swap reverted); `scripts/firefox-restore-snap.sh` for machines that swapped earlier.
- Hardening module forces **hardened Firefox as the default browser** (`xdg-settings` + `mimeapps.list`).

### Tools
- `update-cursor` (`~/.local/bin/update-cursor`): apt-only upgrade; documents Cursor’s GUI-vs-apt lag; `--quiet-gui` sets `update.mode=none`.

### Fixes
- **BTC widget** — descriptive User-Agent so CoinGecko doesn’t 403; HTTP errors surface on the card.

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
