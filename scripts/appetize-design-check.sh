#!/bin/bash
# Appetize design check for Dayline (see APPETIZE.md).
#
# Opens the app on a cloud iPhone, screenshots each tab, stops the
# session. One pass is ~1-2 minutes of Appetize time: the free tier
# (30 min/month, 3-minute sessions) covers roughly 15-20 passes.
#
# Usage: ./scripts/appetize-design-check.sh <build-id> [device] [os-version]
#   build-id: Appetize build id, e.g. app_a1b2c3 — from
#             `appetize build list` or the id printed by
#             `appetize build upload dayline.zip`
#   device:   default iphone17promax (Steen's phone)
#   os:       default 26.0 (our deployment target)
#
# Requires APPETIZE_API_TOKEN exported (token from Appetize org
# settings — never commit it, never paste it in chat; it lives in
# the Secure Vault), OR the vault-backed wrapper below. The CLI lives
# at ~/workspace/tools/appetize (npm install @appetize/cli, Node 22+);
# `appetize` on PATH works too.
#
# Screenshots land in ~/workspace/dayline/appetize-shots/<stamp>/ and
# are NEVER committed to the repo.
set -euo pipefail

BUILD_ID="${1:-}"
DEVICE="${2:-iphone17promax}"
OS_VERSION="${3:-26.0}"

if [ -z "$BUILD_ID" ]; then
    echo "usage: $0 <build-id> [device] [os-version]" >&2
    exit 1
fi

# Auth: prefer the vault-backed wrapper (it mints a short-lived surrogate
# from the stored credential) when no token is exported; otherwise use the
# CLI directly with the exported token.
WRAPPER="$HOME/workspace/custom-connectors/custom.appetize/bin/appetize-cli.py"
if [ -z "${APPETIZE_API_TOKEN:-}" ] && [ -x "$WRAPPER" ]; then
    APPETIZE="$WRAPPER"
elif command -v appetize >/dev/null 2>&1; then
    APPETIZE="appetize"
elif [ -x "$HOME/workspace/tools/appetize/node_modules/.bin/appetize" ]; then
    APPETIZE="$HOME/workspace/tools/appetize/node_modules/.bin/appetize"
elif [ -x "$WRAPPER" ]; then
    APPETIZE="$WRAPPER"
else
    echo "appetize CLI not found and no API token set — see APPETIZE.md." >&2
    exit 1
fi

STAMP="$(date +%Y-%m-%d-%H%M)"
OUT="$HOME/workspace/dayline/appetize-shots/$STAMP"
mkdir -p "$OUT"
cd "$OUT"

SESSION_ID=""
stop_session() {
    if [ -n "$SESSION_ID" ]; then
        "$APPETIZE" session stop --session-id "$SESSION_ID" --json --quiet >/dev/null 2>&1 || true
    fi
}
trap stop_session EXIT

echo "Starting session on $DEVICE (iOS $OS_VERSION), build $BUILD_ID…"
START_JSON="$("$APPETIZE" session start "$DEVICE" --target "$BUILD_ID" --device-os-version "$OS_VERSION" --json --quiet)"
SESSION_ID="$(echo "$START_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sessionId"])')"
echo "Session $SESSION_ID — screenshots go to $OUT"

# Fresh Appetize devices show the Photos permission dialog on first
# launch, covering the Today tab (which is why the first inspect for
# 'Today' found nothing). Grant full access so the scrapbook has the
# device's photos to rank; the dialog is absent on a re-run only if the
# device persisted the grant, so this stays conditional.
if "$APPETIZE" inspect --select-text 'Allow Full Access' --timeout 8000 --json --quiet >/dev/null 2>&1; then
    "$APPETIZE" tap --select-text 'Allow Full Access' --json --quiet >/dev/null
    echo "granted photo access"
fi

# Wait for the app to land on Today, then shoot each tab. A tap that
# "succeeds" only means the gesture was delivered, so every shot is
# preceded by an inspect that waits for the tab's label to be present.
"$APPETIZE" inspect --select-text 'Today' --timeout 15000 --json --quiet >/dev/null
"$APPETIZE" screenshot today --settle --json --quiet >/dev/null
echo "shot: today"

for TAB in Year Trends Data; do
    "$APPETIZE" tap --select-text "$TAB" --json --quiet >/dev/null
    "$APPETIZE" inspect --select-text "$TAB" --timeout 5000 --json --quiet >/dev/null
    "$APPETIZE" screenshot "$(echo "$TAB" | tr 'A-Z' 'a-z')" --settle --json --quiet >/dev/null
    echo "shot: $TAB"
done

echo "Done. Shots in $OUT (today/year/trends/data)."
ls -1 "$OUT"
