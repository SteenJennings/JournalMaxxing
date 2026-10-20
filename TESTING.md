# Dayline — Testing Guide (Mac + Xcode)

Everything up to opening Xcode is already done: project config, permissions
strings, persistence, local AI backends, real photo rendering, tests, CI.
This guide is the exact path from a fresh copy of this repo to (a) green
tests in the simulator and (b) the app running on your iPhone — with **no**
Apple Developer Program membership.

## 0. Prerequisites
- A Mac (Apple silicon ideal) with **Xcode 26** from the App Store
- Your iPhone (17 Pro Max) on **iOS 26**, Apple Intelligence enabled in
  Settings (needed for the Foundation Models polish path; without it the app
  still works, polish falls back to local rules and says so under the entry)
- A USB-C cable for the first device install (Wi-Fi installs after that)
- ~15 minutes the first time

## 1. Verify the machine (2 minutes)
```bash
cd Dayline
./scripts/check-env.sh
```
Expect `READY`. It checks macOS, Xcode ≥ 26, the iOS 26 SDK, XcodeGen, git,
and lists available iPhone simulators. Fix only what it marks FAIL.

## 2. Generate the project
```bash
./scripts/setup.sh        # installs XcodeGen via Homebrew if missing, runs xcodegen
# or, if XcodeGen is already installed:
make gen
```
This creates `Dayline.xcodeproj` from `project.yml`. The generated project is
git-ignored on purpose — regenerate it whenever `project.yml` changes.

## 3. Simulator test (the daily dev loop)
```bash
make test
```
This builds the app and runs all unit tests on an iPhone 17 Pro simulator,
unsigned. If your simulator has a different name, run `make sims` and pass
`SIM="iPhone 17 Pro Max"` (or whatever you have).

Then run it visually:
```bash
open Dayline.xcodeproj    # pick the simulator in Xcode's toolbar, Cmd+R
```
Smoke checklist in the simulator:
- [ ] Today tab loads, date header shows
- [ ] Type an entry mentioning dinner/pool/family → **Polish + Save**
- [ ] "Saved to your journal" appears; note the line under it —
      in the simulator Foundation Models may be unavailable, so expect
      "Polished with: Local rules (fallback)" (on your phone it should say
      FoundationModels). Both are correct behaviour, not an error.
- [ ] Tags chips appear; switch to **Year** — today's card is there
      (in the original scaffold this was always empty: nothing was saved)
- [ ] **Trends** lists tags from your entries, not a fixed list
- [ ] Seed photos: drag a few images into the simulator window (they land in
      its Photos library), restart the app, polish again — the scrapbook
      should show real thumbnails. Simulator photo behaviour is approximate;
      the phone is the source of truth.

Debug signals in the simulator: Xcode console (filter `Summarizer` — the app
logs which polish backend ran and why the fallback engaged), breakpoints in
`TodayView.polishAndSave()`, and View Debugger for layout.

## 4. On your iPhone — free provisioning (the real test)
No paid account anywhere in these steps.

1. Plug the iPhone into the Mac. Unlock it, tap Trust if asked.
2. In Xcode: **Settings → Accounts → + → Apple ID** — sign in with your
   normal Apple ID. This creates your free **Personal Team**.
3. Select the **Dayline** target → **Signing & Capabilities** →
   check "Automatically manage signing" → **Team = (your name) Personal Team**.
   The bundle ID is already set to `com.steenjennings.dayline`; if Xcode says
   it's unavailable, append something unique (e.g. `.steen`) in
   `project.yml`, re-run `make gen`, and tell me — search/replace is one line.
4. Pick your iPhone in the run-destination menu (if it's not listed:
   Xcode → Window → Devices and Simulators → check "Connect via network"
   after the first USB connection for future Wi-Fi runs).
5. **Cmd+R.** First launch on the phone may require:
   **Settings → General → VPN & Device Management → trust your Apple ID.**
6. In the app, grant, in order: **Microphone**, **Speech Recognition**,
   **Photos** (Full Access gives the best suggestions; Limited works too —
   the app only ranks what it can see).

Device smoke checklist:
- [ ] Tap **Speak**, talk for ~20 seconds ("...so fun at the pool today,
      dinner with Malia after..."), tap Stop — text appears, transcribed
      on-device
- [ ] **Polish + Save** — the backend line should read
      "Polished with: FoundationModels (on-device)"
- [ ] Scrapbook shows *today's actual photos*, ranked — pool/water shots
      should outrank screenshots. Videos show a play badge + duration and
      play inline (muted). Live Photos show a Live badge (full Live Photo
      playback is a known next step, not in v1)
- [ ] Kill and relaunch the app — the entry is still there (SwiftData)
- [ ] Year tab card shows your real highlight photo as its thumbnail

## 5. The 7-day rule (read once)
Free-provisioned installs stop launching after **7 days**. Nothing is lost:
your entries live in the app's data container, not in the signing.
Re-run from Xcode (Cmd+R, USB or Wi-Fi) and the same app with the same data
launches again. If Dayline becomes a daily habit, set up AltStore/SideStore
once — it refreshes the signing automatically over Wi-Fi. The moment you
want TestFlight, widgets, or iCloud sync, that's what the $99 program buys;
nothing in the app needs to change to upgrade.

## 6. GitHub (optional, 3 minutes)
```bash
gh repo create dayline --private --source . --push    # with GitHub CLI
# or: create an empty private repo on github.com, then
git remote add origin git@github.com:<you>/dayline.git && git push -u origin main
```
Every push runs `.github/workflows/build.yml`: a Mac runner generates the
project and runs the full simulator test suite, unsigned. Green check = the
commit builds and tests clean on a machine that isn't yours.

## 7. When something is red — send me this
Paste any of these into the chat and I'll fix from the exact error:
- `make test` terminal output (the first `error:` lines are enough)
- The Xcode issue navigator text for a build failure
- For device-signing problems: the exact Signing & Capabilities message
Known first-run suspects, in order: (1) Xcode < 26, (2) simulator name
differs from `iPhone 17 Pro` — use `make sims` + `SIM=`, (3) bundle ID
collision on your Personal Team — see step 4.3, (4) Photos permission set to
Limited/none, which makes suggestions empty by design.

## What is intentionally NOT in this build yet
- MobileCLIP open-vocabulary embeddings + cached photo index (Phase 2 —
  ranking today is Vision labels + aesthetics + faces)
- SpeechAnalyzer engine (v1 uses the stable Speech framework on-device;
  the transcriber is one class, built to be swapped)
- Live Photo motion playback in the scrapbook (badge only in v1)
- Widgets, share extension, iCloud sync (all blocked by free provisioning,
  none block the core loop)
