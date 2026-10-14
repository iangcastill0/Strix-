#!/bin/bash
#
# Strix.app bundle executable (Contents/MacOS/Strix).
#
# Strix is an interactive CLI/TUI, so double-clicking the app opens Terminal
# with the bundled `strix` engine ready to use. This script is self-locating:
# it resolves its own place inside the .app bundle, so it works wherever the
# app is installed (e.g. /Applications/Strix.app).
#
set -euo pipefail

CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$CONTENTS/Resources/bin/strix"

# Build the per-launch session script in a writable temp location. We do NOT
# execute a script from inside the (possibly quarantined, read-only) bundle;
# Terminal runs this freshly-created, un-quarantined .command instead.
TMP="$(mktemp -t strix-launch-XXXXXX)"
CMD="$TMP.command"
mv "$TMP" "$CMD"

cat > "$CMD" <<EOF
#!/bin/bash
clear
cat <<'BANNER'
==================================================
   Strix - open-source AI penetration testing
==================================================
BANNER
echo
if ! command -v docker >/dev/null 2>&1; then
  echo "WARNING: Docker was not found. Strix needs Docker Desktop installed and running."
  echo "         Download: https://www.docker.com/products/docker-desktop/"
  echo
elif ! docker info >/dev/null 2>&1; then
  echo "WARNING: Docker is installed but its daemon isn't running."
  echo "         Start Docker Desktop, then try your command again."
  echo
fi
cat <<'USAGE'
The 'strix' command is ready in this window. Examples:
  strix --target ./my-app                     # scan a local codebase
  strix --target https://github.com/org/repo  # scan a repository
  strix --target https://your-app.com         # scan a live web app
  strix view                                   # open the results dashboard
  strix --help                                 # all options

Authorized use only: test systems you own or have written permission to test.
USAGE
echo
# Expose the bundled engine as the 'strix' command (survives into the shell
# via an exported function, so it works regardless of PATH/login-shell quirks).
strix() { "$BIN" "\$@"; }
export -f strix
exec /bin/bash -i
EOF

chmod +x "$CMD"
open -a Terminal "$CMD"
