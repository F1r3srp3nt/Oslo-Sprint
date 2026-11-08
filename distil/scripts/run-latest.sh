#!/bin/bash
# One command: package dist/Distil.app, then open exactly that copy, and confirm it started.
# Nothing is opened unless packaging succeeded. `open` only brings an already-running Distil to the
# front, so any running copy (same bundle identifier, including older "Token Lab" builds) is asked
# to quit first. Quitting goes through the app's normal unsaved-changes prompt; if you cancel it,
# this script stops without launching. Nothing is deleted. Does not run the tests (scripts/test.sh).
set -uo pipefail
cd "$(dirname "$0")/.."
bundle_id="dev.tokenlab.prototype"
APP="$PWD/dist/Distil.app"
EXE="$APP/Contents/MacOS/Distil"
running() { pgrep -f "/Contents/MacOS/(Distil|TokenLab)( |$)" >/dev/null 2>&1; }

bash scripts/package.sh || { echo "Not opening anything: packaging did not succeed."; exit 1; }

echo
echo "== Launch =="
if running; then
  echo "Asking the running Distil to quit…"
  osascript -e "tell application id \"$bundle_id\" to quit" || true
  for _ in $(seq 1 60); do running || break; sleep 0.5; done
  if running; then
    echo "Distil is still running (quit was cancelled or is waiting for you). Not launching a second copy." >&2
    echo "The new build is ready at $APP" >&2
    exit 1
  fi
fi

open "$APP" || { echo "LAUNCH FAILED: open could not start $APP (the build itself succeeded)." >&2; exit 4; }
pid=""
for _ in $(seq 1 30); do
  pid="$(ps -axo pid=,command= | grep -F "$EXE" | grep -v grep | awk '{print $1}' | head -1)"
  [[ -n "$pid" ]] && break
  sleep 0.5
done
if [[ -z "$pid" ]]; then
  echo "LAUNCH FAILED: $APP was opened but no process from it is running after 15 s." >&2
  echo "The build succeeded; the app exited or crashed at launch. Recent crash reports:" >&2
  ls -t ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i '^Distil' | head -3 | sed 's/^/  /' >&2
  exit 4
fi
echo "LAUNCHED: $APP (pid $pid)"
echo "Settings › About this build shows the commit and build time."
