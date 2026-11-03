import Charts
import SwiftData
import SwiftUI

struct AnalyticsView: View {
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query(sort: \BodyWeightEntry.recordedAt) private var weights: [BodyWeightEntry]
    @Query(sort: \ScheduledWorkout.scheduledStart) private var scheduled: [ScheduledWorkout]
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \DailyActivity.day) private var activity: [DailyActivity]
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

                    bodySection
                    strengthSection
                    cardioSection
                    activitySection
                    adherenceSection
                    recordsSection
                }
                .padding(20)
            }
            .background(FittrTheme.backgroundGradient.ignoresSafeArea())
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
            SectionLabel(text: "Strength")
            let strength = filteredSessions.filter { $0.type == .strength }
            MetricTile(title: "Weekly volume", value: NumberFormatting.volume(currentWeeklyVolume, units: units))
            chart("Training volume", points: volumePoints(strength), format: { NumberFormatting.volume($0, units: units) })
            chart(
                "Sets / week",
                points: weeklyCount(strength, value: { Double($0.completedSetCount) }),
                format: { "\(Int($0.rounded())) sets" },
                style: .bar
            )
            if let exerciseId = selectedExerciseId ?? strengthExercises.first?.id {
                Picker("Exercise", selection: Binding(
                    get: { selectedExerciseId ?? exerciseId },
                    set: { selectedExerciseId = $0 }
                )) {
                    ForEach(strengthExercises, id: \.id) { exercise in
                        Text(exercise.name).tag(exercise.id)
                    }
                }
                chart("Weight over time", points: weightPoints(for: exerciseId), format: { NumberFormatting.weight($0, units: units) })
                chart("Estimated 1RM", points: epleyPoints(for: exerciseId), format: { NumberFormatting.weight($0, units: units) })
                Text("Estimated 1RM uses Epley: weight × (1 + reps / 30), only for 1–12 reps. It is an estimate.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cardioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Cardio & swim")
            let cardio = filteredSessions.filter { $0.type == .cardio || $0.type == .swimming }
            if cardio.isEmpty {
                EmptyHint(text: "No cardio or swim sessions in this range", systemImage: "figure.pool.swim")
                    .fittrCard(.subtle)
            } else {
                chart(
                    "Minutes / week",
                    points: weeklyCount(cardio, value: { $0.elapsed() / 60 }),
                    format: { "\(Int($0.rounded())) min" },
                    style: .bar
                )
                chart("Distance", points: cardio.compactMap { session in
                    let km = session.cardio?.distanceKm ?? ((session.swim?.distanceMeters ?? 0) / 1000)
                    guard km > 0 else { return nil }
                    return ChartPoint(date: session.startedAt, value: km)
                }, format: { String(format: "%.1f km", $0) })
            }
        }
    }

    /// Steps and distance Health counted, by week. Walks that were never logged
    /// as a workout show up here, which is the point of importing them.
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Daily activity")
            let days = activity.filter { day in
                guard let start = range.startDate else { return true }
                return day.day >= start
            }
            if days.isEmpty {
                EmptyHint(text: "No step data yet. Turn on the Health import in Settings.", systemImage: "figure.walk")
                    .fittrCard(.subtle)
            } else {
                let byWeek = Dictionary(grouping: days) { DateHelpers.isoWeekStart(for: $0.day) }
                let weeks = byWeek.keys.sorted()
                chart(
                    "Steps / week",
                    points: weeks.map { week in
                        ChartPoint(date: week, value: Double((byWeek[week] ?? []).reduce(0) { $0 + $1.steps }))
                    },
                    format: { Int($0.rounded()).formatted() },
                    style: .bar
                )
                chart(
                    "Walking distance / week",
                    points: weeks.map { week in
                        ChartPoint(date: week, value: (byWeek[week] ?? []).reduce(0) { $0 + $1.distanceKm })
                    },
                    format: { String(format: "%.1f km", $0) },
                    style: .bar
                )
                let average = Double(days.reduce(0) { $0 + $1.steps }) / Double(days.count)
                Text("Average \(Int(average.rounded()).formatted()) steps a day over \(days.count) days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Body")
            Picker("Weight range", selection: $weightRange) {
                ForEach(BodyWeightChartRange.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            let series = filteredWeights
            if series.isEmpty {
                EmptyHint(text: "No body-weight entries yet", systemImage: "scalemass")
            } else {
                let axisDomain = weightAxisDomain(for: series)
                Chart {
                    if let target = profiles.first?.targetWeightKg {
                        RuleMark(y: .value("Target", target))
                            .foregroundStyle(FittrTheme.success.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Target \(NumberFormatting.weight(target, units: .metric))")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(FittrTheme.success)
                            }
                    }
                    ForEach(series, id: \.id) { entry in
                        PointMark(
                            x: .value("Date", entry.recordedAt),
                            y: .value("kg", entry.weightKg)
                        )
                        .foregroundStyle(FittrTheme.accent.opacity(0.85))
                        .symbolSize(40)
                    }
                    ForEach(WorkoutMath.movingAverage(values: series.map { DatedValue(date: $0.recordedAt, value: $0.weightKg) }), id: \.date) { point in
                        // Filled down to the bottom of the axis, not to zero. The
                        // axis starts near the target, so a fill to zero ran out of
                        // the chart and over the cards beneath it.
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Floor", axisDomain.lowerBound),
                            yEnd: .value("Average", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [FittrTheme.accent.opacity(0.28), FittrTheme.accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Average", point.value)
                        )
                        .foregroundStyle(FittrTheme.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(FittrTheme.hairline)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                }
                // Anchored just under the goal and just over the heaviest entry,
                // not at zero. From zero, a 3 kg drop out of 97 is a flat line.
                .chartYScale(domain: axisDomain)
                // Belt and braces: nothing drawn in the plot can leave it.
                .chartPlotStyle { $0.clipped() }
                .frame(height: 200)
                if let profile = profiles.first, let latest = series.last {
                    Text("Change from start: \(NumberFormatting.signedWeight(latest.weightKg - profile.startingWeightKg, units: .metric))")
                    Text("Target \(NumberFormatting.weight(profile.targetWeightKg, units: .metric)) is a personal target, not a predicted date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fittrCard()
    }

    private var adherenceSection: some View {
        let stats = AnalyticsEngine.adherence(planned: scheduled.filter { $0.template?.isOptionalDay == false })
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Adherence")
                Text("Planned \(stats.planned) · Completed \(stats.completed) · Skipped \(stats.skipped)")
                Text("\(Int((stats.percent * 100).rounded()))% completion")
                    .font(.title3.weight(.semibold))
            }
            .fittrCard()
            chart("Completed each week", points: weeklyAdherencePoints(), format: { "\(Int($0.rounded()))%" }, style: .bar)
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Personal records")
            if records.isEmpty {
                EmptyHint(text: "PRs appear after meaningful bests, not every session", systemImage: "trophy")
            } else {
                ForEach(records.prefix(8), id: \.id) { record in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.exerciseName)
                                .font(.headline)
                            Text(record.kind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(record.achievedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 8)
                        Text(RecordFormatting.detail(record, units: units))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(FittrTheme.accent)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .fittrCard()
    }

    private var units: UnitSystem { profiles.first?.liftingUnits ?? .metric }


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

    /// Runs from the nearest 5 kg below the goal (or below the lightest entry,
    /// if that is lower) to the nearest 5 kg above the heaviest, so the whole
    /// journey from start to target is on screen and a kilo is visibly a kilo.
    func weightAxisDomain(for series: [BodyWeightEntry]) -> ClosedRange<Double> {
        let weights = series.map(\.weightKg)
        let target = profiles.first?.targetWeightKg ?? weights.min() ?? 0
        let start = profiles.first?.startingWeightKg ?? weights.max() ?? 0
        let lowest = min(target, weights.min() ?? target)
        let highest = max(start, weights.max() ?? start)
        let lower = (floor((lowest - 1) / 5) * 5)
        let upper = (ceil((highest + 1) / 5) * 5)
        return lower...max(upper, lower + 5)
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

    private func weeklyAdherencePoints() -> [ChartPoint] {
        let relevant = scheduled.filter { item in
            guard item.template?.isOptionalDay == false, item.template?.type.isTrainable == true else { return false }
            guard item.scheduledStart <= .now else { return false }
            if let start = range.startDate, item.scheduledStart < start { return false }
            return true
        }
        let grouped = Dictionary(grouping: relevant) { DateHelpers.isoWeekStart(for: $0.scheduledStart) }
        return grouped.keys.sorted().map { week in
            let items = grouped[week] ?? []
            let done = items.filter { $0.status == .completed }.count
            let percent = items.isEmpty ? 0 : (Double(done) / Double(items.count)) * 100
            return ChartPoint(date: week, value: percent)
        }
    }

    private func chart(
        _ title: String,
        points: [ChartPoint],
        format: @escaping (Double) -> String,
        style: TrendChart.Style = .line
    ) -> some View {
        TrendChart(title: title, points: points, format: format, style: style)
    }
}

/// A chart with the latest value and how far it has moved, so a curve is readable
/// without tracing it back to the axis.
private struct TrendChart: View {
    let title: String
    let points: [ChartPoint]
    let format: (Double) -> String
    var style: Style = .line

    enum Style {
        case line
        case bar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer(minLength: 8)
                if let last = points.last {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(format(last.value))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if let delta {
                            Text(delta.text)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(delta.rose ? FittrTheme.success : FittrTheme.warning)
                        }
                    }
                }
            }
            if points.isEmpty {
                EmptyHint(text: "Not enough data yet")
            } else {
                chart
                    .frame(height: 168)
            }
        }
        .fittrCard()
    }

    @ViewBuilder
    private var chart: some View {
        switch style {
        case .line:
            Chart(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [FittrTheme.accent.opacity(0.32), FittrTheme.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(FittrTheme.accent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                if point.id == points.last?.id {
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(FittrTheme.accent)
                    .symbolSize(60)
                }
            }
            .chartXAxis { axis }
            .chartYAxis { yAxis }
            .chartLegend(.hidden)
            .chartPlotStyle { $0.clipped() }
        case .bar:
            Chart(points) { point in
                BarMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(FittrTheme.accent.gradient)
                .cornerRadius(4)
            }
            .chartXAxis { axis }
            .chartYAxis { yAxis }
            .chartLegend(.hidden)
        }
    }

    private var axis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine().foregroundStyle(FittrTheme.hairline)
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                .foregroundStyle(.secondary)
        }
    }

    private var yAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine().foregroundStyle(FittrTheme.hairline)
            AxisValueLabel().foregroundStyle(.secondary)
        }
    }

    private var delta: (text: String, rose: Bool)? {
        guard points.count >= 2, let first = points.first?.value, let last = points.last?.value else { return nil }
        let change = last - first
        guard abs(change) >= 0.05 else { return nil }
        let magnitude = format(abs(change))
        if change > 0 {
            return ("+\(magnitude)", true)
        }
        return ("−\(magnitude)", false)
    }
}

private struct ExerciseDefinitionStub {
    var id: UUID
    var name: String
}
