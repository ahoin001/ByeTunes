#!/usr/bin/env bash
#
# Install local prerequisites for building ByeTunes IPAs on macOS.
# Safe to run multiple times (idempotent).
#
# Usage: ./scripts/setup-build-env.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { printf "${BLUE}==>${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$*"; }
die()  { printf "${RED}ERROR:${NC} %s\n" "$*" >&2; exit 1; }

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This script must run on macOS with Xcode."
}

ensure_xcode() {
  log "Checking Xcode…"
  command -v xcodebuild >/dev/null 2>&1 || die "Install Xcode from the App Store, then run: xcode-select -s /Applications/Xcode.app/Contents/Developer"
  if ! xcodebuild -version >/dev/null 2>&1; then
    die "xcodebuild failed. Open Xcode once to finish setup."
  fi
  if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    die "iOS device SDK not found. Install Xcode and open it once."
  fi
  ok "$(xcodebuild -version | head -1)"
  ok "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-path)"
}

ensure_git() {
  log "Checking git…"
  command -v git >/dev/null 2>&1 || die "git is required"
  ok "git $(git --version | awk '{print $3}')"
}

ensure_rust() {
  log "Checking Rust (needed only to rebuild libidevice_ffi.a)…"
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
  fi

  if ! command -v rustup >/dev/null 2>&1; then
    log "Installing Rust via rustup…"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
  fi

  rustup default stable >/dev/null 2>&1 || true
  rustup target add aarch64-apple-ios >/dev/null 2>&1 || true
  ok "Rust $(rustc --version | awk '{print $2}') with aarch64-apple-ios target"
}

ensure_idevice_artifacts() {
  log "Checking idevice artifacts in MusicManager/…"
  local lib="$ROOT_DIR/MusicManager/libidevice_ffi.a"
  local hdr="$ROOT_DIR/MusicManager/idevice.h"
  local bridge="$ROOT_DIR/MusicManager/Bridging-Header.h"

  if [[ -f "$lib" && -f "$hdr" ]]; then
    ok "idevice library and header present"
  else
    warn "idevice files missing — run ./build-ipa.sh (will build them) or ./scripts/build-signulous-ipa.sh"
  fi

  if [[ ! -f "$bridge" ]]; then
    printf '%s\n' '#import "idevice.h"' >"$bridge"
    ok "Created Bridging-Header.h"
  else
    ok "Bridging-Header.h present"
  fi
}

resolve_spm() {
  log "Resolving Swift packages (FFmpegKit)…"
  xcodebuild \
    -resolvePackageDependencies \
    -project MusicManager.xcodeproj \
    -scheme MusicManager \
    -derivedDataPath "$ROOT_DIR/build/DerivedData" \
    >/dev/null
  ok "Swift packages resolved"
}

main() {
  echo ""
  log "ByeTunes build environment setup"
  echo ""
  require_macos
  ensure_xcode
  ensure_git
  ensure_rust
  ensure_idevice_artifacts
  resolve_spm
  echo ""
  ok "Environment ready. Build an IPA with: ./build-ipa.sh"
  echo ""
}

main "$@"
