#!/usr/bin/env bash
#
# Build ByeTunes (MusicManager) for physical iOS devices and export an unsigned IPA
# suitable for re-signing with Signulous, AltStore, or similar sideloading services.
#
# Usage:
#   ./scripts/build-signulous-ipa.sh
#   ./scripts/build-signulous-ipa.sh --clean
#   ./scripts/build-signulous-ipa.sh --skip-idevice
#
# Environment (optional):
#   IDEVICE_SRC_DIR     Path to idevice source (default: build/deps/idevice)
#   IDEVICE_DEPLOYMENT  iOS deployment target for idevice (default: 16.0)
#   DERIVED_DATA        Xcode DerivedData path (default: build/DerivedData)
#   OUTPUT_DIR          IPA output folder (default: dist)
#   SKIP_IDEVICE=1      Same as --skip-idevice
#   CLEAN=1             Same as --clean
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# --- config -------------------------------------------------------------------
PROJECT="MusicManager.xcodeproj"
SCHEME="MusicManager"
CONFIGURATION="Release"
DESTINATION="generic/platform=iOS"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
IDEVICE_SRC_DIR="${IDEVICE_SRC_DIR:-$ROOT_DIR/build/deps/idevice}"
IDEVICE_TARGET_DIR="${IDEVICE_TARGET_DIR:-$ROOT_DIR/build/deps/idevice-target}"
IDEVICE_DEPLOYMENT="${IDEVICE_DEPLOYMENT:-16.0}"
MM_DIR="$ROOT_DIR/MusicManager"
LIB_PATH="$MM_DIR/libidevice_ffi.a"
HEADER_PATH="$MM_DIR/idevice.h"
BRIDGE_PATH="$MM_DIR/Bridging-Header.h"

CLEAN=0
SKIP_IDEVICE=0

# --- logging ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { printf "${BLUE}==>${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$*"; }
die()  { printf "${RED}ERROR:${NC} %s\n" "$*" >&2; exit 1; }

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) CLEAN=1; shift ;;
    --skip-idevice) SKIP_IDEVICE=1; shift ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

[[ "${SKIP_IDEVICE:-0}" == "1" ]] && SKIP_IDEVICE=1
[[ "${CLEAN:-0}" == "1" ]] && CLEAN=1

# --- prerequisites ------------------------------------------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

check_prerequisites() {
  log "Checking prerequisites…"
  require_cmd xcodebuild
  require_cmd xcrun
  require_cmd git
  require_cmd lipo
  require_cmd file

  if ! xcodebuild -version >/dev/null 2>&1; then
    die "Xcode command-line tools are not configured. Run: xcode-select --install"
  fi

  local sdk
  sdk="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
  [[ -n "$sdk" ]] || die "iOS device SDK not found. Install Xcode and open it once."

  ok "Xcode $(xcodebuild -version | head -1)"
  ok "iOS SDK: $sdk"
}

ensure_rust() {
  if command -v cargo >/dev/null 2>&1 && command -v rustup >/dev/null 2>&1; then
    return 0
  fi
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
  fi
  command -v cargo >/dev/null 2>&1 || return 1
}

