
import SwiftUI
import SwiftData
import UIKit

@main
struct DaylineApp: App {
    // The container is built explicitly (not via the modifier) so a
    // store that fails to open gets the move-aside-and-retry fallback in
    // JournalStore instead of crashing the launch.
    private let container: ModelContainer = {
        let c = JournalStore.makeContainer()
        JournalMaintenance.dedupeDuplicates(in: c.mainContext)
        return c
    }()

    init() {
        Log.event("App", "launched on iOS \(UIDevice.current.systemVersion)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "mic.fill") }
            TimelineView().tabItem { Label("Year", systemImage: "calendar") }
            TrendsView().tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
            DataView().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        // Ink only: the tab bar is chrome, and ink marks the thing
        // that matters (mic, selected day, favorite mark).
        .tint(Theme.ink)
    }
}
