#!/usr/bin/env bash
# Checks that this Mac can build (and optionally test) this package. Read-only: it never installs
# anything and never changes the selected developer directory (xcode-select). When something is
# missing it stops and prints the exact command to fix it.
#
#   scripts/check-prerequisites.sh            # what packaging the app needs (swift build, SDK, codesign)
#   scripts/check-prerequisites.sh test       # also what `swift test` needs (XCTest, i.e. full Xcode)
#
# Exit status: 0 = everything needed is present; 1 = something is missing (nothing was built).
# The same file is used by distil/ and relay/; keep the two copies identical.
set -uo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-package}"
case "$MODE" in package|build) MODE=package ;; test) ;; *)
  echo "Usage: $0 [package|test]" >&2; exit 64 ;;
esac

MIN_SWIFT="5.9"      # swift-tools-version in Package.swift
MIN_MACOS="14.0"     # platforms: [.macOS(.v14)] in Package.swift

failures=0
ok()   { printf '  OK    %s\n' "$1"; }
info() { printf '  INFO  %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
fix()  { printf '        fix: %s\n' "$1"; }

# ver_ge A B: true when version A >= version B (numeric, dot-separated).
ver_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, "."); n = na > nb ? na : nb
    for (i = 1; i <= n; i++) { p = x[i] + 0; q = y[i] + 0; if (p > q) exit 0; if (p < q) exit 1 }
    exit 0 }'
}

swift_version() {   # prints e.g. 6.0.3 from `swift --version`
  swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+(\.[0-9]+)*).*/\1/p' | head -1
}

package="$(basename "$PWD")"
echo "Prerequisites for $package ($MODE) on $(uname -s) $(uname -m)"

# --- Linux: core libraries and tests only -----------------------------------------------------------
if [[ "$(uname -s)" != Darwin ]]; then
  if [[ "$MODE" == package ]]; then
    fail "Packaging the macOS app needs macOS (SwiftUI/AppKit). On Linux only the core and its tests build."
    fix "run scripts/test.sh here, or package on a Mac"
  fi
  if command -v swift >/dev/null 2>&1; then
    v="$(swift_version)"
    if [[ -n "$v" ]] && ver_ge "$v" "$MIN_SWIFT"; then ok "Swift $v ($(command -v swift))"
    else fail "Swift ${v:-unknown} is older than $MIN_SWIFT"; fix "install a Swift $MIN_SWIFT+ toolchain from swift.org"; fi
  else
    fail "swift not found on PATH"; fix "install a Swift $MIN_SWIFT+ toolchain from swift.org"
  fi
  [[ $failures -eq 0 ]] && { echo "Ready."; exit 0; }
  echo "Not ready: $failures problem(s) above. Nothing was built."; exit 1
fi

# --- macOS --------------------------------------------------------------------------------------------
macos="$(sw_vers -productVersion 2>/dev/null || echo 0)"
if ver_ge "$macos" "$MIN_MACOS"; then ok "macOS $macos (the app needs $MIN_MACOS or later)"
else fail "macOS $macos is older than $MIN_MACOS, which the app requires"; fix "update macOS to $MIN_MACOS or later"; fi

selected="$(xcode-select -p 2>/dev/null || true)"
dev_dir="${DEVELOPER_DIR:-$selected}"
if [[ -z "$dev_dir" ]]; then
  fail "No developer directory is selected (xcode-select -p failed)"
  fix "xcode-select --install          # Command Line Tools: enough to package the app"
  fix "or install Xcode from the App Store, then: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  echo "Not ready: $failures problem(s) above. Nothing was built."; exit 1
fi
kind="other"
case "$dev_dir" in
  */CommandLineTools|*/CommandLineTools/) kind="clt" ;;
  *.app/Contents/Developer|*.app/Contents/Developer/) kind="xcode" ;;
esac
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  info "DEVELOPER_DIR=$DEVELOPER_DIR is set for this shell (the system selection, $selected, is unchanged)"
fi
case "$kind" in
  clt)   ok "Developer directory: $dev_dir (Command Line Tools)" ;;
  xcode) ok "Developer directory: $dev_dir (Xcode)" ;;
  *)     warn "Developer directory: $dev_dir (neither Xcode.app nor Command Line Tools)" ;;
