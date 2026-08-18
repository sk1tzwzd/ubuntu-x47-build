#!/usr/bin/env bash
# Stage the X47-Win kit onto a mounted Windows volume.
# The kit lives in the separate X47-Win repo; this wrapper clones/updates it.
set -euo pipefail
CACHE="${X47_WIN_DIR:-$HOME/.cache/X47-Win}"
REPO="${X47_WIN_REPO:-https://github.com/sk1tzwzd/X47-Win.git}"

if [[ ! -d "$CACHE/.git" ]]; then
  git clone "$REPO" "$CACHE"
else
  git -C "$CACHE" pull --ff-only || true
fi

exec "$CACHE/scripts/stage-x47-windows.sh" "$@"
