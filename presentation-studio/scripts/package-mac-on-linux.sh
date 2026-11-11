#!/usr/bin/env bash
# Builds "Presentation Studio.app" for macOS Apple Silicon on a Linux machine, ad-hoc signs it with
# rcodesign (Apple Silicon refuses to run unsigned arm64 code), and zips it with symlinks preserved.
#
# On a Mac, use `npm run desktop:dist:mac` instead: electron-builder signs ad hoc with Apple's codesign
# and also produces the DMG (DMGs cannot be built on Linux).
#
# Requires: rcodesign (cargo install apple-codesign), zip. Set RCODESIGN=/path/to/rcodesign if not on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

RCODESIGN="${RCODESIGN:-$(command -v rcodesign || true)}"
if [ -z "$RCODESIGN" ] || [ ! -x "$RCODESIGN" ]; then
  echo "rcodesign not found. Install it with: cargo install apple-codesign --locked (or set RCODESIGN=...)" >&2
  exit 1
fi

VERSION=$(node -p "require('./package.json').version")
APP="release/mac-arm64/Presentation Studio.app"
ZIP="release/Presentation-Studio-${VERSION}-mac-arm64.zip"

node scripts/build-desktop.mjs
rm -rf release/mac-arm64
npx electron-builder --mac dir --arm64

echo "• ad-hoc signing (rcodesign)"
"$RCODESIGN" sign "$APP"

echo "• zipping (symlinks preserved, as Finder's Archive Utility expects)"
rm -f "$ZIP"
(cd release/mac-arm64 && zip -qry "../$(basename "$ZIP")" "Presentation Studio.app")
(cd release && sha256sum "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "Built $APP"
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1))"
