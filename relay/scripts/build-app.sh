#!/usr/bin/env bash
# Kept for existing instructions: same as scripts/package.sh (builds build/Relay.app; no tests).
exec "$(dirname "$0")/package.sh" "$@"
