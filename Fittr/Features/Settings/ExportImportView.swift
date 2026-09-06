import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExportImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var settings: [AppSettings]
    @Query private var exercises: [ExerciseDefinition]
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query private var weights: [BodyWeightEntry]
    @Query private var records: [PersonalRecord]
    @State private var exportURL: URL?
    @State private var showingImporter = false
    @State private var message = ""

    var body: some View {
        Form {
            Section("Export") {
                Text("JSON is the full structured backup. CSV files cover workouts, exercises, sets, cardio, and swimming.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ShareLink(item: jsonURL(), preview: SharePreview("fittr-backup.json")) {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: csvFolderURL(), preview: SharePreview("fittr-csv")) {
                    Label("Export CSV", systemImage: "tablecells")
                }
            }
            Section("Import") {
                Text("Import never silently overwrites. New sessions are added alongside existing history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Import Fittr JSON") { showingImporter = true }
                if !message.isEmpty {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Export data")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importJSON(from: url)
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }

    private func backup() -> FittrBackup {
        DataExportService.makeBackup(
            profile: profiles.first,
            settings: settings.first,
            exercises: exercises,
            sessions: sessions,
            weights: weights,
            records: records
        )
    }

    private func jsonURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fittr-backup.json")
        if let data = try? DataExportService.jsonData(from: backup()) {
            try? data.write(to: url)
        }
        return url
    }

    private func csvFolderURL() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fittr-csv", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = DataExportService.csvBundle(from: backup())
        for (name, data) in files {
            try? data.write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    private func importJSON(from url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let backup = try DataExportService.decodeBackup(from: data)
            var imported = 0
            let existingIDs = Set(sessions.map(\.id))
            for sessionDTO in backup.sessions where !existingIDs.contains(sessionDTO.id) {
                let session = WorkoutSession(
                    id: sessionDTO.id,
                    name: sessionDTO.name,
                    type: WorkoutType(rawValue: sessionDTO.type) ?? .strength,
                    source: .manual,
                    startedAt: sessionDTO.startedAt,
                    endedAt: sessionDTO.endedAt,
                    templateSnapshotJSON: sessionDTO.templateSnapshotJSON,
                    notes: sessionDTO.notes,
                    sessionRPE: sessionDTO.sessionRPE,
                    workoutTemplateId: SeedID.mondayStrength
                )
                for exerciseDTO in sessionDTO.exercises {
                    let exercise = ExerciseSession(
                        id: exerciseDTO.id,
                        exerciseId: exerciseDTO.exerciseId,
                        exerciseName: exerciseDTO.exerciseName,
                        order: exerciseDTO.order,
                        startedAt: exerciseDTO.startedAt,
                        endedAt: exerciseDTO.endedAt,
                        notes: exerciseDTO.notes,
                        snapshotJSON: "{}",
                        workout: session
                    )
                    for setDTO in exerciseDTO.sets {
                        exercise.sets.append(
                            ExerciseSet(
                                id: setDTO.id,
                                setNumber: setDTO.setNumber,
                                weightKg: setDTO.weightKg,
                                reps: setDTO.reps,
                                leftReps: setDTO.leftReps,
                                rightReps: setDTO.rightReps,
                                durationSeconds: setDTO.durationSeconds,
                                rpe: setDTO.rpe,
                                rir: setDTO.rir,
                                startedAt: setDTO.startedAt,
                                completedAt: setDTO.completedAt,
                                status: SetStatus(rawValue: setDTO.status) ?? .completed,
                                notes: setDTO.notes,
                                exercise: exercise
                            )
                        )
                    }
                    session.exercises.append(exercise)
                }
                modelContext.insert(session)
                imported += 1
            }
            try modelContext.save()
            message = "Imported \(imported) workout(s). Existing sessions were left untouched."
        } catch {
            message = error.localizedDescription
        }
    }
}
