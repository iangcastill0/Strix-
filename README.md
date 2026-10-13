# Strix — build & test harness

This repository is a **CI / build-verification harness** for the open-source AI
penetration-testing tool [**usestrix/strix**](https://github.com/usestrix/strix)
(Apache-2.0). It does **not** vendor Strix's source code. Instead it fetches a
pinned upstream revision on demand and verifies that it:

1. installs cleanly (`uv sync`),
2. produces a working CLI (`strix --help`),
3. builds a self-contained wheel (which compiles the bundled **Go TUI sidecar**
   and ships the prebuilt viewer SPA), and
4. passes its test suite.

The goal is continuous, reproducible verification that a known-good revision of
Strix builds and tests green — the kind of CI/build gate you want in front of any
dependency you rely on.

## Layout

| Path | Purpose |
|------|---------|
| `.strix-ref` | The pinned upstream `usestrix/strix` commit SHA — the single source of truth for which revision is built. |
| `scripts/fetch-strix.sh` | Clones/updates the upstream source into `./.upstream/strix` (git-ignored) at the pinned ref. Prints the checkout path. |
| `scripts/build-and-test.sh` | The core gate: fetch → `uv sync` → CLI smoke → `uv build --wheel` → `pytest`. Used by CI and locally. |
| `scripts/known-failures.txt` | Pytest node IDs deselected because they fail **upstream** at the pinned ref (documented, data/timing-sensitive, unrelated to build health). |
| `.github/workflows/ci.yml` | GitHub Actions: runs the gate on push / PR / weekly schedule / manual dispatch, across Python 3.12 and 3.13, and uploads the built wheel. |
| `.claude/hooks/session-start.sh` | Claude Code **cloud** SessionStart hook: fetches upstream + `uv sync` so a cloud session can build/test Strix immediately. |
| `.claude/settings.json` | Registers the SessionStart hook. |

## Requirements

- [`uv`](https://docs.astral.sh/uv/) (Python project/dependency manager)
- **Go ≥ 1.24** — the wheel build compiles a Go TUI sidecar into the package
- `git`

Node is **not** required: the viewer SPA ships prebuilt in the upstream repo.

## Usage

```bash
# Build the pinned revision and run the full suite (deselecting known upstream failures):
bash scripts/build-and-test.sh

# Just verify the build (wheel + CLI smoke), skip the test suite:
RUN_TESTS=0 bash scripts/build-and-test.sh

# Build a different revision without editing .strix-ref:
STRIX_REF=<commit-or-branch-or-tag> bash scripts/build-and-test.sh
```

The upstream checkout lands in `./.upstream/strix` and the wheel in
`./.upstream/strix/dist/`.

## Pinned revision

The built revision is pinned in [`.strix-ref`](./.strix-ref). As of this writing
it is `d8c00a8` (upstream `strix-agent` v1.7.0).

### Bumping the pinned revision

1. Update the SHA in `.strix-ref`.
2. Run `bash scripts/build-and-test.sh` locally (or trigger the workflow with a
   `strix_ref` override) and confirm it is green.
3. Review `scripts/known-failures.txt`: remove any entry upstream has fixed, and
   add any newly-discovered pre-existing failure **with a one-line reason**.
4. Open a PR; CI must pass before merge.

## Known upstream test failures

At the pinned ref, two upstream unit tests fail for reasons unrelated to
packaging/build health, so CI deselects them (see `scripts/known-failures.txt`
for the exact node IDs and rationale):

- a cost-estimate test that depends on litellm's bundled model price map
  resolving a specific model name, and
- an async-timing assertion in the MCP resilience tests.

A green CI run therefore means *"Strix builds and nothing new regressed"* rather
than hiding these pre-existing failures silently. If this list ever grows on a
bump, treat it as a signal and investigate before merging.

## Claude Code cloud sessions

When you open a [Claude Code cloud session](https://code.claude.com/docs/en/claude-code-on-the-web)
on this repo, the SessionStart hook runs synchronously and prepares the upstream
checkout + virtualenv, exporting `STRIX_SRC_DIR` to point at it. You can then
`cd "$STRIX_SRC_DIR"` and run `uv run pytest`, `uv build --wheel`, etc. right
away. The hook only runs in cloud sessions (guarded by `CLAUDE_CODE_REMOTE`).

---

Strix itself is authorized-use-only: only test systems you own or have explicit
written permission to test. See the
[upstream README](https://github.com/usestrix/strix#readme) for Strix's own usage
and licensing terms.
