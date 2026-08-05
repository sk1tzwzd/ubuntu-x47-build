AMNESIA MODE (anon user)
========================

What this is
------------
A Tails-inspired amnesiac profile on a normal Ubuntu install:

  * Home lives in RAM (tmpfs) — wiped every reboot.
  * All traffic is forced through Tor (kill-switch; IPv6 blocked).
  * Desktop matches the main X47 look (dock, 3D effects, wallpaper) — no widgets.
  * Dark Prussian-green theme, green accent, location off.
  * Firefox (Safest): JavaScript off by default, .onion unblocked.

Apps
----
  * WezTerm — default terminal (shared /usr/local/bin/wezterm)
  * Firefox (Amnesia / Safest) — default browser, auto-starts
  * Electrum — Bitcoin
  * Feather — Monero
  * Kleopatra — PGP keys
  * KeePassXC — password manager (same family as Tails)
  * VulnScape — guided pentest / bug-bounty toolkit (shared install, always latest from GitHub on reinstall)
  * NymVPN — mixnet / VPN layer (log in and connect after unlock; Tor still wraps your apps)

Extra privacy (automatic)
-------------------------
  * Random MAC address on every anon login (Tails-style). Restored when you
    log out of anon (or on reboot). Your normal user is unaffected after restore.
  * Open **NymVPN**, sign in, and connect (prefer Anonymous / mixnet mode).
    Traffic path becomes: apps → Tor (transparent) → Nym → Internet.
    Disconnect Nym when you leave the anon session so your main account is not
    left on the mixnet.

PERSISTENT STORAGE (optional, Tails-style)
-----------------------------------------
By default NOTHING survives reboot — including wallets and PGP keys.

If you want selected secrets to survive:

  1. First time only: open "Create Persistent Storage"
     - Pick a size (default 4 GB) and a strong passphrase
     - This creates an encrypted LUKS vault on disk
       (/var/lib/x47-amnesia/persistent.img)
     - Protected by full-disk encryption AND your vault passphrase

  2. Each anon login when you need your secrets:
     - Open "Unlock Persistent Storage" and enter the passphrase
     - The vault is mounted and bound into your session:
         ~/.gnupg                 → Kleopatra / GPG
         ~/.electrum              → Electrum wallets
         ~/.config/feather        → Feather wallets
         ~/Persistent/keepassxc   → KeePassXC databases
         ~/Persistent/Documents   → files you choose to keep

  3. When finished (or just reboot):
     - "Lock Persistent Storage" closes the vault
     - Reboot also locks it (tmpfs home is wiped; LUKS stays closed)

If you never unlock, the session stays fully amnesiac.

IMPORTANT
  * Save KeePassXC databases under ~/Persistent/keepassxc/ AFTER unlock.
  * Create Electrum/Feather wallets only after unlock (so they land in the vault).
  * Write down / back up seed phrases separately — encryption is not a backup.
  * Wrong passphrase = no access. There is no recovery.

Browsing
--------
  * Use Firefox (Amnesia / Safest) from the dock — not the stock Firefox icon.
  * Firefox is pre-set to SOCKS 127.0.0.1:9050 (local Tor). That is safe here:
    localhost bypasses the TransPort redirect, so it is not Tor-over-Tor.
    Other apps stay transparently torified by the kill-switch.
  * .onion sites need that SOCKS path (system DNS refuses .onion by RFC 7686).
    Prefer https://…onion when the service supports it; HTTP onions also work.
  * Verify: homepage opens https://check.torproject.org/api/ip → "IsTor":true
  * Many onions need JavaScript — Safest leaves JS off. Toggle it in
    about:config → javascript.enabled if a site stays blank after it loads.

What this is NOT
----------------
Host-level amnesia, not a full amnesiac OS. The base OS, packages, and system
logs still persist. For stronger guarantees use Tails or Whonix.
