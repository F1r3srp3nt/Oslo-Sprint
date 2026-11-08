#!/usr/bin/env bash
# Builds relay/build/Relay.app and opens that exact copy.
# `open` only brings an already-running Relay to the front, so a running copy (same bundle
# identifier) is asked to quit first. Nothing is deleted: other copies of Relay.app stay where they are.
set -euo pipefail
cd "$(dirname "$0")/.."
bundle_id="com.oslosprint.relay"

./scripts/build-app.sh

if pgrep -f "/Contents/MacOS/Relay$" >/dev/null 2>&1; then
  echo "Asking the running Relay to quit…"
  osascript -e "tell application id \"$bundle_id\" to quit" || true
  for _ in $(seq 1 40); do
    pgrep -f "/Contents/MacOS/Relay$" >/dev/null 2>&1 || break
    sleep 0.5
  done
  if pgrep -f "/Contents/MacOS/Relay$" >/dev/null 2>&1; then
    echo "Relay is still running. Not launching a second copy." >&2
    exit 1
  fi
fi

open "$PWD/build/Relay.app"
echo "Opened $PWD/build/Relay.app — the sidebar's Build card and Settings › About this build show the commit and build time."
