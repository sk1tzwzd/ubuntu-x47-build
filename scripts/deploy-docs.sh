#!/usr/bin/env bash
# Mirror docs/ to the VPS nginx root. Canonical site is GitHub Pages.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${X47_DOCS_HOST:-159.198.42.100}"
USER="${X47_DOCS_USER:-root}"
DEST="${X47_DOCS_DEST:-/var/www/ubuntu-x47}"

rsync -avz --delete \
  -e "ssh -o StrictHostKeyChecking=accept-new" \
  "$ROOT/docs/" "${USER}@${HOST}:${DEST}/"

echo "Mirrored docs/ -> ${USER}@${HOST}:${DEST}/"
echo "Canonical: https://sk1tzwzd.github.io/ubuntu-x47-build/"
echo "Mirror:    http://${HOST}/"
