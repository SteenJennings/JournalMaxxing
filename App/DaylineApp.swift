
import SwiftUI
import SwiftData
import UIKit

@main
struct DaylineApp: App {
    init() {
        Log.event("App", "launched on iOS \(UIDevice.current.systemVersion)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [DayEntry.self])
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
        // Ink, not rust: the tab bar is chrome, and rust is reserved
        // for the mic, the selected day, and the favorite mark.
        .tint(Theme.ink)
    }
}
