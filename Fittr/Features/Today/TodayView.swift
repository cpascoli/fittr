import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \ScheduledWorkout.scheduledStart) private var scheduled: [ScheduledWorkout]
    @Query(sort: \BodyWeightEntry.recordedAt, order: .reverse) private var weights: [BodyWeightEntry]
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]

    @Binding var presentedSession: WorkoutSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let resumePrompt {
                        resumeBanner(resumePrompt)
                    }
                    nextWorkoutCard
                    weekCard
                    progressCard
                    if let record = records.first {
                        recordCard(record)
                    }
                }
                .padding(20)
            }
            .background(FittrTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Today")
            .onAppear { FittrDependencies.shared.attach(context: modelContext) }
        }
    }

    // MARK: - Derived state
    //
    // These read straight from @Query rather than being loaded into @State on
    // appear. The imperative version raced the first-launch seed: Today rendered
    // before SeedService finished and then never recomputed, so a fresh install
    // showed "No upcoming workout" until you switched tabs and came back.

    private var resumePrompt: WorkoutSession? {
        sessions.first { $0.endedAt == nil }
    }

    private var weekItems: [ScheduledWorkout] {
        let start = DateHelpers.isoWeekStart(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return [] }
        return scheduled.filter { $0.scheduledStart >= start && $0.scheduledStart < end }
    }

    private var nextItem: ScheduledWorkout? {
        let today = DateHelpers.startOfDay(.now)
        let upcoming = scheduled.filter { $0.status == .upcoming || $0.status == .rescheduled }
        return upcoming.first { $0.scheduledStart >= today } ?? upcoming.first
    }

    private var weekSessions: [WorkoutSession] {
        let weekStart = DateHelpers.isoWeekStart(for: .now)
        return sessions.filter { DateHelpers.isoWeekStart(for: $0.startedAt) == weekStart }
    }

    private var weekTrainingSeconds: TimeInterval {
        weekSessions.reduce(0) { $0 + $1.elapsed() }
    }

    private var plannedThisWeek: Int {
        weekItems.filter { $0.template?.type.isTrainable == true && $0.template?.isOptionalDay == false }.count
    }

    private var completedThisWeek: Int {
        weekItems.filter { $0.status == .completed }.count
    }

    private var weekMarks: [WeekDayMark] {
        let start = DateHelpers.isoWeekStart(for: .now)
        return ISOWeekday.allCases.map { day in
            let date = DateHelpers.dateOnISOWeekday(day, weekStart: start, hour: 12, minute: 0)
            let items = weekItems.filter { ISOWeekday.from(date: $0.scheduledStart) == day }
            return WeekDayMark(
                id: day.rawValue,
                letter: String(day.shortTitle.prefix(1)),
                dayNumber: Calendar.current.component(.day, from: date),
                state: state(for: items),
                isToday: DateHelpers.isSameDay(date, .now)
            )
        }
    }

    /// A day can hold more than one workout once something has been moved onto it,
    /// and the strip has one dot per day. Show the most significant thing that
    /// happened rather than whichever item the fetch happened to return first:
    /// a day where you trained reads as trained, and a day with anything still to
    /// do reads as upcoming.
    private func state(for items: [ScheduledWorkout]) -> WeekDayMark.State {
        if items.isEmpty { return .empty }
        if items.contains(where: { $0.status == .completed }) { return .completed }
        let pending = items.filter { $0.status == .upcoming || $0.status == .rescheduled }
        if pending.contains(where: { $0.template?.type != .rest }) { return .upcoming }
        if !pending.isEmpty { return .rest }
        return .skipped
    }

    private var adherence: Double {
        let monthStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let items = scheduled.filter {
            $0.scheduledStart >= monthStart
                && $0.scheduledStart <= .now
                && $0.template?.isOptionalDay == false
                && $0.template?.type != .rest
        }
        let completed = items.filter { $0.status == .completed }.count
        return WorkoutMath.weeklyAdherence(planned: items.count, completed: completed)
    }

    // MARK: - Cards

    private var nextWorkoutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item = nextItem, let template = item.template {
                HStack {
                    SectionLabel(text: scheduleLine(item), color: FittrTheme.accent)
                    Spacer()
                    if template.type.isTrainable {
                        Text(template.type.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(template.name)
                    .font(.largeTitle.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .accessibilityIdentifier("today.nextName")

                if template.type.isTrainable {
                    HStack(spacing: 8) {
                        StatusChip(text: "\(template.orderedExercises.count) exercises")
                        StatusChip(text: "~\(template.estimatedDurationMinutes) min")
                    }
                    Button("Start Workout") {
                        start(template: template, scheduled: item)
                    }
                    .buttonStyle(GymButtonStyle())
                    .accessibilityIdentifier("today.start")
                    HStack(spacing: 8) {
                        NavigationLink("View") {
                            TemplateEditorView(template: template, scheduled: item)
                        }
                        .buttonStyle(SecondaryGymButtonStyle(compact: true))
                        if template.type == .strength {
                            NavigationLink("Music") {
                                WorkoutMusicSetupView(template: template)
                            }
                            .buttonStyle(SecondaryGymButtonStyle(compact: true))
                        }
                        Button("Tomorrow") {
                            if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: item.scheduledStart) {
                                try? ScheduleService.reschedule(item, to: tomorrow, in: modelContext)
                            }
                        }
                        .buttonStyle(SecondaryGymButtonStyle(compact: true))
                    }
                } else {
                    Text("Nothing structured today. Rest counts as training.")
                        .foregroundStyle(.secondary)
                }
            } else {
                SectionLabel(text: "Next workout")
                Text("No upcoming workout")
                    .font(.title2.weight(.semibold))
                Text("Add one from the Plan tab.")
                    .foregroundStyle(.secondary)
            }
        }
        .fittrCard(nextItem?.template?.type.isTrainable == true ? .hero : .standard)
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: "This week")
                Spacer()
                if plannedThisWeek > 0 {
                    Text("\(completedThisWeek) of \(plannedThisWeek) done")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            WeekStrip(days: weekMarks)
            Divider().overlay(FittrTheme.hairline)
            HStack(spacing: 12) {
                StatBlock(
                    value: weekTrainingSeconds > 0
                        ? DurationFormatting.compact(seconds: weekTrainingSeconds)
                        : "—",
                    label: "Training time"
                )
                StatBlock(
                    value: "\(weekSessions.filter { $0.type == .strength }.count)",
                    label: "Strength"
                )
                StatBlock(
                    value: "\(Int(weekSessions.filter { $0.type == .cardio || $0.type == .swimming }.reduce(0) { $0 + $1.elapsed() } / 60))m",
                    label: "Cardio"
                )
            }
        }
        .fittrCard()
    }

    private var progressCard: some View {
        HStack(spacing: 18) {
            ProgressRing(progress: adherence, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Adherence")
                Text("Last 30 days")
                    .font(.headline)
                if let latest = weights.first, let profile = profiles.first {
                    let delta = latest.weightKg - profile.startingWeightKg
                    HStack(spacing: 6) {
                        // Only claim a direction once there is one. At zero
                        // change an arrow plus "+0.0" reads as a broken stat.
                        if abs(delta) >= 0.05 {
                            Image(systemName: delta < 0 ? "arrow.down.right" : "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(delta < 0 ? FittrTheme.success : FittrTheme.warning)
                            Text("Body weight \(NumberFormatting.weight(latest.weightKg, units: .metric)) · \(NumberFormatting.signedWeight(delta, units: .metric))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        } else {
                            Text("Body weight \(NumberFormatting.weight(latest.weightKg, units: .metric))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .fittrCard()
    }

    private func recordCard(_ record: PersonalRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(FittrTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Latest record")
                Text(record.exerciseName)
                    .font(.headline)
                Text(record.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .fittrCard(.subtle)
    }

    private func resumeBanner(_ session: WorkoutSession) -> some View {
        let current = session.orderedExercises.first { $0.status == .active }
            ?? session.orderedExercises.first { $0.status == .pending }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(FittrTheme.warning)
                    .frame(width: 8, height: 8)
                SectionLabel(text: "Workout in progress", color: FittrTheme.warning)
            }
            Text(session.name)
                .font(.title.weight(.bold))
            Text("Started \(session.startedAt.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let current {
                Text("Resume at \(current.exerciseName)")
                    .font(.headline)
            }
            Button("Resume workout") {
                presentedSession = session
            }
            .buttonStyle(GymButtonStyle())
            .accessibilityIdentifier("today.resume")
        }
        .fittrCard()
        .overlay(
            RoundedRectangle(cornerRadius: FittrTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(FittrTheme.warning, lineWidth: 2)
        )
    }

    private func scheduleLine(_ item: ScheduledWorkout) -> String {
        if DateHelpers.isSameDay(item.scheduledStart, .now) {
            return "Today"
        }
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: DateHelpers.startOfDay(.now)),
           DateHelpers.isSameDay(item.scheduledStart, tomorrow) {
            return "Tomorrow"
        }
        return item.scheduledStart.formatted(date: .abbreviated, time: .omitted)
    }

    private func start(template: WorkoutTemplate, scheduled: ScheduledWorkout?) {
        if let inProgress = WorkoutSessionFactory.inProgress(in: modelContext) {
            presentedSession = inProgress
            return
        }
        presentedSession = try? WorkoutSessionFactory.start(
            template: template,
            scheduled: scheduled,
            source: scheduled == nil ? .manual : .scheduled,
            in: modelContext
        )
    }
}
