#!/bin/bash
# Kept for existing instructions: same as scripts/package.sh (builds dist/Distil.app). Packaging no
# longer runs the tests, so SKIP_TESTS is no longer needed; run scripts/test.sh for them.
if [[ -n "${SKIP_TESTS:-}" ]]; then echo "Note: SKIP_TESTS is ignored; packaging never runs the tests."; fi
exec "$(dirname "$0")/package.sh" "$@"
