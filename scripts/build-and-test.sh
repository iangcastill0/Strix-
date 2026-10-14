#!/usr/bin/env bash
#
# Build and test upstream usestrix/strix at the pinned ref. This is the single
# source of truth for "does Strix build and pass its tests" and is run both by
# CI (.github/workflows/ci.yml) and by hand.
#
# Requires: git, uv, and Go >= 1.24 (the wheel bundles a compiled Go TUI
# sidecar). The viewer SPA ships prebuilt in the upstream repo, so Node is NOT
# required.
#
# Honours the same env overrides as fetch-strix.sh (STRIX_REF, STRIX_SRC_DIR,
# STRIX_UPSTREAM_URL). Extra knobs:
#   RUN_TESTS=0   build the wheel + smoke-test the CLI, but skip the test suite.
#   PYTEST_ARGS   extra args appended to the pytest invocation.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNOWN_FAILURES="$REPO_ROOT/scripts/known-failures.txt"

step() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

step "Fetching upstream Strix"
SRC="$(bash "$REPO_ROOT/scripts/fetch-strix.sh")"
cd "$SRC"
echo "Source: $SRC @ $(git rev-parse --short HEAD)"

step "Installing dependencies (uv sync)"
uv sync

step "Smoke-testing the CLI entry point"
uv run strix --help >/dev/null
echo "strix --help OK"

step "Building the wheel (compiles the Go TUI sidecar)"
uv build --wheel
ls -1 dist/*.whl

if [ "${RUN_TESTS:-1}" != "1" ]; then
  step "RUN_TESTS=0 set — skipping test suite"
  echo "Build verified."
  exit 0
fi

step "Running the test suite"
# Turn the known-failures list into --deselect args (ignore blanks & # comments).
deselect_args=()
while IFS= read -r line; do
  line="${line%%#*}"
  # trim surrounding whitespace
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$line" ] && deselect_args+=(--deselect "$line")
done < "$KNOWN_FAILURES"

echo "Deselecting $(( ${#deselect_args[@]} / 2 )) known-failing test(s):"
printf '%s\n' "${deselect_args[@]}" | sed -n 's/^tests\//  tests\//p'

# shellcheck disable=SC2086 # PYTEST_ARGS is intentionally word-split
uv run pytest -q "${deselect_args[@]}" ${PYTEST_ARGS:-}

step "All checks passed"
