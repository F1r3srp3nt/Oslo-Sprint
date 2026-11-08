#!/bin/bash
# Builds dist/Distil.app and opens that exact copy.
# `open` only brings an already-running Distil to the front, so any running copy (same bundle
# identifier, including older "Token Lab" builds) is asked to quit first. Quitting goes through the
# app's normal unsaved-changes prompt; if you cancel it, this script stops without launching.
set -euo pipefail
cd "$(dirname "$0")/.."
bundle_id="dev.tokenlab.prototype"

bash scripts/build-macos.sh

if pgrep -f "/Contents/MacOS/(Distil|TokenLab)$" >/dev/null 2>&1; then
  echo "Asking the running Distil to quit…"
  osascript -e "tell application id \"$bundle_id\" to quit" || true
  for _ in $(seq 1 60); do
    pgrep -f "/Contents/MacOS/(Distil|TokenLab)$" >/dev/null 2>&1 || break
    sleep 0.5
  done
  if pgrep -f "/Contents/MacOS/(Distil|TokenLab)$" >/dev/null 2>&1; then
    echo "Distil is still running (quit was cancelled or is waiting for you). Not launching a second copy." >&2
    exit 1
  fi
fi

open "$PWD/dist/Distil.app"
echo "Opened $PWD/dist/Distil.app — the sidebar's Build card and Settings › About this build show the commit and build time."
