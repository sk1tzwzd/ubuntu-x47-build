#!/usr/bin/env bash
# Remaster the official Ubuntu 26.04 desktop ISO into the X47 build ISO.
#
# The result is a normal Ubuntu installer with an extra (default) boot entry
# that seeds the Subiquity autoinstall with:
#   - this repo copied to /opt/ubuntu-x47-build on the installed system
#     (git archive of HEAD only — no home directories, keys, or personal files)
#   - a first-login autostart that runs install.sh in a terminal
# The usual interactive steps (language, keyboard, disk, user/password) are
# kept — each installer creates their own account from scratch.
#
# No root required: xorriso does all ISO extraction/repacking in userspace.
#
# Env overrides:
#   X47_BASE_ISO_URL  base ISO url (default: official 26.04 desktop amd64)
#   X47_ISO_WORK      work dir (default: <repo>/build/iso)
#   X47_SPLIT=1       split the output into <2GiB parts for GitHub releases
#                     (removes the unsplit ISO afterwards to save disk)
#   X47_DELETE_BASE=1 delete the downloaded base ISO after repacking
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

BASE_ISO_URL="${X47_BASE_ISO_URL:-https://releases.ubuntu.com/26.04/ubuntu-26.04-desktop-amd64.iso}"
WORK="${X47_ISO_WORK:-$X47_ROOT/build/iso}"
OUT_NAME="x47-ubuntu-26.04-desktop-amd64.iso"

for tool in xorriso curl git sha256sum; do
  have "$tool" || die "missing required tool: $tool (apt install xorriso)"
done

mkdir -p "$WORK/out"
BASE_ISO="$WORK/$(basename "$BASE_ISO_URL")"
OUT_ISO="$WORK/out/$OUT_NAME"

# --- 1. base ISO -------------------------------------------------------------
if [[ -f "$BASE_ISO" ]]; then
  log "base ISO already downloaded: $BASE_ISO"
else
  log "downloading base ISO (~6 GB): $BASE_ISO_URL"
  curl -fL --retry 3 -o "$BASE_ISO.part" "$BASE_ISO_URL"
  mv "$BASE_ISO.part" "$BASE_ISO"
fi

# --- 2. overlay: repo snapshot + firstboot + nocloud seed --------------------
log "building ISO overlay (repo snapshot, firstboot hook, autoinstall seed)"
OVERLAY="$WORK/overlay"
rm -rf "$OVERLAY"
mkdir -p "$OVERLAY/repo" "$OVERLAY/firstboot" "$OVERLAY/nocloud"

git -C "$X47_ROOT" archive --format=tar HEAD | tar -x -C "$OVERLAY/repo"

install -m 0755 "$X47_ROOT/assets/iso/x47-firstboot.sh" "$OVERLAY/firstboot/x47-firstboot.sh"
install -m 0644 "$X47_ROOT/assets/iso/x47-firstboot.desktop" "$OVERLAY/firstboot/x47-firstboot.desktop"

cat > "$OVERLAY/nocloud/meta-data" <<'EOF'
EOF

cat > "$OVERLAY/nocloud/user-data" <<'EOF'
#cloud-config
autoinstall:
  version: 1
  # Keep the normal installer experience; the X47 payload rides along.
  interactive-sections:
    - locale
    - keyboard
    - network
    - storage
    - identity
    - timezone
    - drivers
    - codecs
  late-commands:
    - cp -a /cdrom/x47/repo /target/opt/ubuntu-x47-build
    - install -m 0755 /cdrom/x47/firstboot/x47-firstboot.sh /target/usr/local/bin/x47-firstboot
    - install -m 0644 /cdrom/x47/firstboot/x47-firstboot.desktop /target/etc/xdg/autostart/x47-firstboot.desktop
EOF

# --- 3. patch grub.cfg with an autoinstall entry ------------------------------
log "patching grub menu"
xorriso -osirrox on -indev "$BASE_ISO" -extract /boot/grub/grub.cfg "$WORK/grub.cfg" >/dev/null 2>&1
chmod +w "$WORK/grub.cfg"

if grep -q "Install X47 Ubuntu" "$WORK/grub.cfg"; then
  warn "grub.cfg already patched"
else
  awk '
    !inserted && /^menuentry / {
      print "menuentry \"Install X47 Ubuntu 26.04 (custom build)\" {"
      print "\tset gfxpayload=keep"
      print "\tlinux\t/casper/vmlinuz autoinstall ds=nocloud\\;s=/cdrom/x47/nocloud/ ---"
      print "\tinitrd\t/casper/initrd"
      print "}"
      inserted = 1
    }
    { print }
  ' "$WORK/grub.cfg" > "$WORK/grub.cfg.new"
  mv "$WORK/grub.cfg.new" "$WORK/grub.cfg"
fi

# --- 4. repack ----------------------------------------------------------------
log "repacking ISO (this takes a few minutes)"
rm -f "$OUT_ISO"
xorriso -indev "$BASE_ISO" -outdev "$OUT_ISO" \
  -overwrite on \
  -map "$OVERLAY" /x47 \
  -map "$WORK/grub.cfg" /boot/grub/grub.cfg \
  -boot_image any replay

if [[ "${X47_DELETE_BASE:-0}" == "1" ]]; then
  rm -f "$BASE_ISO"
fi

# --- 5. checksums (and optional split for GitHub's 2 GiB asset limit) --------
cd "$WORK/out"
sha256sum "$OUT_NAME" > SHA256SUMS
ok "built $OUT_ISO"

if [[ "${X47_SPLIT:-0}" == "1" ]]; then
  log "splitting into 1900 MiB parts for GitHub release assets"
  split -b 1900M -d --additional-suffix=.part "$OUT_NAME" "$OUT_NAME."
  rm -f "$OUT_NAME"
  sha256sum ./*.part >> SHA256SUMS
  ok "parts ready in $WORK/out (rejoin: cat ${OUT_NAME}.*.part > $OUT_NAME)"
fi
