# Ubuntu X47 Build

Idempotent installer that reproduces a custom Ubuntu 24.04 / 26 desktop:

- **WezTerm** as the default terminal, with a subtle grey **X47 ASCII watermark** on the right
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
| `--only 10-terminal,30-icons` | Run a subset of modules |

## What gets installed

### Terminal
- WezTerm AppImage under `~/tools/wezterm`
- Wrapper at `~/.local/bin/wezterm`
- Config: `~/.config/wezterm/wezterm.lua` + watermark `~/.config/wzd/watermark.png`
- Default terminal via `xdg-terminals.list` + GNOME gsettings

### Tools (high level)
- **apt**: nmap, metasploit-framework, wireshark, hashcat, hydra, sqlmap, docker-ce, golang-go, ruby-dev, ufw, fail2ban, …
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
- Cursor / Mullvad / Metasploit may need their own installers or repos; apt installs them when available and skips gracefully otherwise.
- Wallpaper path is `file:///usr/share/backgrounds/mendhak-Red_Acer.jpg` (Ubuntu wallpapers pack). If missing, the theme still applies.
- No Kali dragon is shipped; tools without a specific icon use `x47duster`.

## License

Same terms as your other sk1tzwzd tooling unless a LICENSE file says otherwise.
