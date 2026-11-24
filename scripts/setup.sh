#!/bin/bash
# Dayline first-time setup on a Mac. Safe to re-run.
set -e
cd "$(dirname "$0")/.."

if [[ "$(uname)" != "Darwin" ]]; then
  echo "ERROR: Dayline builds on a Mac with Xcode. This machine is not macOS."
  exit 1
fi

./scripts/check-env.sh || true
echo

install_xcodegen_direct() {
  # No Homebrew (or Homebrew failed)? Grab a pinned release binary from
  # GitHub instead. Pinned to a known-good version: the old code took
  # whatever `releases/latest` returned, unverified, and parsed the API
  # JSON with grep.
  local version="2.48.0"
  local url="https://github.com/yonaskolb/XcodeGen/releases/download/${version}/xcodegen.zip"
  echo "Installing XcodeGen ${version} from the official GitHub release..."
  local tmp
  tmp=$(mktemp -d)
  if ! curl -fsSL --retry 3 "$url" -o "$tmp/xcodegen.zip"; then
    echo "ERROR: could not download XcodeGen ${version}."
    echo "Fallback: install Homebrew from https://brew.sh, then re-run this script."
    exit 1
  fi
  unzip -q "$tmp/xcodegen.zip" -d "$tmp/unzipped"
  local bin
  bin=$(find "$tmp/unzipped" -name xcodegen -type f | head -1)
  if [[ -z "$bin" ]]; then
    echo "ERROR: XcodeGen binary not found inside the release zip."
    exit 1
  fi
  mkdir -p "$HOME/.local/bin"
  cp "$bin" "$HOME/.local/bin/xcodegen"
  chmod +x "$HOME/.local/bin/xcodegen"
  export PATH="$HOME/.local/bin:$PATH"
  echo "Installed to ~/.local/bin/xcodegen (add ~/.local/bin to your PATH for other shells)."
}

if ! command -v xcodegen &>/dev/null; then
  if command -v brew &>/dev/null; then
    echo "Installing XcodeGen via Homebrew..."
    # A failed brew install used to kill the script (set -e) instead of
    # trying the direct-download path that exists for this case.
    brew install xcodegen || install_xcodegen_direct
  else
    install_xcodegen_direct
  fi
fi

echo "Generating Xcode project..."
xcodegen generate

echo
echo "Done. Next steps (full detail in TESTING.md):"
echo "  1. open Dayline.xcodeproj"
echo "  2. Select the Dayline target > Signing & Capabilities > Team = your Personal Team"
echo "  3. make test        # simulator build + unit tests"
echo "  4. Pick your iPhone as run destination, Cmd+R   # real device test"