esac
if [[ ! -d "$dev_dir" ]]; then
  fail "The developer directory $dev_dir does not exist (Xcode moved or deleted?)"
  fix "sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer   (or: sudo xcode-select --reset)"
fi

# Installed copies of Xcode, for precise fix instructions.
xcodes="$( { ls -d /Applications/Xcode*.app 2>/dev/null; mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null; } \
  | grep -v '^$' | sort -u)"
first_xcode="$(printf '%s\n' "$xcodes" | head -1)"
if [[ -n "$xcodes" ]]; then
  info "Xcode installed at: $(printf '%s' "$xcodes" | tr '\n' ' ')"
else
  info "No Xcode.app found (only needed for tests)"
fi

if [[ "$kind" == xcode ]]; then
  if ! xcodebuild -license check >/dev/null 2>&1; then
    fail "The Xcode license has not been accepted, so swift build and swift test refuse to run"
    fix "sudo xcodebuild -license accept"
  fi
  if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    fail "Xcode's first-launch components are not installed"
    fix "sudo xcodebuild -runFirstLaunch"
  fi
fi

swift_path="$(xcrun --find swift 2>/dev/null || true)"
if [[ -z "$swift_path" ]]; then
  fail "xcrun cannot find swift in $dev_dir"
  fix "xcode-select --install   (or select a complete Xcode: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer)"
else
  v="$(swift_version)"
  if [[ -n "$v" ]] && ver_ge "$v" "$MIN_SWIFT"; then ok "Swift $v ($swift_path)"
  else fail "Swift ${v:-unknown} is older than $MIN_SWIFT (Package.swift needs tools version $MIN_SWIFT)"
       fix "install Xcode 15.3 or later (or current Command Line Tools: softwareupdate --list)"; fi
  on_path="$(command -v swift || true)"
  if [[ -n "$on_path" && "$on_path" != /usr/bin/swift && "$on_path" != "$swift_path" ]]; then
    warn "swift on PATH is $on_path, not the selected toolchain's $swift_path (scripts use the PATH one)"
  fi
fi

sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
if [[ -z "$sdk_path" || ! -d "$sdk_path" ]]; then
  fail "No macOS SDK found in $dev_dir"
  fix "xcode-select --install   (or reinstall Xcode)"
elif ver_ge "$sdk_version" "$MIN_MACOS"; then
  ok "macOS SDK $sdk_version ($sdk_path)"
else
  fail "macOS SDK $sdk_version is older than $MIN_MACOS"
  fix "install Xcode 15.3+ or current Command Line Tools"
fi

if command -v codesign >/dev/null 2>&1; then ok "codesign (ad hoc signing of the .app)"
else fail "codesign not found"; fix "xcode-select --install"; fi

# XCTest: `swift test` imports it. The Command Line Tools may not include it; full Xcode does.
xctest=""
for candidate in "$dev_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" \
                 "$dev_dir/Library/Developer/Frameworks/XCTest.framework"; do
  [[ -d "$candidate" ]] && { xctest="$candidate"; break; }
done
if [[ -n "$xctest" ]]; then
  ok "XCTest ($xctest)"
elif [[ "$MODE" == test ]]; then
  fail "XCTest is not available in $dev_dir, so swift test fails with \"no such module 'XCTest'\""
  if [[ -n "$first_xcode" ]]; then
    fix "select Xcode for all tools:  sudo xcode-select --switch \"$first_xcode/Contents/Developer\""
    fix "or for one run only:         DEVELOPER_DIR=\"$first_xcode/Contents/Developer\" scripts/test.sh"
  else
    fix "install Xcode from the App Store, open it once, then:"
    fix "sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  fi
else
  info "XCTest not found in $dev_dir: packaging does not need it, but scripts/test.sh will (needs full Xcode)"
fi

if [[ $failures -eq 0 ]]; then echo "Ready."; exit 0; fi
echo "Not ready: $failures problem(s) above. Nothing was built and the developer-tool selection was not changed."
exit 1
