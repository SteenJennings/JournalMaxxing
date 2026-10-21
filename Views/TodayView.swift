import SwiftUI
import SwiftData
import PhotosUI
import Photos

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
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

    var elapsedString: String { String(format: "%d:%02d", recordingSeconds / 60, recordingSeconds % 60) }
    var wordCount: Int { transcript.split(whereSeparator: { $0.isWhitespace }).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(Theme.display(24)).foregroundStyle(Theme.ink)
                        Text("One page, every day.").font(.caption).foregroundStyle(.secondary)
                    }

                    TextField("Talk about your day...", text: $transcript, axis: .vertical)
                        .lineLimit(5...14)
                        .journalCard(padding: 12)
                        .onChange(of: transcriber.transcript) { _, newValue in
                            if transcriber.isRecording || !newValue.isEmpty { transcript = newValue }
                        }

                    if let err = transcriber.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
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
                    .onChange(of: selectedItems) { _, items in
                        let ids = items.compactMap(\.itemIdentifier)
                        guard !ids.isEmpty else { return }
                        let picked = AssetMediaLoader.fetchAssets(localIdentifiers: ids)
                        for a in picked where !suggestedAssets.contains(where: { $0.localIdentifier == a.localIdentifier }) {
                            suggestedAssets.append(a)
                        }
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
                                      linkURLs: entryLinks)
                    }
                }.padding()
            }.navigationTitle("Today")
             .background(Theme.paper)
             .task { photoService.requestPermissionAndFetch() }
             .task(id: transcriber.isRecording) {
                 recordingSeconds = 0
                 guard transcriber.isRecording else { return }
                 while !Task.isCancelled {
                     try? await Task.sleep(for: .seconds(1))
                     recordingSeconds += 1
                 }
             }
             .sensoryFeedback(.success, trigger: savedMessage)
        }
    }

    func polishAndSave() async {
        isPolishing = true
        savedMessage = nil
        let result = await summarizer.polishFull(transcript: transcript)
        polished = result.polished
        tags = result.tags
        mood = result.mood
        entryLinks = LinkExtractor.extract(from: transcript)

        // Ranked suggestions first; fall back to the day's first assets.
        let ranked = await photoService.rankedSuggest(for: result.polished)
        suggestedAssets = ranked.isEmpty ? photoService.suggest(for: result.polished) : ranked

        saveEntry(result: result)
        isPolishing = false
    }

    /// One entry per calendar day: re-polishing today updates today's entry
    /// instead of creating a duplicate.
    private func saveEntry(result: PolishResult) {
        let start = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date >= start },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let existing = (try? modelContext.fetch(descriptor))?.first {
            Calendar.current.isDateInToday($0.date)
        }
        let entry = existing ?? DayEntry(date: Date(), rawTranscript: transcript)
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
            Log.event("Save", "entry saved (\(existing == nil ? "new" : "updated")), media=\(entry.mediaLocalIds.count), tags=\(entry.projectTags.count)")
        } catch {
            savedMessage = "Could not save: \(error.localizedDescription)"
            Log.event("Save", "entry save FAILED: \(error.localizedDescription)")
        }
    }
}

#Preview { TodayView() }
