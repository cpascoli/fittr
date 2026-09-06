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
    @State private var resumePrompt: WorkoutSession?
    @State private var weekItems: [ScheduledWorkout] = []
    @State private var nextItem: ScheduledWorkout?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let resumePrompt {
                        resumeBanner(resumePrompt)
                    }
                    nextWorkoutCard
                    thisWeekCard
                    latestProgressCard
                    consistencyCard
                }
                .padding(20)
            }
            .background(FittrTheme.background)
            .navigationTitle("Today")
            .onAppear(perform: reload)
        }
    }

    private var nextWorkoutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT WORKOUT")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let item = nextItem, let template = item.template {
                Text(template.name)
                    .font(.largeTitle.weight(.bold))
                    .accessibilityIdentifier("today.nextName")
                Text(scheduleLine(item))
                    .foregroundStyle(.secondary)
                Text("\(template.orderedExercises.count) exercises · ~\(template.estimatedDurationMinutes) min")
                    .foregroundStyle(.secondary)
                if template.type.isTrainable {
                    Button("Start Workout") {
                        start(template: template, scheduled: item)
                    }
                    .buttonStyle(GymButtonStyle())
                    .accessibilityIdentifier("today.start")
                    if template.type == .strength {
                        NavigationLink("Assign music") {
                            WorkoutMusicSetupView(template: template)
                        }
                        .buttonStyle(SecondaryGymButtonStyle())
                    }
                    HStack {
                        NavigationLink("View Workout") {
                            TemplateEditorView(template: template)
                        }
                        .buttonStyle(SecondaryGymButtonStyle())
                        Button("Reschedule") {
                            if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: item.scheduledStart) {
                                try? ScheduleService.reschedule(item, to: tomorrow, in: modelContext)
                                reload()
                            }
                        }
                        .buttonStyle(SecondaryGymButtonStyle())
                    }
                } else {
                    Text("No structured session today.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No upcoming workout.")
                    .font(.title2.weight(.semibold))
            }
        }
        .fittrCard()
    }

    private var thisWeekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THIS WEEK")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            let completed = weekItems.filter { $0.status == .completed }.count
            let planned = weekItems.filter { $0.template?.type.isTrainable == true && $0.template?.isOptionalDay == false }.count
            Text("\(completed) / \(max(planned, 1)) sessions completed")
                .font(.title3.weight(.semibold))
            let weekStart = DateHelpers.isoWeekStart(for: .now)
            let weekSessions = sessions.filter { DateHelpers.isoWeekStart(for: $0.startedAt) == weekStart }
            let trainingTime = weekSessions.reduce(0) { $0 + $1.elapsed() }
            Text("Training time \(DurationFormatting.compact(seconds: trainingTime))")
                .foregroundStyle(.secondary)
            Text("Strength sessions \(weekSessions.filter { $0.type == .strength }.count) · Cardio \(Int(weekSessions.filter { $0.type == .cardio || $0.type == .swimming }.reduce(0) { $0 + $1.elapsed() } / 60)) min")
                .foregroundStyle(.secondary)
        }
        .fittrCard()
    }

    private var latestProgressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LATEST PROGRESS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let record = records.first {
                Text("\(record.exerciseName)")
                    .font(.headline)
                Text("\(record.kind.title)")
                    .foregroundStyle(.secondary)
            } else {
                Text("Complete a workout to see progress here.")
                    .foregroundStyle(.secondary)
            }
            if weights.count >= 2 {
                let latest = weights[0].weightKg
                let previous = weights[1].weightKg
                Text("Body weight \(String(format: "%.1f", previous)) → \(String(format: "%.1f", latest)) kg")
            } else if let latest = weights.first {
                Text("Body weight \(String(format: "%.1f", latest.weightKg)) kg")
            }
        }
        .fittrCard()
    }

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONSISTENCY")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            let monthStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
            let monthItems = scheduled.filter { $0.scheduledStart >= monthStart && $0.template?.isOptionalDay == false && $0.template?.type != .rest }
            let completed = monthItems.filter { $0.status == .completed }.count
            let percent = WorkoutMath.weeklyAdherence(planned: monthItems.count, completed: completed)
            Text("\(weekItems.filter { $0.status == .completed }.count) workouts completed this week")
            Text("\(Int((percent * 100).rounded()))% adherence over last 30 days")
                .foregroundStyle(.secondary)
        }
        .fittrCard()
    }

    private func resumeBanner(_ session: WorkoutSession) -> some View {
        let current = session.orderedExercises.first { $0.status == .active }
            ?? session.orderedExercises.first { $0.status == .pending }
        return VStack(alignment: .leading, spacing: 12) {
            Text("WORKOUT IN PROGRESS")
                .font(.caption.weight(.bold))
                .foregroundStyle(FittrTheme.warning)
            Text(session.name)
                .font(.largeTitle.weight(.bold))
            Text("Started \(session.startedAt.formatted(date: .omitted, time: .shortened))")
            if let current {
                Text("Resume at \(current.exerciseName)")
                    .font(.title3.weight(.semibold))
            }
            Button("Resume workout") {
                presentedSession = session
            }
            .buttonStyle(GymButtonStyle())
            .accessibilityIdentifier("today.resume")
        }
        .fittrCard()
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FittrTheme.warning, lineWidth: 2)
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
        do {
            let session = try WorkoutSessionFactory.start(
                template: template,
                scheduled: scheduled,
                source: scheduled == nil ? .manual : .scheduled,
                in: modelContext
            )
            presentedSession = session
        } catch {
            return
        }
    }

    private func reload() {
        nextItem = try? ScheduleService.nextScheduled(in: modelContext)
        weekItems = (try? ScheduleService.weekItems(containing: .now, in: modelContext)) ?? []
        resumePrompt = WorkoutSessionFactory.inProgress(in: modelContext)
        FittrDependencies.shared.attach(context: modelContext)
    }
}
