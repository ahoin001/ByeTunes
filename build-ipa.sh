#!/usr/bin/env bash
# Convenience wrapper — run from repo root:
#   ./build-ipa.sh
exec "$(cd "$(dirname "$0")" && pwd)/scripts/build-signulous-ipa.sh" "$@"
