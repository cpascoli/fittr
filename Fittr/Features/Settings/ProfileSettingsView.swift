import SwiftData
import SwiftUI

struct ProfileSettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyWeightEntry.recordedAt, order: .reverse) private var weights: [BodyWeightEntry]
    @State private var newWeight = ""
    @State private var newWeightDate = Date.now
    @State private var editing: BodyWeightEntry?
    @State private var healthStatus: String?
    @State private var importingHealth = false

    /// Body weight is always kilograms; only lifting loads are switchable.
    private let units: UnitSystem = .metric

    /// Steps by a round amount in whichever unit is on screen: half a kilo, or
    /// a whole pound.
    private func adjustTarget(_ direction: Double) {
        let stepKg = units == .metric ? 0.5 : UnitConversion.poundsToKilograms(1)
        profile.targetWeightKg = min(150, max(40, profile.targetWeightKg + direction * stepKg))
    }

    var body: some View {
        Form {
            DatePicker("Date of birth", selection: $profile.dateOfBirth, displayedComponents: .date)
            LabeledContent("Age", value: "\(profile.ageYears)")
            Stepper("Height \(Int(profile.heightCm)) cm", value: $profile.heightCm, in: 140...210)
            LabeledContent("Starting weight", value: NumberFormatting.weight(profile.startingWeightKg, units: units))
            LabeledContent("Current weight", value: NumberFormatting.weight(profile.currentWeightKg, units: units))
            Stepper(
                "Target \(NumberFormatting.weight(profile.targetWeightKg, units: units))",
                onIncrement: { adjustTarget(1) },
                onDecrement: { adjustTarget(-1) }
            )
            Section("Log body weight") {
                TextField("Weight \(UnitConversion.weightUnitLabel(units))", text: $newWeight)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("profile.weight.value")
                // Defaults to today, but can be set back for weigh-ins that were
                // written down elsewhere at the time and never made it into the app.
                DatePicker("Date", selection: $newWeightDate, in: ...Date.now, displayedComponents: .date)
                    .accessibilityIdentifier("profile.weight.date")
                Button("Save weight") { saveNewWeight() }
                    .disabled(parsedWeight(newWeight) == nil)
                    .accessibilityIdentifier("profile.weight.save")
            }
            if FittrDependencies.shared.health.isAvailable {
                Section("Apple Health") {
                    Button(importingHealth ? "Importing…" : "Import weigh-ins from Health") {
                        Task { await importFromHealth() }
                    }
                    .disabled(importingHealth)
                    .accessibilityIdentifier("profile.weight.importHealth")
                    Text(healthStatus ?? "Pulls every body-weight reading Health holds, such as ones a smart scale logged. Running it again only adds new ones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !weights.isEmpty {
                Section("Weight history") {
                    ForEach(weights, id: \.id) { entry in
                        Button {
                            editing = entry
                        } label: {
                            HStack {
                                Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.primary)
                                if entry.source == BodyWeightLog.healthSource {
                                    Image(systemName: "heart.fill")
                                        .font(.caption2)
                                        .foregroundStyle(FittrTheme.danger)
                                        .accessibilityLabel("From Apple Health")
                                }
                                Spacer()
                                Text(NumberFormatting.weight(entry.weightKg, units: units))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .onDelete(perform: deleteWeights)
                    Text("Tap an entry to change it. Swipe to delete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Profile")
        .sheet(item: $editing) { entry in
            BodyWeightEntryEditor(entry: entry, units: units) { kg, date in
                try? BodyWeightLog.update(entry, weightKg: kg, on: date, profile: profile, in: modelContext)
            }
        }
        .onDisappear {
            profile.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func saveNewWeight() {
        guard let entered = parsedWeight(newWeight) else { return }
        // Entry is in the display unit; storage is always kilograms.
        let kg = UnitConversion.storageWeight(displayed: entered, units: units)
        try? BodyWeightLog.record(weightKg: kg, on: newWeightDate, profile: profile, in: modelContext)
        newWeight = ""
        newWeightDate = .now
    }

    private func importFromHealth() async {
        importingHealth = true
        defer { importingHealth = false }
        let health = FittrDependencies.shared.health
        do {
            try await health.requestAuthorization()
        } catch {
            healthStatus = "Health is unavailable on this device or signing profile."
            return
        }
        // Everything Health has. A scale logs at most a few readings a day, and
        // the analytics screen filters by range, so there is no reason to cut it.
        let samples = await health.bodyMassSamples(since: .distantPast)
        guard !samples.isEmpty else {
            healthStatus = "Health has no body-weight readings, or read access was not granted. Check Settings › Health › Data Access."
            return
        }
        do {
            let added = try BodyWeightLog.importFromHealth(samples, profile: profile, in: modelContext)
            healthStatus = added == 0
                ? "Up to date — all \(samples.count) Health readings were already on record."
                : "Added \(added) weigh-in\(added == 1 ? "" : "s") from Health."
        } catch {
            healthStatus = "Import failed: \(error.localizedDescription)"
        }
    }

    private func deleteWeights(at offsets: IndexSet) {
        for index in offsets {
            try? BodyWeightLog.delete(weights[index], profile: profile, in: modelContext)
        }
    }

    private func parsedWeight(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value
    }
}

/// Changes one weigh-in's date or value, for the entry typed with the wrong
/// number or saved against the wrong day.
private struct BodyWeightEntryEditor: View {
    let entry: BodyWeightEntry
    let units: UnitSystem
    let onSave: (Double, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weightText: String
    @State private var date: Date

    init(entry: BodyWeightEntry, units: UnitSystem, onSave: @escaping (Double, Date) -> Void) {
        self.entry = entry
        self.units = units
        self.onSave = onSave
        let displayed = UnitConversion.displayWeight(kg: entry.weightKg, units: units)
        _weightText = State(initialValue: displayed.formatted(.number.precision(.fractionLength(0...1))))
        _date = State(initialValue: entry.recordedAt)
    }

    private var parsed: Double? {
        guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Weight \(UnitConversion.weightUnitLabel(units))", text: $weightText)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            }
            .navigationTitle("Edit weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let parsed {
                            onSave(UnitConversion.storageWeight(displayed: parsed, units: units), date)
                            dismiss()
                        }
                    }
                    .disabled(parsed == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
