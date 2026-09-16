import SwiftData
import SwiftUI

struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutTemplate.weekdayRaw) private var templates: [WorkoutTemplate]
    @State private var weekItems: [ScheduledWorkout] = []
    @State private var editing: ScheduledWorkout?
    @State private var duplicating: WorkoutTemplate?

    var body: some View {
        NavigationStack {
            List {
                Section("This week") {
                    ForEach(weekRows, id: \.id) { row in
                        weekRowLink(row)
                            .swipeActions {
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
                                }
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

    private var weekRows: [WeekRow] {
        let start = DateHelpers.isoWeekStart(for: .now)
        return ISOWeekday.allCases.map { day in
            let date = DateHelpers.dateOnISOWeekday(day, weekStart: start, hour: 12, minute: 0)
            let item = weekItems.first { ISOWeekday.from(date: $0.scheduledStart) == day }
            return WeekRow(id: day.rawValue, weekday: day, date: date, scheduled: item)
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
                    Text("\(item.status.title) · \(item.scheduledStart.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(statusColor(item.status))
                } else {
                    Text("Unscheduled")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityIdentifier("plan.day.\(row.weekday.rawValue)")
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
    var id: Int
    var weekday: ISOWeekday
    var date: Date
    var scheduled: ScheduledWorkout?
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
