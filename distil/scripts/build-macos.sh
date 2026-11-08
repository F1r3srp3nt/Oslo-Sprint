#!/bin/bash
# Builds a local development Distil.app. Does not notarize, publish, upload or install anything.
# Usage: bash scripts/build-macos.sh            (runs tests first)
#        SKIP_TESTS=1 bash scripts/build-macos.sh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This app must be built on macOS with Xcode or its command-line tools." >&2
  exit 1
fi
if [[ "${SKIP_TESTS:-0}" != 1 ]]; then swift test; fi
swift build -c release --product Distil
binary_dir="$(swift build -c release --show-bin-path)"

# Identify this build so Settings → About can show which copy is running.
commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain -- . 2>/dev/null)" ]]; then commit="$commit+uncommitted"; fi
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Older copies (for example dist/Token Lab.app from builds before 0.4, or copies elsewhere) are
# left untouched. Only this build's own output, dist/Distil.app, is replaced.
app_dir="$PWD/dist/Distil.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/Distil" "$app_dir/Contents/MacOS/Distil"
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Distil</string>
<key>CFBundleDisplayName</key><string>Distil</string>
<key>CFBundleExecutable</key><string>Distil</string>
<key>CFBundleIdentifier</key><string>dev.tokenlab.prototype</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>DistilGitCommit</key><string>${commit}</string>
<key>DistilBuildDate</key><string>${built_at}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
printf 'Built local development app: %s (commit %s, built %s)\n' "$app_dir" "$commit" "$built_at"
printf 'Open exactly this copy with:\n  open "%s"\n' "$app_dir"
