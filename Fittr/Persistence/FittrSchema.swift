import Foundation
import SwiftData

enum FittrSchema {
    static let models: [any PersistentModel.Type] = [
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

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(
            "Fittr",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
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
