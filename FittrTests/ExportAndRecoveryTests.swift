import Foundation
import SwiftData
import Testing
@testable import Fittr

struct ExportAndRecoveryTests {
    @Test func jsonAndCSVExportContainWorkouts() throws {
        let backup = FittrBackup(
            formatVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            profile: nil,
            settings: nil,
            exercises: [],
            sessions: [
                SessionDTO(
                    id: UUID(),
                    name: "Full Body Strength",
                    type: "strength",
                    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    endedAt: Date(timeIntervalSince1970: 1_700_002_400),
                    notes: "Felt energetic",
                    sessionRPE: 7,
                    templateSnapshotJSON: "{}",
                    exercises: [
                        ExerciseSessionDTO(
                            id: UUID(),
                            exerciseId: SeedID.gobletSquat,
                            exerciseName: "Goblet Squat",
                            order: 0,
                            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
                            notes: "",
                            sets: [
                                SetDTO(
                                    id: UUID(),
                                    setNumber: 1,
                                    weightKg: 10,
                                    reps: 10,
                                    leftReps: nil,
                                    rightReps: nil,
                                    durationSeconds: nil,
                                    rpe: nil,
                                    rir: 3,
                                    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                    completedAt: Date(timeIntervalSince1970: 1_700_000_040),
                                    status: "completed",
                                    notes: ""
                                ),
                            ],
                            rests: []
                        ),
                    ]
                ),
            ],
            bodyWeights: [],
            personalRecords: []
        )

        let json = try DataExportService.jsonData(from: backup)
        let decoded = try DataExportService.decodeBackup(from: json)
        #expect(decoded.sessions.count == 1)
        #expect(decoded.sessions[0].sessionRPE == 7)

        let csv = DataExportService.csvBundle(from: backup)
        let workouts = String(data: csv["workouts.csv"]!, encoding: .utf8) ?? ""
        let sets = String(data: csv["sets.csv"]!, encoding: .utf8) ?? ""
        #expect(workouts.contains("Full Body Strength"))
        #expect(sets.contains("Goblet Squat"))
        #expect(workouts.contains("2023-") || workouts.contains("T"))
    }

    @Test func rejectedUnknownBackupVersion() {
        let data = Data("{\"formatVersion\":99,\"exportedAt\":\"2026-01-01T00:00:00Z\",\"exercises\":[],\"sessions\":[],\"bodyWeights\":[],\"personalRecords\":[]}".utf8)
        #expect(throws: ExportError.self) {
            try DataExportService.decodeBackup(from: data)
        }
    }

    @Test func inProgressSessionSurvivesStoreReload() throws {
        let container = try FittrSchema.container(inMemory: true)
        let context = ModelContext(container)
        try SeedService.seedIfNeeded(in: context)
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let monday = try #require(templates.first { $0.id == SeedID.mondayStrength })
        let session = try WorkoutSessionFactory.start(template: monday, scheduled: nil, source: .manual, in: context)
        session.exercises[0].status = .active
        session.exercises[0].startedAt = Date(timeIntervalSince1970: 100)
        let set = ExerciseSet(setNumber: 1, weightKg: 10, reps: 10, completedAt: .now, status: .completed, exercise: session.exercises[0])
        session.exercises[0].sets.append(set)
        try context.save()

        let reloaded = WorkoutSessionFactory.inProgress(in: context)
        #expect(reloaded?.id == session.id)
        #expect(reloaded?.exercises.first?.completedSets.count == 1)
        #expect(reloaded?.endedAt == nil)
    }
}
