import SwiftUI
import SwiftData
import PhotosUI
import Photos

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \DayEntry.date) private var allEntries: [DayEntry]
    @StateObject var photoService = PhotoService()
    @StateObject var summarizer = Summarizer()
    @StateObject var transcriber = SpeechTranscriberService()
    @State var transcript = ""
    @State var polished = ""
    @State var tags: [String] = []
    @State var mood: String?
    @State var isPolishing = false
    @State var savedMessage: String?
    @State var suggestedAssets: [PHAsset] = []
    @State var entryLinks: [String] = []
    @State var selectedItems: [PhotosPickerItem] = []
    @State var recordingSeconds = 0
    @State var showDayBrowser = false
    /// Set when Steen hand-picks media in the day browser (or the +
    /// button); wins over the auto-ranked suggestions at save time.
    @State var mediaOverride: [PHAsset]?
    @State var isEditingPolished = false
    @State var preEditPolished = ""
    @FocusState private var editorFocused: Bool

    /// The day this screen is working on. The calendar, backfill, day
    /// rollover, photo fetch, ranking, browser, and save all scope to it -
    /// before this, the screen hardcoded Date() and kept yesterday's
    /// post-save state on screen forever (Steen's 2026-10-21 report).
    @State var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State var lastKnownToday: Date = Calendar.current.startOfDay(for: Date())
    /// A rollover that was deferred because a draft was in progress. The
    /// old code consumed the rollover on deferral, so it never fired again
    /// and the tab could show yesterday forever.
    @State var pendingRollover: Date?
    /// The raw transcript of the entry as loaded ("" on a fresh day).
    /// Dirty = the editor no longer matches it, or a polish edit is open.
    @State var loadedRawTranscript = ""
    /// Speech mirroring discipline (swarm audit 2026-11-23): live results
    /// used to overwrite anything typed, and re-recording wiped manual
    /// edits. The mirror only runs while the editor still shows what
    /// recording started with or what was last mirrored; anything the
    /// user typed is appended on stop, never replaced.
    @State var recordStartTranscript = ""
    @State var lastMirroredTranscript = ""
    @State private var draftTask: Task<Void, Never>?

    var isTodaySelected: Bool { Calendar.current.isDateInToday(selectedDate) }
    var entryDays: Set<Date> {
        Set(allEntries.map { Calendar.current.startOfDay(for: $0.date) })
    }
    var elapsedString: String { String(format: "%d:%02d", recordingSeconds / 60, recordingSeconds % 60) }
    var wordCount: Int { transcript.split(whereSeparator: { $0.isWhitespace }).count }
    var isDirty: Bool { transcript != loadedRawTranscript || isEditingPolished }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Theme.kicker("Dayline").foregroundStyle(Theme.accentText)
                        Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(Theme.display(24)).foregroundStyle(Theme.ink)
                        if isTodaySelected {
                            Text("One page, every day.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Back to today") {
                                selectedDate = Calendar.current.startOfDay(for: Date())
                            }
                            .font(.caption).foregroundStyle(Theme.ink)
                        }
                        if pendingRollover != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.exclamationmark")
                                Text("You're still on yesterday — your draft is safe.")
                                Button("Go to today") {
                                    selectedDate = Calendar.current.startOfDay(for: Date())
                                }.bold()
                            }
                            .font(.caption).foregroundStyle(Theme.ink)
                            .padding(8)
                            .background(Theme.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Hairline().padding(.top, 4)
                    }

                    MonthCalendarView(selectedDate: $selectedDate, entryDays: entryDays)

                    TextField("Talk about your day...", text: $transcript, axis: .vertical)
                        .lineLimit(5...14)
                        .journalCard(padding: 12)
                        .focused($editorFocused)
                        .onChange(of: transcriber.transcript) { _, newValue in
                            if transcriber.isRecording {
                                if transcript == lastMirroredTranscript || transcript == recordStartTranscript {
                                    transcript = newValue
                                    lastMirroredTranscript = newValue
                                }
                            } else if !newValue.isEmpty {
                                transcript = newValue
                                lastMirroredTranscript = newValue
                            }
                        }
                        .onChange(of: transcript) { _, newValue in
                            // Draft autosave: a dictation must never live
                            // only in memory. Debounced; skips text that
                            // is exactly the loaded entry (no new work).
                            draftTask?.cancel()
                            guard !newValue.isEmpty, newValue != loadedRawTranscript else { return }
                            let day = selectedDate
                            draftTask = Task {
                                try? await Task.sleep(for: .seconds(1))
                                guard !Task.isCancelled else { return }
                                DraftStore.shared.saveDraft(day: day, text: newValue)
                            }
                        }

                    if let err = transcriber.errorMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Text(err).font(.caption).foregroundStyle(.red)
                            Spacer()
                            Button { transcriber.clearAll() } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss")
                        }
                    }

                    if transcriber.isRecording || transcriber.isStarting {
                        HStack(spacing: 8) {
                            Circle().fill(.red).frame(width: 9, height: 9)
                                .symbolEffect(.pulse, options: .repeating, isActive: transcriber.isRecording)
                            Text(transcriber.isStarting
                                 ? (transcriber.statusMessage ?? "Starting...")
                                 : "Listening - \(elapsedString)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if wordCount > 0 { Text("\(wordCount) words").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }

                    // The mic is centered; the + button sits leading. A
                    // ZStack (not a clear-spacer hack) keeps the mic
                    // centered under Dynamic Type.
                    ZStack {
                        HStack {
                            PhotosPicker(selection: $selectedItems, matching: .any(of: [.images, .videos])) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title3).foregroundStyle(Theme.ink)
                                    .frame(width: 48, height: 48)
                                    .background(Theme.card, in: Circle())
                                    .overlay(Circle().stroke(Theme.ink.opacity(0.08)))
                            }
                            .accessibilityLabel("Add photos")
                            Spacer()
                        }
                        Button { transcriber.toggle() } label: {
                            Image(systemName: transcriber.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 68, height: 68)
                                .background(transcriber.isRecording ? Color.red : Theme.accent, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
                        }
                        .accessibilityLabel(transcriber.isRecording ? "Stop recording" : "Start recording")
                    }

                    Button { Task { await polishAndSave() } } label: {
                        Label(isPolishing ? "Polishing..." : "Polish + Save", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    // Ink only: the save is a quiet, confident action.
                    // The mic is the one ink thing on the page.
                    .buttonStyle(.borderedProminent).tint(Theme.ink)
                    // Never polish mid-recording: the old code saved a
                    // partial entry, then live results kept overwriting
                    // the editor so the screen diverged from the save.
                    .disabled(transcript.isEmpty || isPolishing || transcriber.isRecording || transcriber.isStarting)

                    Button { showDayBrowser = true } label: {
                        Label(photoService.todaysAssets.isEmpty
                              ? "Browse \(isTodaySelected ? "today" : "this day")"
                              : "Browse \(isTodaySelected ? "today" : "this day") - \(photoService.todaysAssets.count) photos & videos",
                              systemImage: "square.grid.2x2")
                            .font(.subheadline).frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).tint(Theme.ink)

                    // Limited access used to be invisible: the app just
                    // showed fewer photos with no explanation. Say so,
                    // and offer the picker that adds more.
                    if photoService.permissionStatus == .limited {
                        Button("Showing only the photos you've chosen — tap to choose more") {
                            LimitedLibraryPicker.present()
                        }
                        .font(.caption).foregroundStyle(Theme.ink)
                    }

                    if let mediaOverride, polished.isEmpty {
                        Text("\(mediaOverride.count) photo\(mediaOverride.count == 1 ? "" : "s") picked — they'll be in your entry when you polish.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if !tags.isEmpty || mood != nil {
                        TagLine(tags: tags, mood: mood)
                    }

                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(Theme.ink)
                        Text("Polished with: \(summarizer.lastBackendUsed)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    if !polished.isEmpty {
                        if isEditingPolished {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Edit entry text").font(Theme.display(15)).foregroundStyle(Theme.ink)
                                TextField("Entry text", text: $polished, axis: .vertical)
                                    .lineLimit(6...20)
                                    .journalCard(padding: 12)
                                    .focused($editorFocused)
                                HStack {
                                    Button("Cancel") {
                                        polished = preEditPolished
                                        isEditingPolished = false
                                    }.buttonStyle(.bordered)
                                    Spacer()
                                    Button("Save edits") {
                                        persistPageEdits()
                                        isEditingPolished = false
                                    }.buttonStyle(.borderedProminent).tint(Theme.ink)
                                }
                            }
                        } else {
                            ScrapbookView(text: polished,
                                          assets: suggestedAssets,
                                          linkURLs: entryLinks,
                                          heading: "Scrapbook Preview")
                            HStack(spacing: 18) {
                                Button {
                                    preEditPolished = polished
                                    isEditingPolished = true
                                } label: { Label("Edit text", systemImage: "pencil").font(.caption) }
                                Button { showDayBrowser = true } label: {
                                    Label("Edit photos", systemImage: "photo.on.rectangle.angled").font(.caption)
                                }
                                Spacer()
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.ink)
                        }
                    }
                }.padding()
            }
            // The keyboard used to cover Polish + Save while editing
            // (BACKLOG item 9): dismiss it interactively, and always
            // offer a Done key above it.
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
            .navigationTitle("Today")
             .background(Theme.paper)
             .task {
                 photoService.requestPermissionAndFetch()
                 loadEntry(for: selectedDate)
             }
             .task(id: transcriber.isRecording) {
                 recordingSeconds = 0
                 guard transcriber.isRecording else { return }
                 while !Task.isCancelled {
                     try? await Task.sleep(for: .seconds(1))
                     recordingSeconds += 1
                 }
             }
             .onChange(of: transcriber.isRecording) { _, recording in
                 if recording {
                     recordStartTranscript = transcript
                     lastMirroredTranscript = transcript
                 } else {
                     // Stop: anything the user typed while recording was
                     // protected from the mirror — append the speech that
                     // arrived after the last mirror instead of replacing
                     // their words. Never destroys manual edits.
                     let live = transcriber.transcript
                     if !live.isEmpty, transcript != lastMirroredTranscript {
                         if live.hasPrefix(lastMirroredTranscript) {
                             let rest = String(live.dropFirst(lastMirroredTranscript.count))
                                 .trimmingCharacters(in: .whitespaces)
                             if !rest.isEmpty {
                                 transcript += (transcript.isEmpty ? "" : " ") + rest
                             }
                         } else if !transcript.contains(live) {
                             transcript += (transcript.isEmpty ? "" : "\n") + live
                         }
                     }
                 }
             }
             .onChange(of: selectedDate) { oldDay, newDay in
                 handleDaySelection(from: oldDay, to: newDay)
             }
             .onChange(of: scenePhase) { _, phase in
                 if phase == .active {
                     checkDayRollover()
                     // The library may have changed while the app was
                     // away; re-scope the pool to the working day.
                     photoService.fetchAssets(on: selectedDate)
                 }
             }
             .sensoryFeedback(.success, trigger: savedMessage)
             .onChange(of: selectedItems) { _, items in
                 let ids = items.compactMap(\.itemIdentifier)
                 guard !ids.isEmpty else { return }
                 let picked = AssetMediaLoader.fetchAssets(localIdentifiers: ids)
                 for a in picked where !suggestedAssets.contains(where: { $0.localIdentifier == a.localIdentifier }) {
                     suggestedAssets.append(a)
                 }
                 // A + pick is a hand-pick: it must survive the next
                 // Polish + Save, which only preserves mediaOverride.
                 if mediaOverride == nil { mediaOverride = suggestedAssets }
                 else {
                     for a in picked where !mediaOverride!.contains(where: { $0.localIdentifier == a.localIdentifier }) {
                         mediaOverride!.append(a)
                     }
                 }
             }
             .sheet(isPresented: $showDayBrowser) {
                 DayMediaBrowserView(
                     date: selectedDate,
                     initialSelection: Set((mediaOverride ?? (suggestedAssets.isEmpty ? photoService.suggest(for: transcript) : suggestedAssets)).map(\.localIdentifier))
                 ) { chosen in
                     mediaOverride = chosen
                     suggestedAssets = chosen
                     // If this day already has a saved entry, the new media
                     // set sticks immediately - no re-polish needed.
                     persistPageEdits()
                 }
             }
        }
    }

    // MARK: - Day scoping

    /// Every day change funnels through here (calendar tap, rollover, back
    /// to today): save the outgoing draft, stop any live recording (it
    /// must never bleed onto the new day's page), reset compose state,
    /// scope photos to the new day, and load that day's entry if one exists.
    private func handleDaySelection(from oldDay: Date, to day: Date) {
        if !transcript.isEmpty { DraftStore.shared.saveDraft(day: oldDay, text: transcript) }
        if transcriber.isRecording || transcriber.isStarting { transcriber.stop() }
        resetCompose()
        if Calendar.current.isDateInToday(day) {
            lastKnownToday = Calendar.current.startOfDay(for: Date())
            pendingRollover = nil
        }
        photoService.fetchAssets(on: day)
        loadEntry(for: day)
    }

    private func resetCompose() {
        transcript = ""
        polished = ""
        tags = []
        mood = nil
        savedMessage = nil
        suggestedAssets = []
        entryLinks = []
        mediaOverride = nil
        selectedItems = []
        loadedRawTranscript = ""
        recordStartTranscript = ""
        lastMirroredTranscript = ""
        transcriber.clearAll()
    }

    /// If the selected day already has an entry, present it as the page
    /// (transcript, polished text, tags, media) instead of a blank editor -
    /// this is also what makes reopening the app show today's saved page.
    /// A draft for the day is newer work than the saved entry, so it wins.
    private func loadEntry(for day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let entry = (try? modelContext.fetch(descriptor))?.first else { return }
        transcript = entry.rawTranscript
        loadedRawTranscript = entry.rawTranscript
        polished = entry.polishedText
        tags = entry.projectTags
        mood = entry.mood
        entryLinks = entry.linkURLs
        suggestedAssets = AssetMediaLoader.fetchAssets(localIdentifiers: entry.mediaLocalIds)
        savedMessage = "Saved to your journal"
        if let draft = DraftStore.shared.draft(for: day), draft != transcript {
            transcript = draft
            savedMessage = nil
            Log.event("Today", "restored unsaved draft for \(start.formatted(date: .abbreviated, time: .omitted))")
        }
        Log.event("Today", "loaded existing entry for \(start.formatted(date: .abbreviated, time: .omitted)) (\(entry.mediaLocalIds.count) media, \(entry.projectTags.count) tags)")
    }

    /// Midnight passed while the app sat open: if Steen was sitting on
    /// (what was) today, move to the new today. A mid-draft page is never
    /// yanked away — but the rollover is NOT consumed on deferral: the
    /// old code set lastKnownToday first, so the rollover never fired
    /// again and the tab could show yesterday forever. Dirty is a real
    /// check now (editor vs. loaded entry, or an open polish edit), not
    /// "an entry exists".
    private func checkDayRollover() {
        let today = Calendar.current.startOfDay(for: Date())
        guard today != lastKnownToday else { return }
        let wasOnOldToday = Calendar.current.isDate(selectedDate, inSameDayAs: lastKnownToday)
        guard wasOnOldToday else { lastKnownToday = today; return }
        if isDirty {
            pendingRollover = today
            Log.event("Today", "day rolled over but a draft is in progress - staying put (will retry)")
        } else {
            lastKnownToday = today
            pendingRollover = nil
            selectedDate = today
            Log.event("Today", "day rolled over - moved to \(today.formatted(date: .abbreviated, time: .omitted))")
        }
    }

    /// Write the page's current text + media back to the day's saved entry
    /// WITHOUT re-polishing (inline edits from the preview, photo changes
    /// from the day browser). No-op when the day has no entry yet.
    private func persistPageEdits() {
        let start = Calendar.current.startOfDay(for: selectedDate)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let entry = (try? modelContext.fetch(descriptor))?.first else { return }
        entry.polishedText = polished
        // An empty media list here means the fetch resolved nothing, not
        // that the user removed every photo — never erase stored media
        // on an empty pick.
        if suggestedAssets.isEmpty, !entry.mediaLocalIds.isEmpty {
            Log.event("Save", "preview edit kept \(entry.mediaLocalIds.count) stored photos (empty pick)")
        } else {
            entry.mediaLocalIds = suggestedAssets.map(\.localIdentifier)
        }
        if let highlight = entry.highlightLocalId, !entry.mediaLocalIds.contains(highlight) {
            entry.highlightLocalId = entry.mediaLocalIds.first
        }
        entry.updatedAt = Date()
        do {
            try modelContext.save()
            savedMessage = "Saved to your journal"
            Log.event("Save", "entry edited from preview for \(start.formatted(date: .abbreviated, time: .omitted)), media=\(entry.mediaLocalIds.count)")
        } catch {
            savedMessage = "Could not save edits: \(error.localizedDescription)"
            Log.event("Save", "preview edit FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: - Polish & save

    func polishAndSave() async {
        // Snapshot the day and the text up front: the old code read live
        // state after the await, so tapping another day mid-polish saved
        // Day A's text onto Day B and Day A was never saved at all.
        let day = selectedDate
        let text = transcript
        isPolishing = true
        savedMessage = nil
        let result = await summarizer.polishFull(transcript: text)
        // Rank against what was said AND the polish — the polish
        // paraphrases, and concrete nouns ("pool") can be lost between
        // dictation and ranking.
        let ranked = await photoService.rankedSuggest(for: "\(text) \(result.polished)")
        var picks = ranked.isEmpty ? photoService.suggest(for: result.polished) : ranked
        if let mediaOverride { picks = mediaOverride }

        saveEntry(day: day, text: text, result: result, assets: picks)
        if Calendar.current.isDate(day, inSameDayAs: selectedDate) {
            polished = result.polished
            tags = result.tags
            mood = result.mood
            entryLinks = LinkExtractor.extract(from: text)
            suggestedAssets = picks
        } else {
            Log.event("Save", "polish finished after a day change - saved to \(day.formatted(date: .abbreviated, time: .omitted)), left the new day's page alone")
        }
        isPolishing = false
    }

    /// One entry per calendar day (the snapshotted day): re-polishing a day
    /// updates its entry instead of creating a duplicate.
    private func saveEntry(day: Date, text: String, result: PolishResult, assets: [PHAsset]) {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let existing = (try? modelContext.fetch(descriptor))?.first
        // A backfilled entry gets the selected day at the current time of
        // day; today's entry gets right now. Calendar arithmetic, not raw
        // interval math — on the 25-hour "fall back" day the interval can
        // exceed 24h and land the entry on the wrong day.
        let entryDate: Date
        if Calendar.current.isDateInToday(day) {
            entryDate = Date()
        } else {
            let now = Date()
            entryDate = Calendar.current.date(
                bySettingHour: Calendar.current.component(.hour, from: now),
                minute: Calendar.current.component(.minute, from: now),
                second: Calendar.current.component(.second, from: now),
                of: start) ?? start
        }
        let entry = existing ?? DayEntry(date: entryDate, rawTranscript: text)
        entry.rawTranscript = text
        entry.polishedText = result.polished
        entry.projectTags = result.tags
        // A fallback polish returns no mood; keep the entry's existing
        // mood rather than erasing it on re-polish.
        entry.mood = result.mood ?? existing?.mood
        let pickedIds = assets.map(\.localIdentifier)
        if pickedIds.isEmpty, let existing, !existing.mediaLocalIds.isEmpty {
            Log.event("Save", "empty media pick for \(start.formatted(date: .abbreviated, time: .omitted)) - keeping \(existing.mediaLocalIds.count) stored photos")
        } else {
            entry.mediaLocalIds = pickedIds
        }
        // Preserve a hand-set cover: only set the highlight when there
        // isn't one, or the old one is no longer in the media set.
        if let highlight = entry.highlightLocalId, entry.mediaLocalIds.contains(highlight) {
            // keep it
        } else {
            entry.highlightLocalId = entry.mediaLocalIds.first
        }
        entry.linkURLs = LinkExtractor.extract(from: text)
        entry.updatedAt = Date()
        if existing == nil { modelContext.insert(entry) }
        do {
            try modelContext.save()
            DraftStore.shared.clearDraft(for: day)
            if Calendar.current.isDate(day, inSameDayAs: selectedDate) {
                savedMessage = "Saved to your journal"
                loadedRawTranscript = text
            }
            Log.event("Save", "entry saved (\(existing == nil ? "new" : "updated")) for \(start.formatted(date: .abbreviated, time: .omitted)), media=\(entry.mediaLocalIds.count), tags=\(entry.projectTags.count)")
            // A deferred rollover may now be unblocked.
            if pendingRollover != nil { checkDayRollover() }
        } catch {
            savedMessage = "Could not save: \(error.localizedDescription)"
            Log.event("Save", "entry save FAILED: \(error.localizedDescription)")
        }
    }
}

#Preview { TodayView() }
