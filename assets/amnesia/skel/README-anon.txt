AMNESIA MODE (anon user)
========================

What this is
------------
This account is a Tails/Whonix-INSPIRED amnesiac profile for a normal, installed
Ubuntu system. It gives you:

  * A home directory that lives entirely in RAM (tmpfs). Everything you create
    here is GONE the moment you log out and the machine reboots. Nothing about
    this session is written to disk under /home/anon.

  * Forced Tor. Every TCP connection this user makes is transparently routed
    through the local Tor daemon, and DNS is resolved through Tor. Anything that
    cannot go through Tor is DROPPED by an nftables kill-switch (including all
    IPv6), so there are no accidental clearnet leaks.

Only the "anon" user is affected. Your normal account is untouched.

How to browse (important for .onion)
------------------------------------
  * Use the "Firefox (Amnesia / Tor)" launcher (or plain Firefox).
  * This Firefox profile has .onion unblocked. Stock Firefox and Chrome REFUSE
    to open .onion links (RFC 7686) even when Tor is working.
  * Do NOT enable a SOCKS proxy in Firefox and do NOT run Tor Browser here —
    the system already torifies everything (Tor-over-Tor is bad).
  * Verify Tor: https://check.torproject.org  (should say you are using Tor)
  * Test onion: http://protonmailrmez3lotccipshtkleegetolb73fuirgj7r4o4vfu7ozyd.onion/

What this is NOT
----------------
This is host-level amnesia, not a full amnesiac operating system. Be aware:

  * The base OS, the kernel, installed packages, and system logs (journald,
    /var/log) still persist on disk across reboots. This profile does not wipe
    those.
  * Transparent Tor protects your network traffic, but it does not give you the
    fingerprinting protections that the real Tor Browser does at the
    application layer.
  * If the system has active swap, RAM pages (including this home) could be
    written to disk. Prefer no swap, or encrypted/zram swap.

For real end-to-end anonymity guarantees, use Tails or Whonix.
