#!/usr/bin/env bash
# macOS only. Builds Relay.app (release), with the microphone usage description that macOS
# requires for push-to-talk, and signs it ad hoc for local use. Nothing is uploaded.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-app.sh needs macOS (SwiftUI/AppKit). On Linux use scripts/test.sh." >&2
  exit 1
fi
swift build -c release --product Relay
BIN="$(swift build -c release --show-bin-path)/Relay"
APP="$PWD/build/Relay.app"
# Identify this build so the app (sidebar Build card, Settings › About this build) shows which copy runs.
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain -- . 2>/dev/null)" ]]; then COMMIT="$COMMIT+uncommitted"; fi
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Relay"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Relay</string>
  <key>CFBundleDisplayName</key><string>Relay</string>
  <key>CFBundleIdentifier</key><string>com.oslosprint.relay</string>
  <key>CFBundleExecutable</key><string>Relay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>RelayGitCommit</key><string>${COMMIT}</string>
  <key>RelayBuildDate</key><string>${BUILT_AT}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Relay records only while you hold the push-to-talk button, and sends that recording to ElevenLabs for transcription.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP (commit $COMMIT, built $BUILT_AT)"
echo "Open exactly this copy with:"
echo "  open \"$APP\""
