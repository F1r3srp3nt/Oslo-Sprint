#!/usr/bin/env bash
# Launch verification for the packaged build/Relay.app (macOS). Separate from building: run
# scripts/package.sh first. Opens exactly that bundle through Launch Services with --self-check;
# the app writes what it sees (bundle identifier, Info.plist values, visible windows, bundled
# resources) to build/logs/launch-report.json and quits. Makes no network requests and does not
# read the Keychain. Exit status: 0 verified; 1 nothing to verify; 4 the app did not start or
# report; 5 it started but the report does not match the bundle.
set -uo pipefail
cd "$(dirname "$0")/.."
PRODUCT="Relay"
BUNDLE_ID="com.oslosprint.relay"
COMMIT_KEY="RelayGitCommit"
APP="$PWD/build/$PRODUCT.app"
EXE="$APP/Contents/MacOS/$PRODUCT"
REPORT="$PWD/build/logs/launch-report.json"
TIMEOUT="${LAUNCH_TIMEOUT:-60}"

[[ "$(uname -s)" == Darwin ]] || { echo "verify-launch.sh needs macOS." >&2; exit 1; }
[[ -x "$EXE" ]] || { echo "Nothing to verify: $APP is not packaged. Run scripts/package.sh first." >&2; exit 1; }
if pgrep -f "/Contents/MacOS/$PRODUCT( |$)" >/dev/null 2>&1; then
  echo "A copy of $PRODUCT is already running. Quit it first, so this check starts a fresh process." >&2
  exit 1
fi

mkdir -p "$(dirname "$REPORT")"
rm -f "$REPORT"
echo "Opening $APP with --self-check…"
started=$(date +%s)
if ! open -n "$APP" --args -ApplePersistenceIgnoreState YES --self-check "$REPORT"; then
  echo "LAUNCH FAILED: Launch Services refused to open $APP (the build itself succeeded)." >&2
  exit 4
fi

pid=""
while [[ ! -s "$REPORT" && $(( $(date +%s) - started )) -lt $TIMEOUT ]]; do
  [[ -z "$pid" ]] && pid="$(ps -axo pid=,command= | grep -F "$EXE" | grep -v grep | awk '{print $1}' | head -1)"
  sleep 1
done
stop() {
  local p
  p="$(ps -axo pid=,command= | grep -F "$EXE" | grep -v grep | awk '{print $1}')"
  [[ -n "$p" ]] && kill $p 2>/dev/null
  return 0
}

if [[ ! -s "$REPORT" ]]; then
  stop
  if [[ -z "$pid" ]]; then
    echo "LAUNCH FAILED: no $PRODUCT process appeared within ${TIMEOUT}s. The build succeeded; the app did not start." >&2
  else
    echo "LAUNCH FAILED: $PRODUCT started (pid $pid) but wrote no report within ${TIMEOUT}s (it exited, crashed or hung)." >&2
  fi
  ls -t ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i "^$PRODUCT" | head -3 | sed 's/^/  crash report: /' >&2
  exit 4
fi
sleep 2; stop

field() { plutil -extract "$1" raw -o - "$REPORT" 2>/dev/null; }
expected_commit="$(/usr/libexec/PlistBuddy -c "Print :$COMMIT_KEY" "$APP/Contents/Info.plist" 2>/dev/null)"
problems=0
check() {  # check <label> <actual> <expected>
  if [[ "$2" == "$3" ]]; then echo "  OK    $1: $2"; else echo "  FAIL  $1: got '$2', expected '$3'"; problems=$((problems + 1)); fi
}
echo "Report from the running app ($REPORT):"
check "bundle identifier" "$(field bundleIdentifier)" "$BUNDLE_ID"
check "bundle path" "$(cd "$(field bundlePath)" 2>/dev/null && pwd -P)" "$(cd "$APP" && pwd -P)"
check "executable" "$(field executable)" "$PRODUCT"
check "commit read from Info.plist" "$(field commit)" "$expected_commit"
windows="$(field visibleWindows)"
if [[ "${windows:-0}" -ge 1 ]]; then echo "  OK    visible windows: $windows"
else echo "  FAIL  visible windows: ${windows:-none}"; problems=$((problems + 1)); fi
echo "  INFO  version $(field version) ($(field build)), appearance $(field appearance)"
echo "  INFO  bundled resources: $(plutil -extract resourceFiles json -o - "$REPORT" 2>/dev/null)"

if [[ $problems -eq 0 ]]; then
  echo "LAUNCH VERIFIED: $APP started, showed a window and read its own Info.plist."
  exit 0
fi
echo "LAUNCH CHECK FAILED: the app started, but $problems check(s) above did not match."
exit 5
