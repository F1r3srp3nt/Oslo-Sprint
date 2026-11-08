#!/usr/bin/env bash
# macOS build verification for Relay. Writes everything to build/verify-macos.log.
#
#   ./scripts/verify-macos.sh                 # toolchain, swift build (incl. app), swift test, Relay.app bundle
#   ./scripts/verify-macos.sh --launch-check  # also opens Relay.app for ~6 s to confirm it starts, then quits it
#
# It never reads the Keychain, never prints credentials and makes no ElevenLabs requests
# (Relay makes none at launch; speech tests only run from buttons in the app).
set -uo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "verify-macos.sh must run on macOS." >&2
  exit 1
fi

LAUNCH_CHECK=0
[[ "${1:-}" == "--launch-check" ]] && LAUNCH_CHECK=1

mkdir -p build
LOG="build/verify-macos.log"
: > "$LOG"
declare -a SUMMARY=()
FAILED=0

section() { printf '\n===== %s =====\n' "$1" | tee -a "$LOG"; }

# run <label> <command...>: runs, logs full output, records PASS/FAIL.
run() {
  local label="$1"; shift
  section "$label"
  echo "\$ $*" >> "$LOG"
  "$@" >> "$LOG" 2>&1
  local status=$?
  if [[ $status -eq 0 ]]; then
    SUMMARY+=("PASS  $label")
  else
    SUMMARY+=("FAIL  $label (exit $status)")
    FAILED=1
  fi
  return $status
}

section "Environment"
{
  echo "date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  sw_vers
  echo "arch: $(uname -m)"
  echo "xcode-select: $(xcode-select -p 2>&1)"
  xcodebuild -version 2>&1
  swift --version 2>&1
  echo "git HEAD: $(git rev-parse --short HEAD 2>&1) on $(git rev-parse --abbrev-ref HEAD 2>&1)"
  echo "uncommitted changes under relay/:"; git status --short -- . 2>&1
} >> "$LOG" 2>&1

run "swift build (core, adapters, runner and the Relay app)" swift build
run "swift test" swift test
run "scripts/build-app.sh (release Relay.app)" ./scripts/build-app.sh

if [[ -d build/Relay.app ]]; then
  run "codesign --verify build/Relay.app" codesign --verify --verbose build/Relay.app
  run "Info.plist has NSMicrophoneUsageDescription" \
      /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" build/Relay.app/Contents/Info.plist
fi

if [[ $LAUNCH_CHECK -eq 1 && -d build/Relay.app ]]; then
  section "Launch check"
  open build/Relay.app >> "$LOG" 2>&1
  sleep 6
  if pgrep -x Relay >/dev/null; then
    echo "Relay process is running after 6 s." >> "$LOG"
    SUMMARY+=("PASS  App launched and stayed running for 6 s")
    osascript -e 'tell application "Relay" to quit' >> "$LOG" 2>&1 || true
  else
    echo "Relay process was NOT running after 6 s. Recent crash reports:" >> "$LOG"
    ls -t ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i relay | head -3 >> "$LOG"
    SUMMARY+=("FAIL  App launch (process not running after 6 s)")
    FAILED=1
  fi
elif [[ $LAUNCH_CHECK -eq 0 ]]; then
  SUMMARY+=("SKIP  App launch (run with --launch-check)")
fi

section "Summary"
printf '%s\n' "${SUMMARY[@]}" | tee -a "$LOG"
echo
echo "Full log: $(pwd)/$LOG"
echo "It contains build output and toolchain versions only (no keys). Send this file back."
exit $FAILED
