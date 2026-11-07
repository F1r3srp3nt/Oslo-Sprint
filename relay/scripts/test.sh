#!/usr/bin/env bash
# Builds and tests the platform-independent parts (RelayCore, RelayAdapters, relay-runner).
# Works on macOS and Linux. On macOS this also builds the SwiftUI app target.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
swift test
echo "OK: build and tests passed on $(uname -s)"
