import SwiftUI

struct ProfileSettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @State private var newWeight = ""

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
            Stepper(
                "Target \(NumberFormatting.weight(profile.targetWeightKg, units: units))",
                onIncrement: { adjustTarget(1) },
                onDecrement: { adjustTarget(-1) }
            )
            Section("Log body weight") {
                TextField("Weight \(UnitConversion.weightUnitLabel(units))", text: $newWeight)
                    .keyboardType(.decimalPad)
                Button("Save weight") {
                    if let entered = Double(newWeight.replacingOccurrences(of: ",", with: ".")) {
                        // Entry is in the display unit; storage is always kilograms.
                        let kg = UnitConversion.storageWeight(displayed: entered, units: units)
                        modelContext.insert(BodyWeightEntry(weightKg: kg))
                        profile.currentWeightKg = kg
                        newWeight = ""
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .onDisappear {
            profile.updatedAt = .now
            try? modelContext.save()
        }
    }
}
