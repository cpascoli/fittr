import Foundation

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: "Metric (kg, km)"
        case .imperial: "Imperial (lb, mi)"
        }
    }
}

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case strength
    case cardio
    case swimming
    case mobility
    case recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: "Strength"
        case .cardio: "Cardio"
        case .swimming: "Swimming"
        case .mobility: "Mobility"
        case .recovery: "Recovery"
        }
    }
}

enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case strength
    case cardio
    case swimming
    case recovery
    case rest
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: "Strength"
        case .cardio: "Cardio"
        case .swimming: "Swimming"
        case .recovery: "Recovery"
        case .rest: "Rest"
        case .mixed: "Mixed"
        }
    }

    var isTrainable: Bool {
        switch self {
        case .strength, .cardio, .swimming, .mixed, .recovery: true
        case .rest: false
        }
    }
}

enum TrackingMode: String, Codable, CaseIterable, Identifiable {
    case repsWeight
    case repsOnly
    case duration
    case distanceDuration
    case lapsDuration
    case freeform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .repsWeight: "Reps + weight"
        case .repsOnly: "Reps"
        case .duration: "Duration"
        case .distanceDuration: "Distance + duration"
        case .lapsDuration: "Laps + duration"
        case .freeform: "Freeform"
        }
    }

    var usesWeight: Bool {
        self == .repsWeight
    }

    var usesReps: Bool {
        switch self {
        case .repsWeight, .repsOnly: true
        case .duration, .distanceDuration, .lapsDuration, .freeform: false
        }
    }
}

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case quads
    case hamstrings
    case glutes
    case calves
    case chest
    case back
    case lats
    case shoulders
    case biceps
    case triceps
    case core
    case fullBody
    case cardio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .chest: "Chest"
        case .back: "Back"
        case .lats: "Lats"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .core: "Core"
        case .fullBody: "Full body"
        case .cardio: "Cardio"
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case dumbbell
    case kettlebell
    case barbell
    case machine
    case cable
    case bodyweight
    case bike
    case treadmill
    case pool
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dumbbell: "Dumbbell"
        case .kettlebell: "Kettlebell"
        case .barbell: "Barbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .bodyweight: "Bodyweight"
        case .bike: "Bike"
        case .treadmill: "Treadmill"
        case .pool: "Pool"
        case .none: "None"
        }
    }
}

enum Laterality: String, Codable, CaseIterable, Identifiable {
    case bilateral
    case unilateral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bilateral: "Bilateral"
        case .unilateral: "Unilateral"
        }
    }
}

enum SetStatus: String, Codable, CaseIterable {
    case pending
    case completed
    case skipped
}

enum ExerciseSessionStatus: String, Codable, CaseIterable {
    case pending
    case active
    case completed
    case skipped
}

enum ScheduledStatus: String, Codable, CaseIterable, Identifiable {
    case upcoming
    case completed
    case skipped
    case rescheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        case .skipped: "Skipped"
        case .rescheduled: "Rescheduled"
        }
    }
}

enum WorkoutSource: String, Codable {
    case scheduled
    case manual
}

enum MusicScope: String, Codable {
    case workout
    case exercise
}

enum AfterTrackBehavior: String, Codable, CaseIterable, Identifiable {
    case continueCurrent
    case returnToPlaylist
    case doNothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueCurrent: "Continue current music"
        case .returnToPlaylist: "Return to workout playlist"
        case .doNothing: "Do nothing"
        }
    }
}

enum PersonalRecordKind: String, Codable, CaseIterable, Identifiable {
    case heaviestWeight
    case mostRepsAtWeight
    case highestSessionVolume
    case longestPlank
    case longestCardio
    case longestSwim
    case fastestPace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heaviestWeight: "Heaviest weight"
        case .mostRepsAtWeight: "Most reps at weight"
        case .highestSessionVolume: "Highest session volume"
        case .longestPlank: "Longest plank"
        case .longestCardio: "Longest cardio"
        case .longestSwim: "Longest swim"
        case .fastestPace: "Fastest pace"
        }
    }
}

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case fourWeeks
    case threeMonths
    case sixMonths
    case oneYear
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fourWeeks: "4 weeks"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .oneYear: "1 year"
        case .all: "All"
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        let now = Date.now
        switch self {
        case .fourWeeks:
            return calendar.date(byAdding: .day, value: -28, to: now)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: now)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: now)
        case .all:
            return nil
        }
    }
}

enum BodyWeightChartRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth: "1 month"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .oneYear: "1 year"
        case .all: "All"
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        let now = Date.now
        switch self {
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: now)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: now)
        case .all:
            return nil
        }
    }
}

/// ISO-8601 weekday: Monday = 1 … Sunday = 7.
enum ISOWeekday: Int, Codable, CaseIterable, Identifiable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    var title: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    static func from(date: Date, calendar: Calendar = .current) -> ISOWeekday {
        let appleWeekday = calendar.component(.weekday, from: date)
        // Apple: Sunday = 1 … Saturday = 7. Convert to ISO.
        let iso = appleWeekday == 1 ? 7 : appleWeekday - 1
        return ISOWeekday(rawValue: iso) ?? .monday
    }
}
