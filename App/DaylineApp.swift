
import SwiftUI
import SwiftData

@main
struct DaylineApp: App {
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
        }
    }
}
