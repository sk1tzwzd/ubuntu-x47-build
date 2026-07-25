# Ubuntu X47 Build

Idempotent installer that reproduces a custom Ubuntu 24.04 / 26 desktop:

- **WezTerm** as the default terminal, with a subtle grey **X47 ASCII watermark** on the right
- **Mullvad VPN** (apt) and **Tor Browser** (latest from Tor Project, registered in the app menu)
- Pentest + developer toolchain (apt, Go, pipx, cargo, GitHub release binaries, gems)
- Custom **app-grid launchers** and icons (`kali-*` pack, custom `kali-cool-*`, `x47duster` fallback — no Kali dragon)
- Hardened services snapshotted from the reference machine (UFW, fail2ban, AppArmor, auditd, unattended-upgrades, sysctl)

Part of the [VulnScape](https://vulnscape.net) cybersecurity suite.

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
| `--with-amnesia` | Also create the amnesiac, Tor-forced `anon` user (opt-in) |
| `--only 10-terminal,30-icons` | Run a subset of modules |

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

- **RAM-only home** — `/home/anon` is a `tmpfs` mount (`home-anon.mount`). Everything the user does is wiped on reboot. A pristine skeleton in `/var/lib/anon-skel` is re-copied at each boot by `anon-home-populate.service`.
- **Forced Tor with kill-switch** — an nftables table (`assets/amnesia/anon-tor.nft`, UID-scoped to `anon`) transparently redirects all of `anon`'s TCP through Tor's `TransPort` (9040) and DNS through `DNSPort` (9053). Anything that cannot be Tor-routed is dropped, and **all IPv6 from `anon` is blocked**, so there are no clearnet leaks. Only `anon` is affected; your normal account is untouched. Tor directives are written into `/etc/tor/torrc` (the `system_tor` AppArmor profile blocks `torrc.d` drop-ins on stock Ubuntu).
- **Unprivileged by design** — `anon` is not in `sudo`/`adm`; that is what makes the UID firewall meaningful.

Usage: log in as `anon` (default password `anon`, forced change on first login). Use **Firefox** or plain `curl`/`wget` — they are transparently torified. Do **not** run Tor Browser as `anon` (it would be Tor-over-Tor). Verify at https://check.torproject.org.

### Limitations (read `~/README-anon.txt` in the anon session)

This is host-level amnesia, **not** a full amnesiac OS:

- The base OS, kernel, installed packages, and system logs (`journald`, `/var/log`) still persist on disk. This profile does not wipe them.
- Transparent Tor protects network traffic but does not provide Tor Browser's application-layer anti-fingerprinting.
- If swap is active, RAM pages (including the tmpfs home) may hit disk. The installer warns you; disable swap or use encrypted zram for real amnesia.

For end-to-end anonymity guarantees, use Tails or Whonix.

### Teardown

```bash
sudo systemctl disable --now home-anon.mount anon-home-populate.service nftables
sudo rm -f /etc/systemd/system/home-anon.mount /etc/systemd/system/anon-home-populate.service
sudo rm -f /etc/nftables.d/anon-tor.nft
sudo sed -i '/### X47 AMNESIA TOR BEGIN ###/,/### X47 AMNESIA TOR END ###/d' /etc/tor/torrc
sudo rm -rf /var/lib/anon-skel
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

## License

Same terms as your other sk1tzwzd tooling unless a LICENSE file says otherwise.
