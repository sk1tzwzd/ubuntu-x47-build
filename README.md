# Ubuntu X47 Build

Idempotent installer that reproduces a custom Ubuntu 24.04 / 26 desktop:

- **WezTerm** as the default terminal, with a subtle grey **X47 ASCII watermark** on the right
- **Mullvad VPN** (apt) and **Tor Browser** (latest from Tor Project, registered in the app menu)
- Pentest + developer toolchain (apt, Go, pipx, cargo, GitHub release binaries, gems)
- Custom **app-grid launchers** and icons (`kali-*` pack, custom `kali-cool-*`, `x47duster` fallback — no Kali dragon)
- Hardened services snapshotted from the reference machine (UFW, fail2ban, AppArmor, auditd, unattended-upgrades, sysctl)

Part of the [VulnScape](https://vulnscape.net) cybersecurity suite.

**Docs site (free):** [sk1tzwzd.github.io/ubuntu-x47-build](https://sk1tzwzd.github.io/ubuntu-x47-build/)  
**Support (optional):** [buymeacoffee.com/sk1tzwzd](https://buymeacoffee.com/sk1tzwzd)

## Quick start (fresh machine)

```bash
git clone https://github.com/sk1tzwzd/ubuntu-x47-build.git
cd ubuntu-x47-build
chmod +x install.sh snapshot.sh modules/*.sh
./install.sh
```

You will be prompted for sudo for apt repos/packages and hardening restore.

### Flags

| Flag | Effect |
|------|--------|
| `--user-only` | Skip apt + hardening; install terminal, tools, icons, launchers only |
| `--skip-apt` | Skip third-party repos and apt packages |
| `--skip-hardening` | Skip UFW / fail2ban / sysctl / auditd restore |
| `--skip-debloat` | Keep language packs and default desktop apps (no trimming) |
| `--skip-desktop-fx` | Skip bottom dock + 3D window/desktop effects |
| `--with-amnesia` | Also create the amnesiac, Tor-forced `anon` user (opt-in) |
| `--only 10-terminal,30-icons` | Run a subset of modules |

## Performance / debloat

By default the installer trims the fat (opt out with `--skip-debloat`):

- **Language packs** — removes every non-English `language-pack-*`, LibreOffice l10n, and non-`en` spell dictionaries.
- **Default desktop apps** — removes GNOME games, Rhythmbox, Cheese, Thunderbird, LibreOffice, Transmission, Remmina, Shotwell, Maps/Weather/Contacts/Todo, Simple Scan, Totem, GNOME Music/Photos.
- **Cleanup** — `apt-get autoremove --purge`, cache clean, `journalctl` vacuum to 200M, thumbnail cache.
- **Tweaks** — `fstrim.timer`, `zram-config` compressed swap, `vm.swappiness=10`, and the desktop file indexer (tracker/localsearch) masked.

Everything is reversible: `sudo apt-get install <pkg>`. Core desktop/session packages and the pentest/dev toolchain are never touched. Note: zram adds compressed swap; if you want *true* amnesia in the anon session, still disable swap (see below).

## Firefox hardening

- **Main browser** — a system-wide enterprise policy at `/etc/firefox/policies/policies.json` (honored by the Firefox snap and deb): telemetry/studies/Pocket/sponsored content off, tracking protection with cryptomining + fingerprinting blocking, HTTPS-only, DNS-over-HTTPS, no prefetch/speculative connections. JavaScript stays on for normal browsing.
- **Anon browser** — stays Tor Browser "Safest": JavaScript off, no SOCKS proxy (transparent Tor), and DoH hard-off (`network.trr.mode=5`) so DNS can never bypass Tor.

## Desktop looks

By default the installer tunes the GNOME desktop for the main user (opt out with `--skip-desktop-fx`):

- **Bottom dock** — Ubuntu Dock moved to the bottom with intelligent autohide (reveal on hover).
- **3D effects** — version-matched GNOME extensions from extensions.gnome.org: Coverflow Alt-Tab (3D window switcher, bound to window + app switching), Desktop Cube (rotating 3D workspaces, fixed at 4), Burn My Windows (Glitch open/close animation), Blur My Shell (blurred panel/overview/dash), and Compiz-style wobbly windows.
- **Hover-only window controls** — minimize/maximize/close stay invisible until you hover the titlebar (GTK3 + GTK4 css, applied to snap apps like Firefox too).
- **X47 wallpaper** — the X47 knuckle-duster rendered as glowing teal ASCII art on a dark charcoal background, set for light and dark modes. Reproducible with `scripts/make-wallpaper.py`.
- **Desktop widgets** — bundled *X47 Widgets* extension (`assets/widgets/`): digital clocks for London and New York, a live BTC/USD ticker with 24 h change (CoinGecko, 60 s refresh), and CPU/RAM/load vitals. Drawn on the wallpaper beneath windows, themed to match.

User-level only (no sudo). On Wayland you must **log out and back in** once for the effects to load. Reverse with `gnome-extensions disable <uuid>`, delete `~/.config/burn-my-windows/profiles/x47.conf`, remove the marked block from `~/.config/gtk-{3.0,4.0}/gtk.css`, or `gsettings reset org.gnome.desktop.background picture-uri`.

## Install from ISO

Each release also ships a bootable installer ISO: the official Ubuntu 26.04 desktop image remastered with this build baked in (`scripts/build-iso.sh`, built by the *Build X47 ISO* GitHub Actions workflow). Pick **Install X47 Ubuntu 26.04 (custom build)** in the boot menu, install Ubuntu as normal (language, disk, and user stay interactive), and the X47 installer runs in a terminal on first login.

GitHub caps release assets at 2 GB, so the ISO is split into parts:

```bash
cat x47-ubuntu-26.04-desktop-amd64.iso.*.part > x47-ubuntu-26.04-desktop-amd64.iso
sha256sum -c SHA256SUMS --ignore-missing
```

To build it yourself: `sudo apt install xorriso`, then `./scripts/build-iso.sh` (no root needed; ~13 GB of free disk).

## What gets installed

### Terminal
- WezTerm AppImage under `~/tools/wezterm`
- Wrapper at `~/.local/bin/wezterm`
- Config: `~/.config/wezterm/wezterm.lua` + watermark `~/.config/wzd/watermark.png`
- Default terminal via `xdg-terminals.list` + GNOME gsettings

### Privacy
- **Mullvad VPN** via official apt repo (`mullvad-vpn` in the apt manifest)
- **Tor Browser** latest linux-x86_64 build → `~/tools/tor-browser`, registered with `--register-app`, CLI symlink `~/.local/bin/tor-browser`

### Tools (high level)
- **apt**: nmap, metasploit-framework, wireshark, hashcat, hydra, sqlmap, docker-ce, golang-go, ruby-dev, mullvad-vpn, ufw, fail2ban, …
- **Go**: amass, subfinder, httpx, nuclei, katana, naabu, dnsx, chisel, ligolo-ng, …
- **pipx**: netexec, impacket, bloodhound-python, smbmap, enum4linux-ng, arjun, wafw00f, …
- **cargo**: bat, feroxbuster
- **release bins**: rustscan, gitleaks, trufflehog, eza, fd, zoxide, delta
- **gems**: evil-winrm, wpscan
- **git clones**: WhatWeb, Responder → `~/tools/`

### Icons & launchers
Bundled under `assets/icons/` and `assets/applications/`. Installer expands `$HOME` placeholders so paths work for any user.

### Hardening
Files under `config/` are copied back to `/etc` (UFW rules, fail2ban jails, sysctl.d, audit rules, unattended-upgrades). Services are enabled.

## Amnesia mode (opt-in)

`./install.sh --with-amnesia` provisions a Tails-inspired `anon` account:

- **RAM-only home** — `/home/anon` is a `tmpfs` mount. Wiped every reboot; skeleton re-copied from `/var/lib/anon-skel`.
- **Forced Tor + kill-switch** — UID-scoped nftables; IPv6 dropped for `anon`. Tor config is inlined in `/etc/tor/torrc` (AppArmor blocks `torrc.d`).
- **Desktop** — dark `Yaru-prussiangreen-dark`, green accent, location off; Ubuntu first-run wizard skipped.
- **Apps** — Firefox (Safest / JS off), Electrum (BTC), Feather (XMR), Kleopatra (PGP), KeePassXC, VulnScape, **NymVPN** (daemon + GUI; connect after login).
- **Random MAC** — Tails-style spoof on anon login, restored on logout (`anon-mac-spoof`).
- **Unprivileged** — `anon` is not in `sudo`/`adm` (except narrow sudoers for persistent vault, MAC spoof, and starting `nym-vpnd`).

### Persistent Storage (optional)

By default wallets/PGP/passwords die with the tmpfs home. To keep selected secrets across reboots (Tails-style):

1. **Create** once (app menu → *Create Persistent Storage*) — picks size (default 4G) + passphrase; writes LUKS2 image to `/var/lib/x47-amnesia/persistent.img`.
2. **Unlock** each session you need secrets — mounts the vault and bind-mounts into the amnesia home:
   - `~/.gnupg`, `~/.electrum`, `~/.config/feather`
   - `~/Persistent/keepassxc`, `~/Persistent/Documents`
3. **Lock** (or reboot) — closes the vault. Without unlock, the session stays fully amnesiac.

The vault has its **own passphrase** on top of full-disk encryption. See `~/README-anon.txt` in the anon session.

Usage: log in as `anon` (default password `anon`, change on first login). Do **not** run Tor Browser as `anon` (Tor-over-Tor). Verify Tor at https://check.torproject.org.

### Limitations

Host-level amnesia, not a full amnesiac OS: base OS, packages, and system logs still persist. Swap can page tmpfs to disk. For stronger guarantees use Tails or Whonix.

### Teardown

```bash
sudo /usr/local/sbin/anon-persistent lock 2>/dev/null || true
sudo systemctl disable --now home-anon.mount anon-home-populate.service nftables
sudo rm -f /etc/systemd/system/home-anon.mount /etc/systemd/system/anon-home-populate.service
sudo rm -f /etc/nftables.d/anon-tor.nft /etc/sudoers.d/anon-persistent
sudo rm -f /usr/local/sbin/anon-persistent /usr/local/bin/anon-persistent-gui
sudo sed -i '/### X47 AMNESIA TOR BEGIN ###/,/### X47 AMNESIA TOR END ###/d' /etc/tor/torrc
sudo rm -rf /var/lib/anon-skel /var/lib/x47-amnesia /opt/x47-amnesia
sudo deluser --remove-home anon
sudo systemctl daemon-reload && sudo systemctl restart tor@default nftables
```

## Capturing / updating the snapshot (maintainers)

On the reference machine (with sudo):

```bash
./snapshot.sh
git add -A
git commit -m "Refresh snapshot from reference machine"
git push
```

`snapshot.sh` never touches secrets (`.ssh`, `.gnupg`, `.msf4`, Burp, Mullvad, Keys, …). Those paths are listed in `.gitignore`.

## Layout

```
install.sh                 # orchestrator
snapshot.sh                # capture live machine → assets/config/manifests
lib/common.sh
modules/                   # ordered install steps
assets/                    # icons, wezterm, wzd watermark, launchers, manifests
config/                    # captured /etc hardening files
```

## Notes

- Log out / re-login after install so GNOME Shell refreshes launchers and icons.
- Cursor / Metasploit may need their own installers or repos; apt installs them when available and skips gracefully otherwise.
- Mullvad account login is not bundled (secrets stay off GitHub). Tor Browser downloads the latest release at install time.
- Wallpaper path is `file:///usr/share/backgrounds/mendhak-Red_Acer.jpg` (Ubuntu wallpapers pack). If missing, the theme still applies.
- No Kali dragon is shipped; tools without a specific icon use `x47duster`.

## Support

This project is **free and open source**. Donations are optional and help cover maintenance and hosting:

- [Buy Me a Coffee — sk1tzwzd](https://buymeacoffee.com/sk1tzwzd)
- Docs: [GitHub Pages](https://sk1tzwzd.github.io/ubuntu-x47-build/) (canonical); VPS mirror `http://159.198.42.100` (optional)
- Issues / PRs: [github.com/sk1tzwzd/ubuntu-x47-build](https://github.com/sk1tzwzd/ubuntu-x47-build)

## License

Same terms as your other sk1tzwzd tooling unless a LICENSE file says otherwise.
