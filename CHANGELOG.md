# Changelog

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
