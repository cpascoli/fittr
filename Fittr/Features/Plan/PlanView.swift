import SwiftData
import SwiftUI

struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutTemplate.weekdayRaw) private var templates: [WorkoutTemplate]
    @State private var weekItems: [ScheduledWorkout] = []
    @State private var editing: ScheduledWorkout?
    @State private var duplicating: WorkoutTemplate?
    @State private var schedulingDay: DayToSchedule?

    var body: some View {
        NavigationStack {
            List {
                Section("This week") {
                    ForEach(weekRows, id: \.id) { row in
                        weekRowLink(row)
                            // Full swipe is off: the first trailing action is Skip,
                            // and a stray flick should not quietly write off a day.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                manageActions(for: row)
                            }
                            .swipeActions(edge: .leading) {
                                moveActions(for: row)
                            }
                    }
                }
                Section("Templates") {
                    ForEach(templates, id: \.id) { template in
                        NavigationLink {
                            TemplateEditorView(template: template)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                Text(templateSubtitle(template))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Duplicate") { duplicating = template }
                                .tint(FittrTheme.accent)
                        }
                    }
                }
            }
            .navigationTitle("Plan")
            .onAppear(perform: reload)
            .sheet(item: $editing) { item in
                ScheduleEditorView(item: item) {
                    reload()
                }
            }
            .sheet(item: $duplicating) { template in
                DuplicateTemplateSheet(template: template)
            }
            .sheet(item: $schedulingDay) { day in
                ScheduleDaySheet(day: day.date, templates: templates) { template in
                    _ = try? ScheduleService.schedule(template: template, on: day.date, in: modelContext)
                    reload()
                }
            }
        }
    }

    private func templateSubtitle(_ template: WorkoutTemplate) -> String {
        var parts = [
            template.weekday.title,
            template.type.title,
            "\(template.orderedExercises.count) exercises",
        ]
        if let hour = template.preferredHour, let minute = template.preferredMinute {
            parts.append(String(format: "%d:%02d", hour, minute))
        }
        return parts.joined(separator: " · ")
    }

    /// One row per scheduled workout rather than one row per day. A day can hold
    /// several once something has been moved onto it, and collapsing them to
    /// `first` used to leave the loser invisible — and therefore impossible to
    /// reschedule, skip or remove, since every one of those lives on its row.
    private var weekRows: [WeekRow] {
        let start = DateHelpers.isoWeekStart(for: .now)
        return ISOWeekday.allCases.flatMap { day -> [WeekRow] in
            let date = DateHelpers.dateOnISOWeekday(day, weekStart: start, hour: 12, minute: 0)
            let items = weekItems
                .filter { ISOWeekday.from(date: $0.scheduledStart) == day }
                .sorted { $0.scheduledStart < $1.scheduledStart }
            guard !items.isEmpty else {
                return [WeekRow(id: "\(day.rawValue).empty", weekday: day, date: date, scheduled: nil)]
            }
            return items.map { item in
                WeekRow(id: "\(day.rawValue).\(item.id)", weekday: day, date: date, scheduled: item)
            }
        }
    }

    @ViewBuilder
    private func manageActions(for row: WeekRow) -> some View {
        if let item = row.scheduled {
            if item.status == .upcoming {
                Button("Skip") {
                    try? ScheduleService.markSkipped(item, in: modelContext)
                    reload()
                }
                .tint(.orange)
            }
            Button("Reschedule") { editing = item }
                .tint(FittrTheme.accent)
            if item.completedSession == nil {
                Button("Remove", role: .destructive) {
                    try? ScheduleService.remove(item, in: modelContext)
                    reload()
                }
            }
        }
    }

    /// Swiping right means "bring this here" or "put it back" — the two one-tap
    /// moves worth having without opening the date picker.
    @ViewBuilder
    private func moveActions(for row: WeekRow) -> some View {
        if let item = row.scheduled, item.status != .completed {
            if item.rescheduledFrom != nil {
                Button("Undo move") {
                    try? ScheduleService.undoReschedule(item, in: modelContext)
                    reload()
                }
                .tint(.blue)
            } else if !DateHelpers.isSameDay(item.scheduledStart, .now) {
                Button("Today") {
                    try? ScheduleService.moveToToday(item, in: modelContext)
                    reload()
                }
                .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private func weekRow(_ row: WeekRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(row.weekday.shortTitle) \(Calendar.current.component(.day, from: row.date))")
                    .font(.headline)
                if let item = row.scheduled, let template = item.template {
                    HStack {
                        if item.status == .completed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(FittrTheme.success)
                        }
                        Text(template.name)
                        if let session = item.completedSession {
                            Text(DurationFormatting.compact(seconds: session.elapsed()))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(statusLine(item))
                        .font(.caption)
                        .foregroundStyle(statusColor(item.status))
                } else {
                    Text("Unscheduled")
                        .foregroundStyle(.secondary)
                    Text("Tap to add a workout")
                        .font(.caption)
                        .foregroundStyle(FittrTheme.accent)
                }
            }
            Spacer()
        }
        .accessibilityIdentifier("plan.day.\(row.id)")
    }

    /// Says where a moved workout came from. "Rescheduled" on its own leaves you
    /// with no idea what to undo to.
    private func statusLine(_ item: ScheduledWorkout) -> String {
        let time = item.scheduledStart.formatted(date: .omitted, time: .shortened)
        guard let origin = item.rescheduledFrom else {
            return "\(item.status.title) · \(time)"
        }
        let day = origin.formatted(.dateTime.weekday(.abbreviated).day())
        return "Moved from \(day) · \(time)"
    }

    /// Tapping a day opens the workout: the logged session if it already happened,
    /// otherwise the workout itself, ready to start. Rescheduling is the rarer
    /// intent and lives on a swipe — it used to own the row tap, where people
    /// reasonably expect "open this".
    @ViewBuilder
    private func weekRowLink(_ row: WeekRow) -> some View {
        if let session = row.scheduled?.completedSession {
            NavigationLink {
                WorkoutDetailView(session: session)
            } label: {
                weekRow(row)
            }
        } else if let item = row.scheduled, let template = item.template, template.type.isTrainable {
            NavigationLink {
                TemplateEditorView(template: template, scheduled: item)
            } label: {
                weekRow(row)
            }
        } else if row.scheduled == nil {
            Button {
                schedulingDay = DayToSchedule(date: row.date)
            } label: {
                weekRow(row)
            }
            .buttonStyle(.plain)
        } else {
            weekRow(row)
        }
    }

    private func statusColor(_ status: ScheduledStatus) -> Color {
        switch status {
        case .upcoming: FittrTheme.accent
        case .completed: FittrTheme.success
        case .skipped: FittrTheme.warning
        case .rescheduled: .blue
        }
    }

    private func reload() {
        weekItems = (try? ScheduleService.weekItems(containing: .now, in: modelContext)) ?? []
    }
}

private struct WeekRow: Identifiable {
    var id: String
    var weekday: ISOWeekday
    var date: Date
    var scheduled: ScheduledWorkout?
}

private struct DayToSchedule: Identifiable {
    var date: Date
    var id: Date { date }
}

/// Puts a workout on a day that has none. Without this an empty day was inert
/// text, so a day vacated by a reschedule could only be refilled by the seeder.
private struct ScheduleDaySheet: View {
    let day: Date
    let templates: [WorkoutTemplate]
    var onPick: (WorkoutTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(templates, id: \.id) { template in
                Button {
                    onPick(template)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .foregroundStyle(.primary)
                        Text("\(template.type.title) · \(template.orderedExercises.count) exercises · ~\(template.estimatedDurationMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct DuplicateTemplateSheet: View {
    @Bindable var template: WorkoutTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var weekday: ISOWeekday

    init(template: WorkoutTemplate) {
        self.template = template
        _name = State(initialValue: "\(template.name) copy")
        _weekday = State(initialValue: template.weekday)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Weekday", selection: $weekday) {
                    ForEach(ISOWeekday.allCases) { day in
                        Text(day.title).tag(day)
                    }
                }
            }
            .navigationTitle("Duplicate workout")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Duplicate") {
                        _ = try? TemplateService.duplicate(template, name: name, weekday: weekday, in: modelContext)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

extension ScheduledWorkout: Identifiable {}
