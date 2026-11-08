#!/usr/bin/env bash
# macOS build verification for Relay. Writes everything to build/verify-macos.log.
#
#   ./scripts/verify-macos.sh                 # prerequisites, tests, Relay.app bundle (each reported separately)
#   ./scripts/verify-macos.sh --launch-check  # also opens Relay.app with --self-check to confirm it starts, then it quits
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
  elif [[ $status -eq 3 ]]; then
    SUMMARY+=("NOT RUN  $label (a prerequisite is missing; see the log)")
    FAILED=1
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

run "Prerequisites for packaging (scripts/check-prerequisites.sh)" scripts/check-prerequisites.sh package
run "Tests (scripts/test.sh: source build, test compilation, test run)" scripts/test.sh
run "Packaging (scripts/package.sh: release Relay.app, no tests)" scripts/package.sh

if [[ $LAUNCH_CHECK -eq 1 && -d build/Relay.app ]]; then
  run "Launch verification (scripts/verify-launch.sh)" scripts/verify-launch.sh
elif [[ $LAUNCH_CHECK -eq 0 ]]; then
  SUMMARY+=("SKIP  Launch verification (run with --launch-check)")
else
  SUMMARY+=("SKIP  Launch verification (no Relay.app was packaged)")
fi

section "Summary"
printf '%s\n' "${SUMMARY[@]}" | tee -a "$LOG"
echo
echo "Full log: $(pwd)/$LOG"
echo "It contains build output and toolchain versions only (no keys). Send this file back."
exit $FAILED