install_rust_hint() {
  cat >&2 <<'EOF'

Rust is required to build libidevice_ffi.a (not shipped in this repo).

Install Rust, then re-run this script:
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  source "$HOME/.cargo/env"
  rustup target add aarch64-apple-ios

Or place these files manually in MusicManager/ and use --skip-idevice:
  - libidevice_ffi.a
  - idevice.h
  - Bridging-Header.h  (contents: #import "idevice.h")

EOF
}

idevice_artifacts_present() {
  [[ -f "$LIB_PATH" && -f "$HEADER_PATH" && -f "$BRIDGE_PATH" ]]
}

ensure_bridging_header() {
  if [[ ! -f "$BRIDGE_PATH" ]]; then
    log "Creating Bridging-Header.h…"
    printf '%s\n' '#import "idevice.h"' >"$BRIDGE_PATH"
  fi
  if ! grep -q 'idevice.h' "$BRIDGE_PATH" 2>/dev/null; then
    die "Bridging-Header.h exists but does not import idevice.h"
  fi
}

build_idevice_ffi() {
  log "Building idevice FFI for iOS (this can take several minutes on first run)…"

  ensure_rust || { install_rust_hint; die "Rust toolchain not found"; }

  rustup target add aarch64-apple-ios >/dev/null 2>&1 || true

  if [[ ! -d "$IDEVICE_SRC_DIR/.git" ]]; then
    mkdir -p "$(dirname "$IDEVICE_SRC_DIR")"
    log "Cloning idevice into $IDEVICE_SRC_DIR"
    git clone --depth 1 https://github.com/jkcoxson/idevice "$IDEVICE_SRC_DIR"
  else
    log "Updating idevice source…"
    git -C "$IDEVICE_SRC_DIR" pull --ff-only || warn "Could not fast-forward idevice; using existing checkout"
  fi

  local ios_sdk
  ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"

  mkdir -p "$IDEVICE_TARGET_DIR"
  # Use a dedicated target dir (avoid Cursor/sandbox CARGO_TARGET_DIR overrides).
  (
    cd "$IDEVICE_SRC_DIR/ffi"
    export CARGO_TARGET_DIR="$IDEVICE_TARGET_DIR"
    export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=${ios_sdk}"
    export IPHONEOS_DEPLOYMENT_TARGET="$IDEVICE_DEPLOYMENT"
    cargo build --release --target aarch64-apple-ios
  )

  local built_lib="$IDEVICE_TARGET_DIR/aarch64-apple-ios/release/libidevice_ffi.a"
  local built_header="$IDEVICE_SRC_DIR/ffi/idevice.h"

  [[ -f "$built_lib" ]] || die "idevice build finished but library not found at $built_lib"
  [[ -f "$built_header" ]] || die "idevice header not found at $built_header (build may have failed during cbindgen)"

  log "Installing idevice artifacts into MusicManager/…"
  cp "$built_lib" "$LIB_PATH"
  cp "$built_header" "$HEADER_PATH"
  ensure_bridging_header

  local arch
  arch="$(lipo -info "$LIB_PATH" 2>/dev/null | sed -n 's/.*: //p' || file -b "$LIB_PATH")"
  ok "libidevice_ffi.a ($arch)"
}

ensure_idevice_artifacts() {
  if [[ "$SKIP_IDEVICE" == "1" ]]; then
    idevice_artifacts_present || die "--skip-idevice set but idevice files are missing in MusicManager/"
    ensure_bridging_header
    ok "Using existing idevice artifacts"
    return 0
  fi

  if idevice_artifacts_present; then
    ensure_bridging_header
    ok "idevice artifacts already present"
    return 0
  fi

  build_idevice_ffi
}

resolve_packages() {
  log "Resolving Swift Package Manager dependencies (FFmpegKit)…"
  xcodebuild \
    -resolvePackageDependencies \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA" \
    | grep -E 'Resolved|Checking out|error:' || true
  ok "Packages resolved"
}

build_app() {
  log "Building $SCHEME ($CONFIGURATION) for iOS device (unsigned)…"

  # Clear upstream author team; Signulous will apply its own signature.
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    build

  ok "Xcode build succeeded"
  embed_required_frameworks "$DERIVED_DATA/Build/Products/Release-iphoneos/MusicManager.app"
}

embed_required_frameworks() {
  local app_dir="$1"
  local binary="$app_dir/MusicManager"
  [[ -f "$binary" ]] || die "Cannot embed frameworks: binary missing at $binary"

  if ! otool -L "$binary" 2>/dev/null | grep -q 'FFmpeg-Kit.framework/FFmpeg-Kit'; then
    ok "Binary does not link FFmpeg-Kit.framework (skip embed check)"
    return 0
  fi

  local dest="$app_dir/Frameworks/FFmpeg-Kit.framework"
  if [[ -d "$dest" ]]; then
    ok "FFmpeg-Kit.framework already embedded"
    return 0
  fi

  local candidates=(
    "$DERIVED_DATA/Build/Products/Release-iphoneos/PackageFrameworks/FFmpeg-Kit.framework"
    "$DERIVED_DATA/Build/Products/Release-iphoneos/MusicManager.app/Frameworks/FFmpeg-Kit.framework"
  )
  local src=""
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      src="$candidate"
      break
    fi
  done

  [[ -n "$src" ]] || die "FFmpeg-Kit.framework is required at launch but was not found in build products. Re-run after fixing the Xcode Embed Frameworks phase."

  log "Embedding FFmpeg-Kit.framework into app bundle…"
  mkdir -p "$app_dir/Frameworks"
  cp -R "$src" "$dest"
  ok "Embedded FFmpeg-Kit.framework from $(basename "$(dirname "$src")")"
}

read_marketing_version() {
  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$DERIVED_DATA/Build/Products/Release-iphoneos/MusicManager.app/Info.plist" 2>/dev/null || true)"
  if [[ -z "$version" ]]; then
    version="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" 2>/dev/null \
      | awk -F' = ' '/MARKETING_VERSION/ {print $2; exit}')"
  fi
  echo "${version:-unknown}"
}

