#!/usr/bin/env bash
# Builds and tests the platform-independent parts (RelayCore, RelayAdapters, relay-runner); on macOS
# `swift build` also compiles the SwiftUI app target. Testing only: no Relay.app is packaged
# (scripts/build-app.sh does that). Works from any directory, on macOS (needs Xcode's XCTest) and Linux.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

bash "$ROOT/scripts/check-prereqs.sh" --tests || exit 1

mkdir -p "$ROOT/.build"
LOG="$ROOT/.build/test.log"
echo "Running: swift build && swift test   (full output also in $LOG)"
{ swift build && swift test; } 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

echo
summary="$(grep -E 'Executed [0-9]+ tests?, with' "$LOG" | tail -1)"
if [[ -n "$summary" ]]; then
  run="$(sed -nE 's/.*Executed ([0-9]+) tests?.*/\1/p' <<<"$summary")"
  skipped="$(sed -nE 's/.* with ([0-9]+) tests? skipped.*/\1/p' <<<"$summary")"
  failed="$(sed -nE 's/.* and ([0-9]+) failures?.*/\1/p; s/.*, with ([0-9]+) failures?.*/\1/p' <<<"$summary" | head -1)"
  echo "Tests: ${run} run, ${skipped:-0} skipped, ${failed:-?} failed."
elif grep -q "no such module 'XCTest'" "$LOG"; then
  echo "Tests did NOT run: the test targets could not be compiled because XCTest is missing from the selected"
  echo "developer tools (usually Command Line Tools instead of Xcode). This is a toolchain problem, not an app crash."
  echo "Run: bash $ROOT/scripts/check-prereqs.sh --tests   for the exact fix."
else
  echo "Tests did NOT run to completion (exit status $status before results were reported)."
  echo "See the first 'error:' lines in $LOG."
fi

if [[ $status -eq 0 ]]; then echo "OK: build and tests passed on $(uname -s)"; else echo "Result: FAIL (exit status $status)"; fi
exit $status
