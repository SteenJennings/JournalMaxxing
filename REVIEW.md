# Dayline — deep review (2026-10-20)

Scope: all app code as merged on the diagnostics branch (baseline + Speech
Analyzer + Data tab + Diagnostics). Question asked: what compiles fine but
will fail or misbehave on a real phone, and what do we already know won't
work?

## Fixed in this pass
1. **Record-button race (crash).** Start is async (permissions + possible
   model download take seconds) but `isRecording` only flipped at the end.
   A second tap in that window started a competing analyzer and installed a
   second AVAudioEngine tap — installing two taps on one bus throws. Now:
   `isStarting` flag + a `startGeneration` counter; `stop()` during setup
   cleanly aborts the in-flight start at two checkpoints.
2. **Transcript reset ordering.** Text state reset *after* the engine
   started; an early result could be wiped. Resets now happen first.
3. **Photo loading hang.** If PhotoKit delivered a degraded preview and the
   full image then failed (iCloud hiccup), the continuation never resumed
   and the polish spinner hung forever. The loader now finishes on
   error/cancel callbacks too.

## Known limits — accepted, not bugs
- **Long dictation vs the polish model.** Foundation Models has a ~4k-token
  context (instructions + transcript + output). A multi-minute entry can
  overflow it; the call throws and polish falls back to local rules, i.e.
  your words come back basically unedited. Voice (logged in Diagnostics as
  "FoundationModels FAILED"). Fix path if it bites: chunked summarise.
- **Ranking is serial.** Up to 24 candidates × (image fetch + 3 Vision
  requests), one at a time. Local photos: a few seconds. iCloud-only
  originals: could be much slower. The Diagnostics log timestamps will show
  real numbers from the field test; parallelising + caching features per
  asset is the queued optimisation.
- **Stop loses the last partial phrase.** `stop()` cancels the results task;
  the on-screen transcript already contains the volatile text, so nothing
  visible is lost, but no finalised flush is awaited.
- **Manual edits vs re-record.** Today mirrors the live transcript into the
  text editor; typing edits, then recording again, starts the service
  transcript empty and overwrites the edits on the first new result.
- **Link previews refetch.** LPLinkView metadata is fetched on each
  scrapbook appearance (no cache). Minor data use; fine for now.
- **Audio-session interruptions.** A phone call mid-recording stalls the
  engine with no interruption observer; you'd see a frozen recording state.
  Add `AVAudioSession.interruptionNotification` handling if the field test
  makes this real.
- **Concurrency hygiene (Swift 5 mode).** The audio tap reads the converter
  off the audio thread; safe in practice (assigned before engine start,
  read-only while recording) but will need `@preconcurrency`/isolation care
  in a Swift 6 migration.
- **Diagnostics write cost.** One atomic file rewrite per log line (max 500
  lines). Fine at current volumes; throttle if photo ranking gets chatty.

## Known won't-work (platform gates, already decided)
- CloudKit sync of journal ENTRIES (the app's own data), widgets, share
  extension — need entitlements free provisioning doesn't grant (see
  STORAGE.md). Note the distinction: referencing photos that live in
  iCloud Photos is NOT gated — that's the free, already-working path.
- Background transcription — iOS won't keep the mic pipeline alive
  indefinitely in the background; journaling is a foreground activity.
- SpeechAnalyzer on the simulator has no real mic path — voice is a
  device-only test, by platform design.

## Verify on device (first field test, in TESTING.md order)
- Persistence: save an entry, force-quit, relaunch — entry must survive.
  (CI logs showed CoreData store warnings in the simulator *test host*;
  unproven either way on device. The Diagnostics "Save" lines + relaunch
  behaviour settle it.)
- First-run speech: model asset download prompt/flow and its timing.
- Video cells in the scrapbook actually autoplay muted under the default
  audio session.
- Photo ranking wall-clock time with a real (partly iCloud) library —
  read it off the Diagnostics timestamps.

## Pass 2 addendum (same day, views + logic)
Fixed:
- **Year grid was a dead end.** Tapping a past entry did nothing - there
  was no way to reopen a day's scrapbook. Cards now navigate to an
  EntryDetailView (full scrapbook resolved from stored identifiers).
- **Scrapbook cards after the first were half-empty** (an empty text
  column beside a small thumbnail). Later cards are now media-led,
  full-width.
- **Videos never moved.** Players were created but never played; the
  design's GIF-like behaviour is now real: muted autoplay + loop, pause
  when scrolled away.
- **Trends showed fake tags** with an empty journal (scaffold leftovers:
  work/trip/building/family). Now an honest "no tags yet" state.
- **Tagger substring traps:** "moment" tagged family ("mom"), "happy"
  tagged building ("app"), "trunk" tagged health ("run"). Those four now
  match on word boundaries; deliberate stems (ship, hik) still substring.
- **Speak button** now shows "Starting..." during the async start window
  (isStarting is published), matching the race guard from pass 1.
