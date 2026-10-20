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
