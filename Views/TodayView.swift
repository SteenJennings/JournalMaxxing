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
    /// Set when Steen hand-picks media in the day browser; wins over the
    /// auto-ranked suggestions at save time (auto stays the default).
    @State var mediaOverride: [PHAsset]?

    /// The day this screen is working on. The calendar, backfill, day
    /// rollover, photo fetch, ranking, browser, and save all scope to it -
    /// before this, the screen hardcoded Date() and kept yesterday's
    /// post-save state on screen forever (Steen's 2026-10-21 report).
    @State var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State var lastKnownToday: Date = Calendar.current.startOfDay(for: Date())

    var isTodaySelected: Bool { Calendar.current.isDateInToday(selectedDate) }
    var entryDays: Set<Date> {
        Set(allEntries.map { Calendar.current.startOfDay(for: $0.date) })
    }
    var elapsedString: String { String(format: "%d:%02d", recordingSeconds / 60, recordingSeconds % 60) }
    var wordCount: Int { transcript.split(whereSeparator: { $0.isWhitespace }).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(Theme.display(24)).foregroundStyle(Theme.ink)
                        if isTodaySelected {
                            Text("One page, every day.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Back to today") {
                                selectedDate = Calendar.current.startOfDay(for: Date())
                            }
                            .font(.caption).foregroundStyle(Theme.accent)
                        }
                    }

                    MonthCalendarView(selectedDate: $selectedDate, entryDays: entryDays)

                    TextField("Talk about your day...", text: $transcript, axis: .vertical)
                        .lineLimit(5...14)
                        .journalCard(padding: 12)
                        .onChange(of: transcriber.transcript) { _, newValue in
                            if transcriber.isRecording || !newValue.isEmpty { transcript = newValue }
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
                            Text(transcriber.isStarting ? "Starting..." : "Listening - \(elapsedString)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if wordCount > 0 { Text("\(wordCount) words").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }

                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedItems, matching: .any(of: [.images, .videos])) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title3).foregroundStyle(Theme.ink)
                                .frame(width: 48, height: 48)
                                .background(Theme.card, in: Circle())
                                .overlay(Circle().stroke(Theme.ink.opacity(0.08)))
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
                        Color.clear.frame(width: 48, height: 48)
                        Spacer()
                    }

                    Button { Task { await polishAndSave() } } label: {
                        Label(isPolishing ? "Polishing..." : "Polish + Save", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(Theme.accent)
                     .disabled(transcript.isEmpty || isPolishing)

                    if !photoService.todaysAssets.isEmpty {
                        Button { showDayBrowser = true } label: {
                            Label("Browse \(isTodaySelected ? "today" : "this day") - \(photoService.todaysAssets.count) photos & videos",
                                  systemImage: "square.grid.2x2")
                                .font(.subheadline).frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(Theme.ink)
                    }

                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(tags, id: \.self) { Text("#\($0)").font(.caption).padding(6).background(.blue.opacity(0.1)).clipShape(Capsule()) }
                                if let mood { Text(mood).font(.caption).padding(6).background(.purple.opacity(0.1)).clipShape(Capsule()) }
                            }
                        }
                    }

                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                        Text("Polished with: \(summarizer.lastBackendUsed)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    if !polished.isEmpty {
                        ScrapbookView(text: polished,
                                      assets: suggestedAssets,
                                      linkURLs: entryLinks,
                                      heading: "Scrapbook Preview")
                    }
                }.padding()
            }.navigationTitle("Today")
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
             .onChange(of: selectedDate) { _, newDay in
                 handleDaySelection(newDay)
             }
             .onChange(of: scenePhase) { _, phase in
                 if phase == .active { checkDayRollover() }
             }
             .sensoryFeedback(.success, trigger: savedMessage)
             .onChange(of: selectedItems) { _, items in
                 let ids = items.compactMap(\.itemIdentifier)
                 guard !ids.isEmpty else { return }
                 let picked = AssetMediaLoader.fetchAssets(localIdentifiers: ids)
                 for a in picked where !suggestedAssets.contains(where: { $0.localIdentifier == a.localIdentifier }) {
                     suggestedAssets.append(a)
                 }
             }
             .sheet(isPresented: $showDayBrowser) {
                 DayMediaBrowserView(
                     date: selectedDate,
                     initialSelection: Set((mediaOverride ?? (suggestedAssets.isEmpty ? photoService.suggest(for: transcript) : suggestedAssets)).map(\.localIdentifier))
                 ) { chosen in
                     mediaOverride = chosen
                     suggestedAssets = chosen
                 }
             }
        }
    }

    // MARK: - Day scoping

    /// Every day change funnels through here (calendar tap, rollover, back
    /// to today): reset compose state, scope photos to the new day, and
    /// load that day's entry if one exists.
    private func handleDaySelection(_ day: Date) {
        resetCompose()
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
        transcriber.clearAll()
    }

    /// If the selected day already has an entry, present it as the page
    /// (transcript, polished text, tags, media) instead of a blank editor -
    /// this is also what makes reopening the app show today's saved page.
    private func loadEntry(for day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let entry = (try? modelContext.fetch(descriptor))?.first else { return }
        transcript = entry.rawTranscript
        polished = entry.polishedText
        tags = entry.projectTags
        mood = entry.mood
        entryLinks = entry.linkURLs
        suggestedAssets = AssetMediaLoader.fetchAssets(localIdentifiers: entry.mediaLocalIds)
        savedMessage = "Saved to your journal"
        Log.event("Today", "loaded existing entry for \(start.formatted(date: .abbreviated, time: .omitted)) (\(entry.mediaLocalIds.count) media, \(entry.projectTags.count) tags)")
    }

    /// Midnight passed while the app sat open: if Steen was sitting on
    /// (what was) today, move to the new today. A mid-draft page is never
    /// yanked away - the rollover waits until the draft is saved or empty.
    private func checkDayRollover() {
        let today = Calendar.current.startOfDay(for: Date())
        guard today != lastKnownToday else { return }
        let wasOnOldToday = Calendar.current.isDate(selectedDate, inSameDayAs: lastKnownToday)
        lastKnownToday = today
        guard wasOnOldToday else { return }
        if transcript.isEmpty || savedMessage != nil {
            selectedDate = today
            Log.event("Today", "day rolled over - moved to \(today.formatted(date: .abbreviated, time: .omitted))")
        } else {
            Log.event("Today", "day rolled over but a draft is in progress - staying put")
        }
    }

    // MARK: - Polish & save

    func polishAndSave() async {
        isPolishing = true
        savedMessage = nil
        let result = await summarizer.polishFull(transcript: transcript)
        polished = result.polished
        tags = result.tags
        mood = result.mood
        entryLinks = LinkExtractor.extract(from: transcript)

        // Ranked suggestions first; fall back to the day's first assets.
        // photoService is scoped to selectedDate, so backfill days rank
        // against that day's library. A hand-picked browser selection wins.
        let ranked = await photoService.rankedSuggest(for: result.polished)
        suggestedAssets = ranked.isEmpty ? photoService.suggest(for: result.polished) : ranked
        if let mediaOverride { suggestedAssets = mediaOverride }

        saveEntry(result: result)
        isPolishing = false
    }

    /// One entry per calendar day (the selected day): re-polishing a day
    /// updates its entry instead of creating a duplicate.
    private func saveEntry(result: PolishResult) {
        let start = Calendar.current.startOfDay(for: selectedDate)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let existing = (try? modelContext.fetch(descriptor))?.first
        // A backfilled entry gets the selected day at the current time of
        // day; today's entry gets right now.
        let entryDate = isTodaySelected
            ? Date()
            : start.addingTimeInterval(Date().timeIntervalSince(Calendar.current.startOfDay(for: Date())))
        let entry = existing ?? DayEntry(date: entryDate, rawTranscript: transcript)
        entry.rawTranscript = transcript
        entry.polishedText = result.polished
        entry.projectTags = result.tags
        entry.mood = result.mood
        entry.mediaLocalIds = suggestedAssets.map(\.localIdentifier)
        entry.highlightLocalId = suggestedAssets.first?.localIdentifier
        entry.linkURLs = entryLinks
        entry.updatedAt = Date()
        if existing == nil { modelContext.insert(entry) }
        do {
            try modelContext.save()
            savedMessage = "Saved to your journal"
            Log.event("Save", "entry saved (\(existing == nil ? "new" : "updated")) for \(start.formatted(date: .abbreviated, time: .omitted)), media=\(entry.mediaLocalIds.count), tags=\(entry.projectTags.count)")
        } catch {
            savedMessage = "Could not save: \(error.localizedDescription)"
            Log.event("Save", "entry save FAILED: \(error.localizedDescription)")
        }
    }
}

#Preview { TodayView() }