Noted, not fixed: LPMetadataProvider continuation can leak if its view is
dismissed mid-fetch (harmless, one-shot); per-cell loop observers suit the
current scrapbook sizes.

## Pass 3 — taste (2026-11-23, branch `taste-pass`)

Steen's critique: the design had become AI-slop homogeny — the same
warm-beige/rust/serif look every AI-assisted app ships. The pass
replaced decoration with a point of view (documented in DESIGN.md):
field journal, not lifestyle blog. Rust is now reserved for exactly
three jobs (mic, selected calendar day, favorite mark); surfaces are
separated by hairlines, not shadows; tags are words under a small-caps
label, never blue/purple pills; serif is dates/titles only.

Gaps closed in the same pass:
- **`isFavorite` was orphaned** (model field since the scaffold, no UI
  anywhere). It now has a star toggle in EntryDetail (persisted) and a
  rust star on Year cards.
- **Keyboard covered Polish + Save** (BACKLOG item 9): interactive
  keyboard dismissal plus a Done key above the keyboard.
- **Year grid had no structure** (undifferentiated adaptive grid):
  month-grouped sections with serif headers and day counts, via the
  pure, unit-tested `YearGrouping.group` (YearGroupingTests).
- **Trends was a default iOS `List`** — restyled into the design
  language (scroll sections, hairline rows, tabular counts, inline
  insight card); behavior unchanged.
- **Scrapbook media badges** were black pill overlays; now plain
  caption text. Link-preview fallback and placeholder rows lost their
  blue/yellow system colors for ink/rust.
- **DataView Form buttons** were system blue; now ink.

Deliberately not changed: the app icon (rust sun over ink horizon),
the peppered scrapbook layout, and the two-pool photo selection —
those were already opinionated. Not fixed here: manual edits
overwritten by re-recording, and long-dictation polish overflow —
both were fixed in Pass 4 below (BACKLOG items 1 and 4 closed).

## Pass 4 — swarm fixes (2026-11-23, branch `swarm-fixes`)

Five parallel read-only audit lanes (speech & polish, photos &
ranking, persistence & data, UI/UX & design, tests & CI) produced 9
P0s and ~30 P1/P2s. All P0s are fixed here; the P1/P2s are fixed
except the ones listed as deferred at the end.

### Data safety — the reason for the pass

- **Cross-day polish race (P0):** `polishAndSave()` read live state
  after the await, so tapping another day mid-polish saved Day A's
  text onto Day B and Day A was never saved. The day + text are now
  snapshotted up front and the save is scoped to the snapshot; the UI
  only updates if the day hasn't changed.
- **Deferred rollover never recovered (P0):** the old code consumed
  `lastKnownToday` on deferral, so a deferred rollover never fired
  again and the tab could show yesterday forever. It is not consumed
  now; a real dirty check (editor vs. loaded entry, or an open polish
  edit) decides, and a "You're still on yesterday" banner offers a
  way back.
- **Recording across a day change (P0):** a live recording bled onto
  the new day's page. Day changes now stop the recorder first.
- **Re-polish wiping saved photos (P0):** an empty photo fetch
  (limited access, a permission race) used to erase a day's saved
  media. Saves never shrink `mediaLocalIds` to empty unless the user
  removed items — in `saveEntry` and `persistPageEdits` both.
- **Media order not preserved (P0):** `fetchAssets(withLocalIdentifiers:)`
  does not guarantee order, so the scrapbook reshuffled on every
  relaunch. Results are re-sorted to the stored order.
- **Re-recording wiping manual edits (P0):** live results only mirror
  while the editor still shows what recording started with or what
  was last mirrored; typed words are appended on stop, never replaced.
- **No draft autosave (P0):** drafts persist per day (`DraftStore`),
  debounced while typing/dictating, restored on open, cleared on save.
  Day changes save the outgoing draft first instead of wiping it.
- **Backup (P1):** the export now carries `id`, `placeholders`,
  `createdAt`, `updatedAt`, and `schemaVersion`; the Data tab can
  import a JSON backup (matching on id, then day, so re-imports
  update instead of duplicating). The store is a versioned schema
  (v1) with a migration plan, and a store that fails to open is moved
  aside (never deleted) with a fresh store opened instead.
- **Placeholders — decided:** the feature stays unwired and the field
  stays in the model. Deleting a stored property is a model change and
  belongs in a V2 migration stage, not a drive-by edit. The export
  now carries placeholders so the data is at least round-tripped.
- **Duplicate day entries:** a launch-time dedupe pass collapses
  same-day rows into the newest, merging media ids.

### Speech & polish

- Polish + Save is disabled while recording (the old code saved a
  partial entry, then live results kept overwriting the editor).
- Audio-interruption + route-loss handling: a call, Siri, or a
  disconnected mic stops recording cleanly with a message instead of
  a frozen "Listening" state. The results stream dying does the same.
