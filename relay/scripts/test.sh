#!/usr/bin/env bash
# Builds and tests the package, in separate stages so a failure says what failed:
#   1. prerequisites      scripts/check-prerequisites.sh test (stops with exact fixes; changes nothing)
#   2. source build       swift build                 (libraries, CLI and, on macOS, the app target)
#   3. test compilation   swift build --build-tests   (the test targets; needs XCTest, i.e. full Xcode)
#   4. test run           swift test --skip-build
# Works on macOS and Linux. Never packages or launches the app (that is scripts/package.sh).
# Full output: build/logs/test.log. Exit status: 0 passed, 1 tests failed, 2 a build failed,
# 3 tests not run because a prerequisite is missing.
set -uo pipefail
cd "$(dirname "$0")/.."
LOG_DIR="build/logs"
mkdir -p "$LOG_DIR"
LOG="$PWD/$LOG_DIR/test.log"
: > "$LOG"

stage() { printf '\n== %s ==\n' "$1" | tee -a "$LOG"; }

# run <command...>: shows and logs the output, returns the command's exit status.
run() { echo "\$ $*" >> "$LOG"; "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }

errors_from_log() { grep -E '(error|fatal error):' "$LOG" | grep -v '^\$' | sort -u | head -10 | sed 's/^/    /'; }

stage "1/4 Prerequisites"
if ! run scripts/check-prerequisites.sh test; then
  echo
  echo "RESULT: tests NOT RUN. A prerequisite is missing (see the fixes above). Nothing was compiled."
  exit 3
fi

stage "2/4 Source build (swift build)"
if ! run swift build; then
  echo
  echo "RESULT: tests NOT RUN. The package's own sources failed to compile (not the tests, not a crash):"
  errors_from_log
  echo "Full log: $LOG"
  exit 2
fi

stage "3/4 Test compilation (swift build --build-tests)"
if ! run swift build --build-tests; then
  echo
  echo "RESULT: tests NOT RUN. The test targets failed to compile. The app was not run, so this is not an app crash:"
  errors_from_log
  if grep -q "no such module 'XCTest'" "$LOG"; then
    echo "  XCTest is missing from the selected developer directory: run scripts/check-prerequisites.sh test for the fix."
  fi
  echo "Full log: $LOG"
  exit 2
fi

stage "4/4 Test run (swift test --skip-build)"
run swift test --skip-build
status=$?
summary="$(grep -E 'Executed [0-9]+ tests?' "$LOG" | tail -1 | sed -E 's/^[[:space:]]+//')"
echo
if [[ $status -eq 0 && -n "$summary" ]]; then
  echo "RESULT: tests PASSED on $(uname -s). $summary"
  exit 0
fi
if [[ -z "$summary" ]]; then
  echo "RESULT: tests DID NOT COMPLETE (exit $status). The test process stopped before reporting a summary,"
  echo "for example a crash inside a test. Last lines:"
  tail -15 "$LOG" | sed 's/^/    /'
else
  echo "RESULT: tests FAILED (exit $status). $summary"
  echo "Failing tests:"
  grep -E "Test Case .*(failed|crashed)" "$LOG" | sort -u | sed 's/^/    /'
fi
echo "Full log: $LOG"
exit 1
