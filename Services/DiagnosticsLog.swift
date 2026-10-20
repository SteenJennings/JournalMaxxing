import Foundation
import os

/// Persistent, in-app diagnostics log - built for field testing on a real
/// phone where Xcode's console is not attached.
///
/// Why this exists: the interesting failure modes (photos not suggesting,
/// speech stopping, polish falling back) happen away from a Mac. This log
/// records the decision points - permissions, fetch counts, backend choices,
/// errors - survives relaunches (written to Application Support), and can be
/// shared out from the Data tab. Every entry also mirrors to the unified log
/// (subsystem com.steenjennings.dayline) for live Xcode sessions.
///
/// It must NEVER be able to crash the app: all file IO is best-effort.
final class DiagnosticsLog: ObservableObject {
    static let shared = DiagnosticsLog()

    @Published private(set) var lines: [String] = []

    private var storage: [String] = []
    private let lock = NSLock()
    private let storageURL: URL?
    private let maxLines = 500
    private static let osLog = Logger(subsystem: "com.steenjennings.dayline", category: "Diagnostics")

    init(storageURL: URL? = DiagnosticsLog.defaultFileURL()) {
        self.storageURL = storageURL
        if let storageURL,
           let text = try? String(contentsOf: storageURL, encoding: .utf8) {
            let loaded = text.split(separator: "\n").map(String.init)
            storage = Array(loaded.suffix(maxLines))
            lines = storage
        }
    }

    static func defaultFileURL() -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dayline-diagnostics.log")
    }

    func log(_ category: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(category)] \(message)"
        Self.osLog.info("\(line, privacy: .public)")
        lock.lock()
        storage.append(line)
        if storage.count > maxLines { storage.removeFirst(storage.count - maxLines) }
        let snapshot = storage
        lock.unlock()
        persist(snapshot)
        DispatchQueue.main.async { [weak self] in self?.lines = snapshot }
    }

    func exportText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return storage.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        storage = []
        lock.unlock()
        if let storageURL { try? FileManager.default.removeItem(at: storageURL) }
        DispatchQueue.main.async { [weak self] in self?.lines = [] }
    }

    private func persist(_ snapshot: [String]) {
        guard let storageURL else { return }
        try? snapshot.joined(separator: "\n").write(to: storageURL, atomically: true, encoding: .utf8)
    }
}

/// Short call-site helper: `Log.event("Photos", "fetched 42 assets")`.
enum Log {
    static func event(_ category: String, _ message: String) {
        DiagnosticsLog.shared.log(category, message)
    }
}