- `stop()` now finishes the input, finalizes the analyzer, and lets
  the results task drain before the 2s watchdog cancels it — the old
  order cancelled the consumer before finalizing, losing the last
  phrase.
- Model download has a 60s timeout and a "Downloading speech model…"
  status; polish has a 30s timeout and falls back to local rules.
- Parser: multi-line polished text is kept; a missing `POLISHED:`
  line returns nil (local-rules fallback) instead of writing the raw
  response — including literal `TAGS:`/`MOOD:` lines — into the entry.
  Tags are deduped and capped at 4; mood is one sanitized word.
- Tagger stems fixed: "ship" no longer tags "friendship" as work,
  "work" no longer tags "workout", "we ate." (end of sentence) now
  tags dinner. Regression tests lock all four in.
- Chunked polish (BACKLOG item 4): transcripts over ~8000 chars are
  polished in ~6000-char sentence-boundary chunks and stitched; a
  chunk that fails falls back to its own raw text plus keyword tags.
- A fallback polish no longer erases a saved mood on re-polish.

### Photos & ranking

- Ranking runs in parallel (4 at a time) with an in-memory feature
  cache per launch, and respects cancellation. The candidate pool is
  stride-sampled across the day instead of `prefix(24)` of a
  newest-first list, and videos are always included.
- `PhotoService` gained injectable analyzer + thumbnail seams, so
  `rankedSuggest` is unit-testable (the old single test asserted
  nothing).
- Library observation: a `PHPhotoLibraryChangeObserver` re-fetches
  the working day on change, and the pool re-fetches on foreground.
- Limited access is surfaced in the UI with the system picker to add
  more photos.
- Highlight preserved on re-polish; day-browser picks outside the
  pool are resolved instead of dropped; PhotosPicker picks merge into
  `mediaOverride` so they survive the next polish; the Browse button
  is always shown (the browser has its own empty state).
- Vision label threshold raised 0.05 → 0.2; a triple feature failure
  is logged instead of silent.
- Ranker: semantic credit is by distinct word matched, not label
  count; light stemming ("hike" ↔ "hiking", "dogs" → "dog"); the
  two-pool rule keeps a quality slot at small limits.
- Scrapbook: surplus media distributes between text chunks instead
  of dumping at the end; photo alignment parity runs on the photo
  index (a video no longer flips every photo after it); long
  two-sentence paragraphs split at word boundaries. Video loop
  observers are removed on disappear.

### UI / design

- DESIGN.md rule 1 now names the real rust system ("rust marks the
  thing that matters on the page") — the taste pass claimed three
  jobs while the code used six. Rule 2 names the text-over-photo
  legibility shadow as the one exception. Rust gained a text-safe
  shade (`accentText`) for kickers, the mood word, and the selected-
  day disc.
- DataView rebuilt as journal cards (no more default `Form`), with
  live transcription availability (the old row was hardcoded),
  library-access status, import flow, error labels, and a clear-log
  confirmation. Prepared export files are cleared when their source
  data changes, so Share never hands out a stale snapshot.
- Month calendar follows the selection across months, uses the
  locale's weekday order, and has VoiceOver labels. The mic is
  centered by layout, not a clear-spacer hack. The success label is
  ink, not green. Trends clears the old insight and shows a spinner
  while loading. Year cards show the mood word. EntryDetail shows
  "Last edited …" (the `updatedAt` field was stored and never shown).
- The keyboard Done key works in the polished-text editor too.

### Tests & CI

- CI asserts tests actually ran (a 0-test green run used to be
  indistinguishable from a real one), pins Xcode 26.6, dedupes
  failure issues by commit, and has a 30-minute timeout plus
  cancel-in-progress.
- `make test` / `make build` use the same simctl-UDID picker as CI
  (the name-based destination already failed on Steen's Mac) and
  depend on `gen`. `setup.sh` falls back to a pinned XcodeGen
  download (2.48.0) when Homebrew fails. `check-env.sh` fails when
  no iPhone simulator exists.
- Suite strengthened: DiagnosticsLog cap + persistence + clear
  tests, word-boundary tag regressions, parser edge cases, trend
  summary positive/boundary/plural, `allTags`, full-field export
  round-trip + import dedupe, PhotoRanker quality/clamp/stemming/
  distinct-word tests, select boundary tests, ScrapbookLayout
  distribution tests, DraftStore tests, a Vision smoke test.

### Deferred, not forgotten

- **Dynamic Type (P2-3):** fixed font sizes still ignore the
  system's text size. Needs a typography-scale pass, not a
  one-off fix.
- **Manual photo reorder + manual cover pick (BACKLOG item 6):**
  still open; the pass only stopped the algorithm clobbering the
  cover and preserved saved order.
- **Entry deletion UI:** none exists anywhere; no design decision
  yet on where it lives.
- **Test for the versioned-schema migration:** CI builds but never
  opens an existing store, so a migration failure would only show
  on a real device. The move-aside fallback exists for exactly
  that case, and Steen's simulator data is the only store at risk.
