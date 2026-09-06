import Charts
import SwiftData
import SwiftUI

struct AnalyticsView: View {
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query(sort: \BodyWeightEntry.recordedAt) private var weights: [BodyWeightEntry]
    @Query(sort: \ScheduledWorkout.scheduledStart) private var scheduled: [ScheduledWorkout]
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var range: AnalyticsRange = .fourWeeks
    @State private var weightRange: BodyWeightChartRange = .threeMonths
    @State private var selectedExerciseId: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Range", selection: $range) {
                        ForEach(AnalyticsRange.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    strengthSection
                    cardioSection
                    bodySection
                    adherenceSection
                    recordsSection
                }
                .padding(20)
            }
            .background(FittrTheme.background)
            .navigationTitle("Analytics")
        }
    }

    private var filteredSessions: [WorkoutSession] {
        sessions.filter { session in
            guard session.endedAt != nil else { return false }
            if let start = range.startDate {
                return session.startedAt >= start
            }
            return true
        }
    }

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STRENGTH")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            let strength = filteredSessions.filter { $0.type == .strength }
            MetricTile(title: "Weekly volume", value: NumberFormatting.volume(currentWeeklyVolume, units: .metric))
            chart("Training volume", points: volumePoints(strength))
            chart("Sets / week", points: weeklyCount(strength, value: { Double($0.completedSetCount) }))
            if let exerciseId = selectedExerciseId ?? strengthExercises.first?.id {
                Picker("Exercise", selection: Binding(
                    get: { selectedExerciseId ?? exerciseId },
                    set: { selectedExerciseId = $0 }
                )) {
                    ForEach(strengthExercises, id: \.id) { exercise in
                        Text(exercise.name).tag(exercise.id)
                    }
                }
                chart("Weight over time", points: weightPoints(for: exerciseId))
                chart("Estimated 1RM (Epley)", points: epleyPoints(for: exerciseId))
                Text("Estimated 1RM uses Epley: weight × (1 + reps / 30), only for 1–12 reps. It is an estimate.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cardioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CARDIO & SWIM")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            let cardio = filteredSessions.filter { $0.type == .cardio || $0.type == .swimming }
            if cardio.isEmpty {
                Text("No cardio or swim sessions in this range.")
                    .foregroundStyle(.secondary)
            } else {
                chart("Minutes / week", points: weeklyCount(cardio, value: { $0.elapsed() / 60 }))
                chart("Distance (km)", points: cardio.compactMap { session in
                    let km = session.cardio?.distanceKm ?? ((session.swim?.distanceMeters ?? 0) / 1000)
                    guard km > 0 else { return nil }
                    return ChartPoint(date: session.startedAt, value: km)
                })
            }
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BODY")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Picker("Weight range", selection: $weightRange) {
                ForEach(BodyWeightChartRange.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            let series = filteredWeights
            if series.isEmpty {
                Text("No body-weight entries yet.")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(series, id: \.id) { entry in
                        PointMark(x: .value("Date", entry.recordedAt), y: .value("kg", entry.weightKg))
                    }
                    ForEach(WorkoutMath.movingAverage(values: series.map { DatedValue(date: $0.recordedAt, value: $0.weightKg) }), id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Average", point.value))
                            .foregroundStyle(FittrTheme.accent)
                    }
                }
                .frame(height: 180)
                if let profile = profiles.first, let latest = series.last {
                    Text("Change from start: \(String(format: "%+.1f", latest.weightKg - profile.startingWeightKg)) kg")
                    Text("Target \(String(format: "%.0f", profile.targetWeightKg)) kg is a personal target, not a predicted date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fittrCard()
    }

    private var adherenceSection: some View {
        let stats = AnalyticsEngine.adherence(planned: scheduled.filter { $0.template?.isOptionalDay == false })
        return VStack(alignment: .leading, spacing: 8) {
            Text("ADHERENCE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text("Planned \(stats.planned) · Completed \(stats.completed) · Skipped \(stats.skipped)")
            Text("\(Int((stats.percent * 100).rounded()))% completion")
                .font(.title3.weight(.semibold))
        }
        .fittrCard()
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PERSONAL RECORDS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if records.isEmpty {
                Text("PRs appear after meaningful bests, not after every session.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records.prefix(8), id: \.id) { record in
                    Text("\(record.kind.title) · \(record.exerciseName)")
                }
            }
        }
        .fittrCard()
    }

    private var strengthExercises: [ExerciseDefinition] {
        let ids = Set(filteredSessions.flatMap(\.exercises).map(\.exerciseId))
        // Reconstruct lightweight identities from sessions if needed.
        return filteredSessions
            .flatMap(\.orderedExercises)
            .reduce(into: [UUID: ExerciseDefinitionStub]()) { partial, exercise in
                partial[exercise.exerciseId] = ExerciseDefinitionStub(id: exercise.exerciseId, name: exercise.exerciseName)
            }
            .values
            .sorted { $0.name < $1.name }
            .map { stub in
                // The picker only needs id + name; fetch from first matching definition if present.
                ExerciseDefinition(
                    id: stub.id,
                    name: stub.name,
                    slug: stub.name.lowercased(),
                    category: .strength,
                    primaryMuscleGroups: [],
                    equipment: .none,
                    setupInstructions: "",
                    movementInstructions: "",
                    breathingCue: "",
                    coachingCues: [],
                    commonMistakes: []
                )
            }
            .filter { ids.contains($0.id) }
    }

    private var currentWeeklyVolume: Double {
        let start = DateHelpers.isoWeekStart(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? .now
        return AnalyticsEngine.weeklyVolume(sessions: sessions, in: DateInterval(start: start, end: end))
    }

    private var filteredWeights: [BodyWeightEntry] {
        weights.filter { entry in
            if let start = weightRange.startDate {
                return entry.recordedAt >= start
            }
            return true
        }
    }

    private func volumePoints(_ sessions: [WorkoutSession]) -> [ChartPoint] {
        sessions.map { ChartPoint(date: $0.startedAt, value: $0.trainingVolumeKg) }
    }

    private func weeklyCount(_ sessions: [WorkoutSession], value: (WorkoutSession) -> Double) -> [ChartPoint] {
        let grouped = Dictionary(grouping: sessions) { DateHelpers.isoWeekStart(for: $0.startedAt) }
        return grouped.keys.sorted().map { week in
            ChartPoint(date: week, value: (grouped[week] ?? []).reduce(0) { $0 + value($1) })
        }
    }

    private func weightPoints(for exerciseId: UUID) -> [ChartPoint] {
        filteredSessions.compactMap { session in
            let sets = session.orderedExercises.first { $0.exerciseId == exerciseId }?.completedSets ?? []
            guard let weight = sets.compactMap(\.weightKg).max() else { return nil }
            return ChartPoint(date: session.startedAt, value: weight)
        }
    }

    private func epleyPoints(for exerciseId: UUID) -> [ChartPoint] {
        filteredSessions.compactMap { session in
            let sets = session.orderedExercises.first { $0.exerciseId == exerciseId }?.completedSets ?? []
            let estimates = sets.compactMap { set -> Double? in
                guard let weight = set.weightKg, let reps = set.reps else { return nil }
                return WorkoutMath.estimatedOneRepMaxKg(weightKg: weight, reps: reps)
            }
            guard let best = estimates.max() else { return nil }
            return ChartPoint(date: session.startedAt, value: best)
        }
    }

    private func chart(_ title: String, points: [ChartPoint]) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            if points.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value(title, point.value))
                    PointMark(x: .value("Date", point.date), y: .value(title, point.value))
                }
                .frame(height: 160)
            }
        }
        .fittrCard()
    }
}

private struct ExerciseDefinitionStub {
    var id: UUID
    var name: String
}
