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

How to use it
-------------
  * Just log in as "anon" from the login screen and use the machine normally.
  * Use FIREFOX (or plain curl/wget) for browsing — they are transparently
    torified for you.
  * Do NOT run "Tor Browser" here. It bundles its own Tor and would create
    Tor-over-Tor. The system already Tor-routes everything for this user.
  * Verify you are on Tor: visit https://check.torproject.org

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
    written to disk. Prefer no swap, or encrypted/zram swap. The installer will
    warn you about this.

For real end-to-end anonymity guarantees, use Tails or Whonix.