verify_app_bundle() {
  local app_dir="$1"
  [[ -d "$app_dir" ]] || die "App bundle not found: $app_dir"

  local binary="$app_dir/MusicManager"
  [[ -f "$binary" ]] || die "Main binary missing: $binary"

  local arch_info
  arch_info="$(file -b "$binary")"
  [[ "$arch_info" == *arm64* ]] || die "Expected arm64 device binary, got: $arch_info"

  if [[ ! -d "$app_dir/Frameworks" ]]; then
    die "No Frameworks/ folder in app bundle"
  fi

  local fw_count
  fw_count="$(find "$app_dir/Frameworks" -maxdepth 1 -name '*.framework' 2>/dev/null | wc -l | tr -d ' ')"
  ok "Embedded frameworks: $fw_count"

  if otool -L "$binary" 2>/dev/null | grep -q 'FFmpeg-Kit.framework/FFmpeg-Kit'; then
    [[ -f "$app_dir/Frameworks/FFmpeg-Kit.framework/FFmpeg-Kit" ]] \
      || die "Binary links FFmpeg-Kit.framework but it is missing from Frameworks/ (launch would crash)"
    ok "FFmpeg-Kit.framework present (required for launch)"
  fi

  for required in ffmpegkit libavcodec libavformat libavutil; do
    [[ -d "$app_dir/Frameworks/${required}.framework" ]] \
      || die "Missing ${required}.framework in app bundle"
  done
  ok "FFmpeg native frameworks present"

  ok "App bundle verified (arm64)"
}

package_ipa() {
  local app_dir="$DERIVED_DATA/Build/Products/Release-iphoneos/MusicManager.app"
  verify_app_bundle "$app_dir"

  local version ipa_name staging payload_dir
  version="$(read_marketing_version)"
  ipa_name="ByeTunes-${version}-unsigned.ipa"
  mkdir -p "$OUTPUT_DIR"

  staging="$(mktemp -d "${TMPDIR:-/tmp}/byetunes-ipa.XXXXXX")"
  payload_dir="$staging/Payload"
  mkdir -p "$payload_dir"

  log "Packaging IPA…"
  cp -R "$app_dir" "$payload_dir/"

  local ipa_path="$OUTPUT_DIR/$ipa_name"
  rm -f "$ipa_path"
  (
    cd "$staging"
    zip -qr "$ipa_path" Payload
  )
  rm -rf "$staging"

  [[ -f "$ipa_path" ]] || die "Failed to create IPA at $ipa_path"

  ok "IPA created: $ipa_path"
  echo ""
  echo "────────────────────────────────────────────────────────────"
  echo "  ByeTunes IPA ready for Signulous"
  echo "────────────────────────────────────────────────────────────"
  echo "  File:     $ipa_path"
  echo "  Version:  $version"
  echo "  Bundle:   com.EduAlexxis.MusicManager"
  echo "  Signing:  unsigned (for Signulous / sideload re-signing)"
  echo ""
  echo "  Next steps:"
  echo "    1. Register your device at https://www.signulous.com/register"
  echo "    2. Open https://www.signulous.com/sign-apps"
  echo "    3. Upload this IPA and install on your device"
  echo ""
  echo "  After install:"
  echo "    • Use LocalDevVPN when importing a pairing file (see README)"
  echo "    • Generate a pairing file with idevice_pair on your computer"
  echo "────────────────────────────────────────────────────────────"
}

maybe_clean() {
  if [[ "$CLEAN" == "1" ]]; then
    log "Cleaning build artifacts…"
    rm -rf "$DERIVED_DATA" "$OUTPUT_DIR"
    ok "Cleaned DerivedData and dist/"
  fi
}

main() {
  echo ""
  log "ByeTunes → Signulous IPA build"
  echo ""

  maybe_clean
  check_prerequisites
  ensure_idevice_artifacts
  resolve_packages
  build_app
  package_ipa
}

main "$@"
