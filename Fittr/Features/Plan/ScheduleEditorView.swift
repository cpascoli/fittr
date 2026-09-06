import SwiftUI

struct ScheduleEditorView: View {
    @Bindable var item: ScheduledWorkout
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date and time", selection: $item.scheduledStart)
                Picker("Status", selection: $item.status) {
                    ForEach(ScheduledStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                TextField("Notes", text: $item.notes)
            }
            .navigationTitle("Reschedule")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if item.status == .upcoming {
                            item.status = .rescheduled
                        }
                        try? modelContext.save()
                        onSave()
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
