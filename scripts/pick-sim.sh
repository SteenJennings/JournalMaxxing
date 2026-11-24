#!/bin/bash
# Prints the UDID of the first available iPhone simulator. Shared by the
# Makefile and the CI workflow (which inlines the same logic): a
# name-based destination is brittle — one runner had no matching
# simulator at all, and Steen's Mac has several sims sharing one name.
set -e
xcrun simctl list devices available --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' not in runtime:
        continue
    for d in devices:
        if d.get('isAvailable') and 'iPhone' in d.get('name', ''):
            print(d['udid']); sys.exit(0)
sys.exit(1)
"
