# Appetize — the visual iteration loop for Dayline

The question it answers: *can LeBron see the app and iterate on the
design without Steen in the loop?* Yes — Appetize runs our simulator
build on a cloud iPhone that the agent drives through a CLI: open the
app, screenshot each tab, check the shots against `DESIGN.md`, change
the code, repeat. One pass is ~1–2 minutes of Appetize time.

## Cost (verified Nov 24, 2026, from Appetize's own pricing)

- **Free: $0** — 1 user, 2 devices, **30 minutes refilled monthly**,
  sessions capped at **3 minutes** each. A design check (open, shoot
  4 tabs, close) fits comfortably in one session, so the free tier
  covers roughly 15–20 passes a month.
- Starter: $59/mo, 500 minutes, then $0.06/min. Only needed if the
  free allowance runs out — which would mean we're iterating a lot,
  and at that point the $0 rule for this app is the thing to revisit,
  not the tool.

## What it can and cannot do

- **Can:** real app, real SwiftUI pixels, interactive — tap tabs,
  scroll, open the day browser, inspect the view hierarchy, read
  device logs. Screenshots after every step.
- **Cannot:** it's a simulator, not Steen's phone. No speech
  transcription (no downloadable speech model on a cloud sim), no
  real photo library, no Apple Intelligence polish check beyond what
  the sim already does. Field testing on the device is still the
  only way to validate speech and ranking against a real library.
- **Media seeding (partial fix for the empty library):**
  `appetize media add <photo>` drops a PNG/JPEG/MP4 into the
  device gallery. The test photos in `~/workspace/dayline-test-photos.zip`
  (park/brunch/sunset/dog, EXIF-dated 2026-10-20) can seed a pass so
  the scrapbook and two-pool picks have something to show — open
  Oct 20 in the calendar to see them, since they're dated then, not
  today.

## Setup (one time, Steen's side)

1. Create a free account at https://appetize.io (Free plan).
2. Create an API token in organization settings
   (docs: `account/api-tokens`). Hand it to LeBron through the
   Secure Vault flow — never in chat. It lives as `APPETIZE_API_TOKEN`.
3. Get the first build up there, one of:
   - **Dashboard (simplest):** build the simulator .app
     (`xcodebuild -scheme Dayline -sdk iphonesimulator`, or Product
     → Show Build Folder in Xcode → `Products/Debug-iphonesimulator/Dayline.app`),
     `zip -r Dayline.zip Dayline.app`, drag it into the Appetize
     dashboard. Note the build id it prints.
   - **CLI:** `appetize build upload Dayline.zip` (needs the token).
   - **CI:** a guarded step in `.github/workflows/build.yml` uploads
     each green main build (zipped simulator .app, `--wait` for the
     build id). The step is skipped while `APPETIZE_API_TOKEN` is
     absent, so CI stays green without it. Steen adds the secret in
     repo Settings → Secrets → Actions, once.
4. iOS uploads must be **simulator .app bundles, zipped** — `.ipa`
   files are not supported. ARM simulator builds preferred.

## The loop

```bash
# No export needed on this VM: the script uses the vault-backed wrapper
# (~/workspace/custom-connectors/custom.appetize/bin/appetize-cli.py),
# which mints the token from the stored credential.
./scripts/appetize-design-check.sh app_a1b2c3
# → ~/workspace/dayline/appetize-shots/<stamp>/{today,year,trends,data}.png
```

What the script does, per the CLI's own agent guide
(`appetize skill get`):

1. `appetize session start iphone17promax --target <build-id> --device-os-version 26.0`
   — the device matches Steen's phone (iPhone 17 Pro Max) and our
   iOS 26.0 deployment target. Blocks until the device is ready.
2. `appetize inspect --select-text 'Today' --timeout 15000` — waits
   for the app instead of sleeping.
3. `appetize screenshot today --settle`, then taps each tab
   (`Year`, `Trends`, `Data`) by its label, inspects for the label,
   screenshots it. A tap "succeeding" only means the gesture was
   delivered — the inspect + screenshot is what proves the screen
   actually changed.
4. `appetize session stop` — always, via a trap, so the device is
   released and the minutes stop.

## Checking a pass against the design standard

Read the four shots against `DESIGN.md` ("field journal, not
lifestyle blog"): rust only on the thing that matters on the page
(mic, selected day, favorite, mood word, kicker, margin tick — never
two jobs in one view); hairlines, not shadows; tags as words under a
small-caps label; serif only for dates/titles; photos as prints with
plain caption text; `accentText` (the darker rust) for small rust
text. Screenshots are never committed to the repo.

## Tooling

- CLI: `@appetize/cli` 0.33.1, installed at
  `~/workspace/tools/appetize` (Node 22+ required; VM has Node
  24.22.1). `appetize --version` to confirm.
- Agent guide: `appetize skill get` (also `appetize <command> --help`).
- Session minutes are metered — always stop the session, and prefer
  one pass per design question over leaving a session idling.
