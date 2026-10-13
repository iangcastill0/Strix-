#!/bin/bash
#
# SessionStart hook for Claude Code cloud sessions.
#
# This repo is a CI/build harness for upstream usestrix/strix (the source is not
# vendored here). To make a cloud session immediately able to build and test
# Strix, this hook fetches the pinned upstream ref and installs its dependencies
# with `uv sync`. It runs synchronously so deps are ready before the agent loop
# starts (no race conditions); flip to async mode if you prefer faster startup.
#
set -euo pipefail

# Only do the (slow) fetch+sync in remote/cloud sessions. Local runs skip it.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

echo "[session-start] Fetching upstream Strix + installing deps..." >&2
SRC="$(bash "$ROOT/scripts/fetch-strix.sh")"
( cd "$SRC" && uv sync )
echo "[session-start] Strix ready at: $SRC" >&2

# Persist a convenience pointer to the upstream checkout for the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export STRIX_SRC_DIR=\"$SRC\"" >> "$CLAUDE_ENV_FILE"
fi
