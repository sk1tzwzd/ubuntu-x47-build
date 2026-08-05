# Reddit thread — Ubuntu X47

Copy/paste ready. Suggested subs: r/linux, r/Ubuntu, r/privacy, r/netsec, r/Kalilinux, r/TOR, r/selfhosted (pick one primary; crosspost carefully).

---

## Title

**Ubuntu X47: lean Ubuntu 26.04 build — debloated for speed, with a Tor/Nym amnesia session for anonymity + pentest tooling**

---

## Body

I rebuilt my daily Ubuntu around three things: **speed**, **a clean desktop**, and an **optional anonymity / lab session** that doesn’t slow down the main account.

Repo: https://github.com/sk1tzwzd/ubuntu-x47-build

### Debloat & speed

Stock Ubuntu is fine until you pile on cube effects, blur, animated window death, and a fat dock. X47 defaults to a **lean GNOME desktop**:

- No Desktop Cube, Coverflow Alt-Tab, Burn My Windows, Blur My Shell, wobbly windows, or per-workspace wallpaper FX
- GNOME animations off
- Ubuntu Dock off — lime Ubuntu circle in the top bar opens the app grid; Super / Super+1…9 still work
- CTRL+drag tiling only (plain drags stay free)
- Optional package cleanup, zram, and sane defaults aimed at a snappier session

Main account stays a normal, fast Ubuntu you can actually work on. No “pretty but laggy” tax.

### Anonymity & security (`anon` / amnesia mode)

Opt-in with `--with-amnesia`. Creates a separate **`anon`** user inspired by Tails-style amnesia:

- **RAM-only home** (`tmpfs`) — wiped on reboot; skeleton restored from skel
- **Forced Tor + kill-switch** (UID-scoped nftables; IPv6 dropped for anon)
- **obfs4 bridges** in the Tor path
- **NymVPN / mixnet** on the stack; status panel shows **LINK / NYM / TOR** only — **no Wi‑Fi SSID or network name** leaking from the UI
- Firefox hardened toward Safer/Safest-style use (verify via check.torproject.org)
- Random MAC on anon login
- Optional LUKS **persistent vault** for wallets / GPG / KeePass when you need secrets to survive reboot
- Dark identity + ASCII shrouded-figure wallpaper so the session *feels* separate from the daily driver

This is **host-level amnesia**, not a full amnesiac OS. Base packages and system logs still persist. For stronger guarantees use Tails or Whonix — X47 is for when you want Ubuntu tooling with a hard privacy lane next door.

### Pentesting & lab work

Same machine, different hats:

- Main session: fast desktop for writing, building, browsing
- Anon session: Tor-forced traffic, mixnet status, crypto/PGP tools, and room to run lab / assessment work without painting your daily profile onto every packet

Toolchain stays installable/reversible through the build modules (dev + security tooling are first-class; the installer doesn’t strip the useful stuff to “look minimal”).

### Desktop identity

- X47 ASCII knuckle-duster wallpapers on the main user
- Anon: carbon-fibre ASCII **shrouded figure** wallpaper
- Top bar Show Apps (green Ubuntu circle), taller panel so icons stay readable
- WezTerm with PuTTY-style copy/paste when you want it

### Install

```bash
git clone https://github.com/sk1tzwzd/ubuntu-x47-build.git
cd ubuntu-x47-build
./install.sh                  # lean desktop + tooling
./install.sh --with-amnesia   # also provision the anon session
```

ISO remaster / GitHub Actions path is in the README if you want a bootable installer.

### Honest limits

- Not a replacement for Tails/Whonix for high-threat anonymity
- Swap can still page tmpfs if you leave swap on — disable swap if you want stronger amnesia
- Wayland: log out/in once after extension changes

### Why I built it

I wanted Ubuntu that **boots into work fast**, doesn’t waste GPU on eye candy I never asked for, and still has a **one-click lane** into Tor + mixnet + amnesia when I’m testing, researching, or just don’t want the session glued to my real identity.

Feedback welcome — especially from people who live in Tor/Nym daily or who care about lean GNOME on Ubuntu 26.04.

---

## Short comment / TL;DR (optional sticky reply)

**TL;DR:** Ubuntu 26.04 custom build. Debloated GNOME (no cube/blur/dock tax) for speed. Optional `anon` user: tmpfs home, Tor kill-switch, Nym status, no SSID in the panel, pentest-friendly tooling. https://github.com/sk1tzwzd/ubuntu-x47-build
