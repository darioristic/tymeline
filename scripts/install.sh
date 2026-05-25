#!/usr/bin/env bash
# Build tymeline from source and install into /Applications.
#
# Requirements:
#   - macOS 14+
#   - Xcode 16+ (full IDE, not just Command Line Tools)
#   - XcodeGen (installed automatically via brew if missing)
#
# Usage:
#   ./scripts/install.sh
#
# To skip launching after install: NO_OPEN=1 ./scripts/install.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
red()  { printf "\033[31m%s\033[0m\n" "$*" >&2; }

# Sanity checks
if [[ "$(uname -s)" != "Darwin" ]]; then
  red "tymeline is macOS-only. Detected: $(uname -s)"
  exit 1
fi

if ! xcode-select -p &>/dev/null; then
  red "Xcode is not selected. Install Xcode from the App Store and run:"
  red "  sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

if ! command -v xcodegen &>/dev/null; then
  bold "Installing XcodeGen via Homebrew..."
  if ! command -v brew &>/dev/null; then
    red "Homebrew not found. Install it from https://brew.sh first."
    exit 1
  fi
  brew install xcodegen
fi

# Generate project from project.yml
bold "Generating Xcode project..."
xcodegen generate >/dev/null

# Build Release configuration with ad-hoc signing
bold "Building tymeline (Release config)..."
build_dir="$repo_root/.build-release"
log_file="/tmp/tymeline-build.log"
rm -rf "$build_dir"

if ! xcodebuild \
      -project tymeline.xcodeproj \
      -scheme tymeline \
      -configuration Release \
      -destination 'platform=macOS' \
      -derivedDataPath "$build_dir" \
      CODE_SIGN_IDENTITY=- \
      CODE_SIGN_STYLE=Manual \
      build \
      >"$log_file" 2>&1; then
  red "Build failed. Full log: $log_file"
  tail -40 "$log_file" >&2
  exit 1
fi

# Copy into /Applications
app_src="$build_dir/Build/Products/Release/tymeline.app"
app_dst="/Applications/tymeline.app"

if [[ ! -d "$app_src" ]]; then
  red "Built app not found at $app_src"
  exit 1
fi

# Re-sign embedded frameworks (Sparkle) ad-hoc so they match the app's
# Team ID. Without this, dyld refuses to load Sparkle.framework and the
# app crashes immediately on launch.
bold "Re-signing bundle ad-hoc (matches Sparkle.framework to the app)..."
codesign --force --deep --sign - "$app_src" >/dev/null 2>&1 || {
  red "ad-hoc resign failed"
  exit 1
}

bold "Installing to $app_dst..."
if [[ -d "$app_dst" ]]; then
  # If the app is currently running, stop it first so the bundle can be replaced
  if pgrep -f "$app_dst/Contents/MacOS/tymeline" >/dev/null; then
    bold "Stopping running tymeline instance..."
    pkill -f "$app_dst/Contents/MacOS/tymeline" || true
    sleep 1
  fi
  rm -rf "$app_dst"
fi
cp -R "$app_src" "$app_dst"

# Strip quarantine so Gatekeeper doesn't show the 'unidentified developer'
# prompt on first launch. Ad-hoc signing is enough for local builds.
xattr -dr com.apple.quarantine "$app_dst" 2>/dev/null || true

bold "Done."
echo
echo "tymeline is installed at $app_dst"
echo "It will appear in your menubar after first launch."

if [[ "${NO_OPEN:-0}" == "0" ]]; then
  open "$app_dst"
fi
