# Dayline Backlog — core-app improvements

Status: **proposed** (Steen, 2026-10-21 — "lets revisit this soon",
2026-11-23). None of these is started. The Discover/Memory Lane design
lives separately in `DISCOVERY.md`; this file is the core app — capture,
trust, and the reading experience. Ordered by value; revisit and re-rank
with field-test evidence before building anything.

## P0 — Protect the words

### 1. Draft autosave + recording-interruption handling
An unsaved dictation currently lives in memory only. If the app is
killed, or a phone call interrupts recording (accepted limit: no
`AVAudioSession` interruption handling), words can be lost. Autosave the
in-progress draft to disk as you speak; restore it on launch; pause and
resume cleanly around interruptions. A journal app that loses an entry
once loses trust forever.

### 2. Backup nudge
Everything is local by design and export is manual today (Data tab).
Add a quiet "no backup in 30 days" badge on the Data tab so a lost phone
never means a lost journal. No cloud, no account — just a reminder to
export.

## P1 — Capture the way a day actually happens

### 3. Journal in moments (timestamped segments on one day page)
One page per day stays right, but capture shouldn't require one nightly
sitting. Dictate at 10am, again at lunch, again at night — each appends
as a timestamped segment to the same day page, polished together or per
segment.

### 4. Chunked polish for long dictation
Talk for five minutes and the Foundation Models ~4k-token context
ceiling overflows; polish falls back to near-raw text (accepted limit).
Polish in passes over chunks and stitch the results.

### 5. Quick capture
Lock-screen / Home Screen widget or Action Button shortcut that starts
recording immediately. The "one-second journal" idea lives or dies on
how fast you can start talking. (Widgets/share extension were parked in
Phase 2 — re-check free-provisioning signing for the extension when
scoping this.)

## P2 — Make the page yours

### 6. Reorder photos + pick your own highlight
Media selection is hand-pickable today (day browser), but order is
algorithmic and the highlight/cover is the algorithm's pick. Let Steen
reorder and set the cover per day.

### 7. Live Photo motion
Live Photos show a badge only today. Playing the motion in the
scrapbook (and later in Stories) is the single biggest "this feels
alive" upgrade for the least design risk.

### 8. Live preview while composing
The scrapbook preview appears after Polish + Save; ranked picks could
shape up live as you write, so you're composing the page rather than
approving it after the fact.

## Pre-field-test fix (done in the taste pass, 2026-11-23)

### 9. Keyboard covering Polish + Save — DONE
While editing, the keyboard could cover the Polish + Save buttons.
Fixed with interactive keyboard dismissal plus a Done key above the
keyboard (TodayView, taste-pass branch).

## Deliberately NOT on this list

- Streaks / coaching / guilt mechanics. The perfect-day program is
  paused by Steen's choice and the journal is not a habit app.
- Cloud sync / iCloud / widgets that need paid entitlements — the $0,
  local, no-$99-Developer-Program constraints still stand.
