#!/usr/bin/env bash
#
# Fetch the upstream usestrix/strix source at the pinned ref into a local,
# git-ignored checkout. Prints the absolute path of the checkout on stdout so
# callers can `cd` into it.
#
# Overridable via environment variables:
#   STRIX_REF          upstream ref (commit/branch/tag) to check out
#                      (default: contents of ./.strix-ref)
#   STRIX_SRC_DIR      where to put the checkout (default: ./.upstream/strix)
#   STRIX_UPSTREAM_URL clone URL (default: https://github.com/usestrix/strix.git)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${STRIX_SRC_DIR:-$REPO_ROOT/.upstream/strix}"
UPSTREAM="${STRIX_UPSTREAM_URL:-https://github.com/usestrix/strix.git}"
REF="${STRIX_REF:-}"
if [ -z "$REF" ]; then
  REF="$(tr -d '[:space:]' < "$REPO_ROOT/.strix-ref")"
fi

# Progress/log goes to stderr so stdout stays a clean path for `$(...)` capture.
log() { printf '[fetch-strix] %s\n' "$*" >&2; }

mkdir -p "$(dirname "$DEST")"

if [ ! -d "$DEST/.git" ]; then
  log "cloning $UPSTREAM -> $DEST"
  # blob:none keeps the clone small but still lets us check out any commit.
  git clone --filter=blob:none "$UPSTREAM" "$DEST" >&2
fi

log "fetching ref $REF"
git -C "$DEST" fetch --quiet --filter=blob:none origin "$REF" 2>/dev/null \
  || git -C "$DEST" fetch --quiet --filter=blob:none --tags origin
git -C "$DEST" -c advice.detachedHead=false checkout --quiet "$REF"

log "checked out $(git -C "$DEST" rev-parse HEAD)"
printf '%s\n' "$DEST"
