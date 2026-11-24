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
    /// Lines trimmed off the front of the ring buffer, so far. The log
    /// used to drop old lines silently — after a week of use there was
    /// no way to tell history was missing.
    private var droppedCount = 0
    private static let osLog = Logger(subsystem: "com.steenjennings.dayline", category: "Diagnostics")
    private static let timestampFormatter = ISO8601DateFormatter()

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
        lock.lock()
        // The formatter is shared and not thread-safe; format inside
        // the lock that already guards storage.
        let line = "\(Self.timestampFormatter.string(from: Date())) [\(category)] \(message)"
        storage.append(line)
        if storage.count > maxLines {
            let dropped = storage.count - maxLines
            storage.removeFirst(dropped)
            droppedCount += dropped
            // The marker consumes the oldest surviving line's slot, so
            // the 500-line cap still holds exactly.
            storage[0] = "… \(droppedCount) earlier line\(droppedCount == 1 ? "" : "s") dropped …"
        }
        let snapshot = storage
        lock.unlock()
        Self.osLog.info("\(line, privacy: .public)")
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
        droppedCount = 0
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
