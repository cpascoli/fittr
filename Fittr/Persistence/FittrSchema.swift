import Foundation
import SwiftData

/// The models backing the store.
///
/// **Migration policy.** SwiftData performs automatic lightweight migration for
/// additive changes — a new model, or a new property that is optional or carries
/// a default — and that covers everything done to this schema so far.
///
/// A `VersionedSchema` + `SchemaMigrationPlan` is deliberately *not* used here.
/// It only works if each version owns a snapshot of the old model definitions:
/// two `VersionedSchema`s that list the same live Swift types hash to the same
/// checksum, and Core Data rejects the migration stage between them with
/// `NSInvalidArgumentException: Duplicate version checksums detected` — at
/// launch, before any recovery UI can run. That was tried, and it crashed on a
/// real store.
///
/// So: for a **destructive** change (renaming a property, changing its type, or
/// making one non-optional without a default), the work is to introduce
/// `FittrSchemaV1` holding a copy of the *old* `@Model` definitions, point V2 at
/// the current ones, and add a `.custom` stage between them. Until then, keep
/// changes additive — and rely on `StoreRecoveryView` if an open ever fails.
enum FittrModels {
    static var all: [any PersistentModel.Type] {
        [
            UserProfile.self,
            AppSettings.self,
            BodyWeightEntry.self,
            PlannedExerciseLoad.self,
            PersonalRecord.self,
            HealthMetricReference.self,
            ExerciseDefinition.self,
            WorkoutPlan.self,
            WorkoutTemplate.self,
            WorkoutTemplateExercise.self,
            MusicAssignment.self,
            ScheduledWorkout.self,
            WorkoutSession.self,
            ExerciseSession.self,
            ExerciseSet.self,
            RestInterval.self,
            CardioMetrics.self,
            SwimMetrics.self,
        ]
    }
}

/// The outcome of trying to open the store on launch.
///
/// Opening can fail on a device that holds the only copy of the user's training
/// history, so failure is a state the app renders, never a trap.
enum StoreState {
    case ready(ModelContainer)
    case failed(StoreFailure)
}

struct StoreFailure {
    /// Technical detail, shown small so it can be reported.
    var message: String
    /// The on-disk files backing the store, for export before any reset.
    var files: [URL]
}

enum FittrSchema {
    static var models: [any PersistentModel.Type] { FittrModels.all }

    static var current: Schema { Schema(FittrModels.all) }

    static func configuration(inMemory: Bool = false) -> ModelConfiguration {
        ModelConfiguration("Fittr", schema: current, isStoredInMemoryOnly: inMemory)
    }

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: current,
            configurations: [configuration(inMemory: inMemory)]
        )
    }

    /// Opens the store, reporting failure instead of crashing.
    static func openStore(inMemory: Bool = false) -> StoreState {
        do {
            return .ready(try container(inMemory: inMemory))
        } catch {
            return .failed(
                StoreFailure(
                    message: String(describing: error),
                    files: existingStoreFiles(inMemory: inMemory)
                )
            )
        }
    }

    /// The SQLite store and its write-ahead-log siblings.
    ///
    /// Derived from the same `ModelConfiguration` the container uses, so this always
    /// points at wherever SwiftData actually put the store.
    static func storeFileURLs(inMemory: Bool = false) -> [URL] {
        guard !inMemory else { return [] }
        let base = configuration(inMemory: false).url
        let folder = base.deletingLastPathComponent()
        let name = base.lastPathComponent
        return [base] + ["-wal", "-shm"].map { folder.appendingPathComponent(name + $0) }
    }

    static func existingStoreFiles(inMemory: Bool = false) -> [URL] {
        storeFileURLs(inMemory: inMemory).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Deletes the store so the next open starts from a fresh seed.
    ///
    /// Irreversible: only call behind an explicit user confirmation, and only after
    /// offering `existingStoreFiles()` for export.
    static func deleteStoreFiles() throws {
        for url in existingStoreFiles() {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum LaunchArguments {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    static var resetStore: Bool {
        ProcessInfo.processInfo.arguments.contains("--reset-store")
    }
}
