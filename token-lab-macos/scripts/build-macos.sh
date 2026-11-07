#!/bin/bash
# Builds a local development .app. Does not notarize, publish, upload or install anything.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This app must be built on macOS with Xcode or its command-line tools." >&2
  exit 1
fi
swift test
swift build -c release --product TokenLab
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/Distil.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/TokenLab" "$app_dir/Contents/MacOS/TokenLab"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Distil</string>
<key>CFBundleDisplayName</key><string>Distil</string>
<key>CFBundleExecutable</key><string>TokenLab</string>
<key>CFBundleIdentifier</key><string>dev.tokenlab.prototype</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
printf 'Built local development app: %s\n' "$app_dir"
