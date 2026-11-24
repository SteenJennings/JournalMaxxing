import SwiftData
import Foundation

/// The versioned schema for the journal store (swarm audit, 2026-11-23).
/// Before this, the store opened with a bare `.modelContainer(for:)`,
/// so any model change — renaming a property, changing a type, adding a
/// non-optional field — could break the store on launch with no recovery
/// and no import to restore from. V1 is the model exactly as it shipped:
/// versioning it now, while the journal is small, means the next model
/// change gets a real migration stage instead of a silent gamble.
/// V1 deliberately keeps `placeholders` (a designed-but-never-wired
/// feature): deleting a stored property is itself a model change, and it
/// belongs in a V2 stage with a migration, not in a drive-by edit.
enum DaylineSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [DayEntry.self] }
}

enum DaylineMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [DaylineSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Opening the store, with a fallback the app never had: if the store
/// fails to open (a bad migration, a corrupt file), the old store files
/// are moved aside — never deleted — and a fresh store is opened, so the
/// app still launches. The moved-aside store stays on disk for manual
/// recovery, and the last JSON export remains the restore path.
enum JournalStore {
    static func makeContainer() -> ModelContainer {
        // The versioned overload takes a Schema *value*, not the
        // VersionedSchema metatype — `for: DaylineSchemaV1.self` does
        // not compile (CI issue #6).
        let schema = Schema(versionedSchema: DaylineSchemaV1.self)
        do {
            return try ModelContainer(for: schema, migrationPlan: DaylineMigrationPlan.self)
        } catch {
            Log.event("App", "store failed to open (\(error.localizedDescription)) - moving aside and opening fresh")
            moveAsideCorruptStore()
            do {
                return try ModelContainer(for: schema, migrationPlan: DaylineMigrationPlan.self)
            } catch {
                Log.event("App", "fresh store also failed (\(error.localizedDescription)) - opening in-memory")
                return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            }
        }
    }

    private static func moveAsideCorruptStore() {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = dir.appendingPathComponent("corrupt-store-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            let src = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.moveItem(at: src, to: dest.appendingPathComponent(name))
            }
        }
    }
}
