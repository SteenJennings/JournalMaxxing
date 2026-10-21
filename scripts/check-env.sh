#!/bin/bash
# Verifies this Mac can build and test Dayline. Prints PASS/FAIL per item.
# Exit code 0 = ready (warnings allowed), 1 = hard blocker.
fail=0
say() { printf "%-34s %s\n" "$1" "$2"; }

if [[ "$(uname)" != "Darwin" ]]; then
  echo "FAIL: not macOS - Xcode requires a Mac."; exit 1
fi
say "macOS" "$(sw_vers -productVersion)"

if xcodebuild -version &>/dev/null; then
  say "Xcode" "$(xcodebuild -version | head -1)"
  xver=$(xcodebuild -version | head -1 | grep -oE '[0-9]+' | head -1)
  if [[ "$xver" -lt 26 ]]; then
    echo "  -> FAIL: Dayline targets the iOS 26 SDK (Foundation Models, current Speech)."
    echo "     Install Xcode 26 from the App Store, then: sudo xcode-select -s /Applications/Xcode.app"
    fail=1
  fi
else
  echo "FAIL: xcodebuild not found. Install Xcode from the App Store."
  fail=1
fi

# Dayline needs iOS SDK 26 OR NEWER (a newer Xcode ships a newer SDK - fine).
sdk_major=$(xcodebuild -showsdks 2>/dev/null | grep -oE 'iphoneos[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
if [[ -n "$sdk_major" && "$sdk_major" -ge 26 ]]; then
  say "iOS SDK" "$sdk_major (26+ required) - present"
else
  say "iOS SDK" "MISSING or older than 26 (install Xcode 26+)"; fail=1
fi

if command -v xcodegen &>/dev/null; then say "XcodeGen" "$(xcodegen --version)"; else say "XcodeGen" "not installed (setup.sh installs it)"; fi
if command -v git &>/dev/null; then say "git" "$(git --version | cut -d' ' -f3)"; else say "git" "missing"; fail=1; fi
if command -v gh &>/dev/null; then say "GitHub CLI" "present (optional)"; else say "GitHub CLI" "not installed (optional, for repo creation)"; fi

echo "iPhone simulators available:"
xcrun simctl list devices available 2>/dev/null | grep -i "iphone 1[67]" | head -6 | sed 's/^/  /'

if [[ "$fail" -eq 0 ]]; then echo; echo "READY: run ./scripts/setup.sh, then make test"; else echo; echo "NOT READY: fix the FAIL items above."; fi
exit $fail
