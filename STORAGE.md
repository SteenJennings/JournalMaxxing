# Dayline — Storage, Logging, and the iCloud question

## Where does everything live right now?

| Thing | Where | Details |
|---|---|---|
| Journal entries (text, tags, mood, links, photo IDs) | **On the phone, in the app's sandbox** | SwiftData store (SQLite under the hood), created by `.modelContainer(for: [DayEntry.self])` in `DaylineApp.swift`. No server copy exists. |
| Photos & videos | **Your Photos library** — never copied into the app | Entries store only each asset's `localIdentifier`. Rendering resolves it through PhotoKit at display time. |
| Audio | Not stored | Transcription is live; when you stop, the audio is gone and only text remains. (Saving audio for re-transcription is a possible future setting.) |
| Runtime logs | **Apple's unified log on the device** | `Logger` with subsystem `com.steenjennings.dayline`. Visible live in Xcode's console during a run from the Mac, or in Console.app. The OS retains/rotates them; the app does not keep its own log file. |
| Build/test logs | **GitHub Actions** | Every push stores the full build + test log on the run page. |

## Is there a third-party database? Should there be a Supabase?

No, and no — by design. Dayline is a single-user, single-device app whose
entire value is that your journal never leaves your phone. Supabase (or
Firebase, or any backend) would add accounts, auth, network sync conflicts,
a bill eventually, and a privacy surface — to solve a problem this app does
not have. The local SwiftData store *is* the database; it is a real
SQLite-backed store with queries, sorting, and migrations, just on-device.

The one legitimate job a server would do — backup/sync — is handled below
without one.

## iCloud: your instinct is right, and half of it already works

Two different things share the "iCloud" name, and only one costs money:

- **iCloud Photos** (your library syncing itself) — a consumer feature of
  your Apple ID. ANY app with your photo permission can reference those
  assets through PhotoKit, free provisioning included. **This is free and
  already works in Dayline.**
- **iCloud as a developer platform** (CloudKit containers, an iCloud
  documents folder owned by this app) — syncing the app's OWN data (here:
  journal text) between devices. That needs the iCloud entitlement, which
  free provisioning does not grant. **This is the $99-gated part** — plus
  widgets and share extensions, which need the same class of capability.

**Photos:** if you use iCloud Photos, your library already syncs itself.
PhotoKit doesn't care where an asset physically lives: ask for a
`localIdentifier` and iOS hands back the image, downloading it from iCloud
transparently when it isn't on the device (Dayline allows network access in
its image requests for exactly this reason). So "populate from iCloud like
the camera roll" is literally the current behaviour — the app is a lens on
the camera roll, not a second copy of it.

**Journal text:** entries are local-only today. There are three paths, in
the order I'd take them:

1. **Export (built, Data tab)** — JSON + readable Markdown export via the
   share sheet; save to iCloud Drive/Files. Manual, zero infrastructure,
   works under free provisioning. This is the backup story for now, and it
   means deleting the app is recoverable *if* you export.
2. **SwiftData + CloudKit (the real sync answer, later)** — SwiftData can
   mirror the same store into your private CloudKit database with a
   configuration change, no new backend and no third party: your entries
   would sync between your own devices under your Apple ID, end-to-end in
   your private container. **Blocker:** CloudKit needs the iCloud
   entitlement, which free provisioning does not grant. This is the single
   strongest reason to ever pay the $99 — not distribution, sync. If/when
   that day comes it's a small change, because the data model doesn't move.
3. **App Groups / widgets / share extension** — same entitlement family,
   same gate, same later date.

## Testing installs and where their data goes

- **Simulator (Mac):** the app installs into a simulated device container
  under `~/Library/Developer/CoreSimulator/Devices/…`. Data persists between
  launches; "Erase All Content and Settings" in Simulator wipes it. The
  SwiftData store file (`default.store`) inside the app container can be
  opened with any SQLite browser if you ever want to inspect raw rows.
- **Your iPhone (free provisioning):** data persists in the app sandbox
  across re-installs/re-signing (the 7-day expiry does not touch data), as
  long as the app is not deleted and the bundle ID does not change.
- Deleting the app deletes its sandbox — hence exports (path 1).

## Debugging signals, summarised
- Xcode console while running from the Mac — Logger output, including which
  polish backend actually ran (Foundation Models vs fallback) and why.
- Data tab in the app — entry count/range, Foundation Models availability,
  storage summary, exports.
- GitHub Actions — full build/test logs per push.
