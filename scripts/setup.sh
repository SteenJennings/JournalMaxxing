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

if ! command -v xcodegen &>/dev/null; then
  if command -v brew &>/dev/null; then
    echo "Installing XcodeGen via Homebrew..."
    brew install xcodegen
  else
    echo "ERROR: XcodeGen not found and Homebrew is not installed."
    echo "Install Homebrew from https://brew.sh, then re-run this script."
    exit 1
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
