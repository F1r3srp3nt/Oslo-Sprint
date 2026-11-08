#!/bin/bash
# Runs Distil's test suite (TokenLabCoreTests). Testing only: this does not build or package the app.
# Works from any directory, on macOS (needs Xcode's XCTest) and on Linux.
#
# Usage: bash distil/scripts/test.sh
#        TOKENLAB_ENCODINGS_DIR=/folder/with/tiktoken/files bash distil/scripts/test.sh   # also the 3 tokenizer tests
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

bash "$ROOT/scripts/check-prereqs.sh" --tests || exit 1

mkdir -p "$ROOT/.build"
LOG="$ROOT/.build/test.log"
echo "Running: swift test   (full output also in $LOG)"
swift test 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

echo
summary="$(grep -E 'Executed [0-9]+ tests?, with' "$LOG" | tail -1)"
if [[ -n "$summary" ]]; then
  run="$(sed -nE 's/.*Executed ([0-9]+) tests?.*/\1/p' <<<"$summary")"
  skipped="$(sed -nE 's/.* with ([0-9]+) tests? skipped.*/\1/p' <<<"$summary")"
  failed="$(sed -nE 's/.* and ([0-9]+) failures?.*/\1/p; s/.*, with ([0-9]+) failures?.*/\1/p' <<<"$summary" | head -1)"
  echo "Tests: ${run} run, ${skipped:-0} skipped, ${failed:-?} failed."
  [[ "${skipped:-0}" != 0 ]] && echo "Skipped tests need the official tokenizer files (see README: TOKENLAB_ENCODINGS_DIR)."
elif grep -q "no such module 'XCTest'" "$LOG"; then
  echo "Tests did NOT run: the test targets could not be compiled because XCTest is missing from the selected"
  echo "developer tools (usually Command Line Tools instead of Xcode). This is a toolchain problem, not an app crash."
  echo "Run: bash $ROOT/scripts/check-prereqs.sh --tests   for the exact fix."
else
  echo "Tests did NOT run to completion (swift test exited with status $status before reporting results)."
  echo "See the first 'error:' lines in $LOG."
fi

if [[ $status -eq 0 ]]; then echo "Result: PASS"; else echo "Result: FAIL (swift test exit status $status)"; fi
exit $status
