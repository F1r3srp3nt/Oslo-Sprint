#!/usr/bin/env bash
# One command: package build/Relay.app, then open exactly that copy, and confirm it started.
# Nothing is opened unless packaging succeeded. `open` only brings an already-running Relay to the
# front, so a running copy (same bundle identifier) is asked to quit first. Nothing is deleted:
# other copies of Relay.app, preferences and Keychain items stay where they are.
# Does not run the tests (scripts/test.sh does).
set -uo pipefail
cd "$(dirname "$0")/.."
bundle_id="com.oslosprint.relay"
APP="$PWD/build/Relay.app"
EXE="$APP/Contents/MacOS/Relay"

scripts/package.sh || { echo "Not opening anything: packaging did not succeed."; exit 1; }

echo
echo "== Launch =="
if pgrep -f "/Contents/MacOS/Relay( |$)" >/dev/null 2>&1; then
  echo "Asking the running Relay to quit…"
  osascript -e "tell application id \"$bundle_id\" to quit" || true
  for _ in $(seq 1 40); do
    pgrep -f "/Contents/MacOS/Relay( |$)" >/dev/null 2>&1 || break
    sleep 0.5
  done
  if pgrep -f "/Contents/MacOS/Relay( |$)" >/dev/null 2>&1; then
    echo "Relay is still running (quit was cancelled or is waiting). Not launching a second copy." >&2
    echo "The new build is ready at $APP" >&2
    exit 1
  fi
fi

open "$APP" || { echo "LAUNCH FAILED: open could not start $APP (the build itself succeeded)." >&2; exit 4; }
for _ in $(seq 1 30); do
  pid="$(ps -axo pid=,command= | grep -F "$EXE" | grep -v grep | awk '{print $1}' | head -1)"
  [[ -n "$pid" ]] && break
  sleep 0.5
done
if [[ -z "${pid:-}" ]]; then
  echo "LAUNCH FAILED: $APP was opened but no process from it is running after 15 s." >&2
  echo "The build succeeded; the app exited or crashed at launch. Recent crash reports:" >&2
  ls -t ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i '^Relay' | head -3 | sed 's/^/  /' >&2
  exit 4
fi
echo "LAUNCHED: $APP (pid $pid)"
echo "The sidebar's Build card and Settings › About this build show the commit and build time."
