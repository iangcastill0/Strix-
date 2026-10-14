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
| `.github/workflows/mac-app.yml` | GitHub Actions (macOS runners): builds a native **`Strix.app` + DMG** for Apple Silicon and Intel. |
| `packaging/macos/` | The macOS app packaging: `build-app.sh`, the `Strix.launcher.sh` bundle executable, and `Info.plist.template`. |
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

## Native macOS app (`Strix.app` + DMG)

The [`Build macOS App`](./.github/workflows/mac-app.yml) workflow builds a native
`Strix.app` bundle and a `.dmg` installer for **Apple Silicon (arm64)** and
**Intel (x86_64)** — no Python install required on the end-user's Mac. It runs
on GitHub-hosted macOS runners because PyInstaller cannot cross-compile; you
cannot build the Mac app from a Linux machine.

How it's built, per arch, from the pinned upstream ref:

1. `make tui-build` compiles the Go TUI sidecar.
2. `uv sync --frozen` + `uv run pyinstaller strix.spec` produce a self-contained
   `strix` engine binary (upstream's own PyInstaller spec).
3. `packaging/macos/build-app.sh` wraps that binary in `Strix.app` — a
   Terminal-launcher app (`Strix.launcher.sh`) with an `Info.plist` and an icon
   generated from upstream's viewer logo — ad-hoc signs it, and packages a DMG
   with an `/Applications` drop target.

**Get the app:**

- Push a tag `app-v*` (e.g. `app-v1.7.0`) to publish a GitHub Release with the
  DMGs and zipped apps attached, **or**
- Run the workflow manually (Actions → *Build macOS App* → *Run workflow*) and
  download the `strix-macos-arm64` / `strix-macos-x86_64` artifacts.

**What the app does:** double-clicking `Strix.app` opens Terminal with the
bundled `strix` command ready (`strix --target …`, `strix view`, `strix --help`).
It is a native wrapper around the Strix engine, not a separate GUI.

**Important caveats:**

- **Docker is still required.** The app checks for Docker Desktop on launch and
  warns if it's missing or not running — native packaging removes the Python
  install step, not Strix's Docker dependency.
- **Gatekeeper.** The app is only *ad-hoc* signed (enough to launch, especially
  on Apple Silicon). Because it isn't signed with an Apple Developer ID or
  notarized, macOS will warn on first open of a downloaded copy — right-click →
  **Open** once, or run `xattr -dr com.apple.quarantine /Applications/Strix.app`.
  To ship without that warning, add a Developer ID certificate + notarization
  step (wire the signing identity in as repo secrets).

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
