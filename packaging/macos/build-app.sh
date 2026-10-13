#!/usr/bin/env bash
#
# Assemble a native macOS Strix.app bundle (+ .dmg and zipped .app) around the
# PyInstaller-built `strix` engine binary. Runs on macOS only (uses sips,
# iconutil, codesign, hdiutil, ditto).
#
# Required environment:
#   STRIX_BIN   path to the PyInstaller onefile binary (e.g. $SRC/dist/strix)
#   STRIX_SRC   upstream checkout (for pyproject version + viewer logo)
#   ARCH        arch label for output filenames (arm64 | x86_64)
#   OUT         directory to write Strix-<ver>-<arch>.{dmg,app.zip} into
#
set -euo pipefail

: "${STRIX_BIN:?set STRIX_BIN to the PyInstaller binary}"
: "${STRIX_SRC:?set STRIX_SRC to the upstream checkout}"
: "${ARCH:?set ARCH to arm64 or x86_64}"
: "${OUT:?set OUT to the output directory}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: build-app.sh must run on macOS (got $(uname -s))" >&2
  exit 1
fi
[ -f "$STRIX_BIN" ] || { echo "error: STRIX_BIN not found: $STRIX_BIN" >&2; exit 1; }

VERSION="$(grep -m1 '^version' "$STRIX_SRC/pyproject.toml" | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "$VERSION" ] || { echo "error: could not read version from pyproject.toml" >&2; exit 1; }
echo "==> Building Strix.app  version=$VERSION  arch=$ARCH"

WORK="$(mktemp -d)"
APP="$WORK/Strix.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"

# 1. Engine binary
cp "$STRIX_BIN" "$APP/Contents/Resources/bin/strix"
chmod +x "$APP/Contents/Resources/bin/strix"

# 2. Launcher (bundle executable)
cp "$HERE/Strix.launcher.sh" "$APP/Contents/MacOS/Strix"
chmod +x "$APP/Contents/MacOS/Strix"

# 3. Info.plist (substitute version)
sed "s/__VERSION__/$VERSION/g" "$HERE/Info.plist.template" > "$APP/Contents/Info.plist"

# 4. Icon from upstream's viewer logo (best-effort; app still works without one)
LOGO="$STRIX_SRC/strix/interface/viewer/static/logo.png"
if [ -f "$LOGO" ]; then
  ICONSET="$WORK/strix.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s"       "$LOGO" --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$LOGO" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/strix.icns"; then
    echo "==> Icon generated from $LOGO"
  else
    echo "==> iconutil failed; shipping without a custom icon"
    rm -f "$APP/Contents/Resources/strix.icns"
  fi
else
  echo "==> No logo found at $LOGO; shipping without a custom icon"
fi

# 5. Ad-hoc code signature (required for the app to launch on Apple Silicon;
#    does NOT avoid the Gatekeeper warning for downloaded apps — that needs a
#    Developer ID certificate + notarization).
codesign --force --deep --sign - "$APP" \
  && echo "==> Ad-hoc signed" \
  || echo "==> WARNING: ad-hoc codesign failed; the app may be blocked on launch"

mkdir -p "$OUT"

# 6. Zipped .app (ditto preserves bundle metadata better than zip)
APP_ZIP="$OUT/Strix-$VERSION-$ARCH.app.zip"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
echo "==> Wrote $APP_ZIP"

# 7. DMG with an /Applications drop target for drag-install
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Strix-$VERSION-$ARCH.dmg"
hdiutil create -volname "Strix" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "==> Wrote $DMG"

# 8. Smoke-check the bundled engine runs
"$APP/Contents/Resources/bin/strix" --version && echo "==> Bundled engine OK"

echo "==> Done:"
ls -lh "$OUT"/Strix-"$VERSION"-"$ARCH".* 2>/dev/null || true
