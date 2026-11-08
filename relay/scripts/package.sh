#!/usr/bin/env bash
# Packages build/Relay.app (release). macOS only. Compiles the Relay product only: no test targets,
# so it works with the Command Line Tools as well as Xcode. Run scripts/test.sh for the tests.
# Signs ad hoc for local use. Does not notarize, install, upload or publish anything.
#
# Stages: prerequisites → app compilation → bundle assembly → signing → bundle verification.
# Exit status: 0 packaged and verified; 1 prerequisites missing; 2 a stage failed (named in the output).
set -uo pipefail
cd "$(dirname "$0")/.."

PRODUCT="Relay"                      # executable product in Package.swift (macOS only)
APP_NAME="Relay"
BUNDLE_ID="com.oslosprint.relay"     # keep: Keychain items and preferences belong to this identifier
VERSION="0.2.0"
BUILD_NUMBER="2"
MIN_MACOS="14.0"
APP="$PWD/build/$APP_NAME.app"

stage_name=""
stage() { stage_name="$1"; printf '\n== %s ==\n' "$1"; }
die() {
  echo
  echo "PACKAGING FAILED at stage: $stage_name. $1"
  echo "The app was not launched; this is not an app crash."
  exit 2
}

stage "Prerequisites"
if ! scripts/check-prerequisites.sh package; then
  echo "PACKAGING NOT STARTED: a prerequisite is missing (see the fixes above)."
  exit 1
fi

stage "App compilation (swift build -c release --product $PRODUCT)"
swift build -c release --product "$PRODUCT" || die "The $PRODUCT product did not compile; the compiler errors are above."
BIN_DIR="$(swift build -c release --show-bin-path)" || die "swift build --show-bin-path failed."
[[ -x "$BIN_DIR/$PRODUCT" ]] || die "No executable at $BIN_DIR/$PRODUCT."

stage "Bundle assembly ($APP)"
# Identify this build so the app (sidebar Build card, Settings › About this build) shows which copy runs.
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain -- . 2>/dev/null)" ]]; then COMMIT="$COMMIT+uncommitted"; fi
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Only this build's own output is replaced. Copies elsewhere, preferences and Keychain items are untouched.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" || die "Cannot create $APP."
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT" || die "Cannot copy the executable."
printf 'APPL????' > "$APP/Contents/PkgInfo"
# SwiftPM resource bundles, if a target ever declares resources (none do today).
resource_bundles=0
for bundle in "$BIN_DIR"/*.bundle; do
  [[ -d "$bundle" ]] || continue
  cp -R "$bundle" "$APP/Contents/Resources/" || die "Cannot copy resource bundle $bundle."
  resource_bundles=$((resource_bundles + 1))
done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$PRODUCT</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>RelayGitCommit</key><string>${COMMIT}</string>
  <key>RelayBuildDate</key><string>${BUILT_AT}</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Relay records only while you hold the push-to-talk button, and sends that recording to ElevenLabs for transcription.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null || die "Info.plist is not valid."

stage "Signing (ad hoc)"
codesign --force --sign - --timestamp=none "$APP" || die "codesign failed."

stage "Bundle verification"
codesign --verify --strict --verbose=1 "$APP" || die "The signature does not verify."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")" == "$PRODUCT" ]] \
  || die "CFBundleExecutable does not name the executable."
/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$APP/Contents/Info.plist" >/dev/null \
  || die "NSMicrophoneUsageDescription is missing; macOS would terminate the app at push-to-talk."
echo "Executable: $(lipo -archs "$APP/Contents/MacOS/$PRODUCT" 2>/dev/null || uname -m)"
echo "Resource bundles: $resource_bundles"

echo
echo "PACKAGED: $APP"
echo "  $APP_NAME $VERSION ($BUILD_NUMBER), $BUNDLE_ID, commit $COMMIT, built $BUILT_AT"
echo "Open exactly this copy with:"
echo "  open \"$APP\""
echo "or build and open in one step: scripts/run-latest.sh"
