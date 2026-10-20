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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Date(), style: .date).font(.headline).foregroundStyle(.secondary)

                    TextField("Talk about your day...", text: $transcript, axis: .vertical)
                        .lineLimit(4...12)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: transcriber.transcript) { _, newValue in
                            if transcriber.isRecording || !newValue.isEmpty { transcript = newValue }
                        }

                    if let err = transcriber.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }

                    HStack {
                        Button { transcriber.toggle() } label: {
                            Label(transcriber.isRecording ? "Stop" : "Speak",
                                  systemImage: transcriber.isRecording ? "stop.circle.fill" : "mic.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(transcriber.isRecording ? .red : .accentColor)

                        Button { Task { await polishAndSave() } } label: {
                            Label(isPolishing ? "Polishing..." : "Polish + Save", systemImage: "wand.and.stars")
                        }.buttonStyle(.borderedProminent).disabled(transcript.isEmpty || isPolishing)

                        PhotosPicker(selection: $selectedItems, matching: .any(of: [.images, .videos])) {
                            Label("Add", systemImage: "photo.badge.plus")
                        }.buttonStyle(.bordered)
                    }
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
             .task { photoService.requestPermissionAndFetch() }
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
