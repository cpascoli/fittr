import SwiftUI

struct ProfileSettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @State private var newWeight = ""

    var body: some View {
        Form {
            DatePicker("Date of birth", selection: $profile.dateOfBirth, displayedComponents: .date)
            LabeledContent("Age", value: "\(profile.ageYears)")
            Stepper("Height \(Int(profile.heightCm)) cm", value: $profile.heightCm, in: 140...210)
            LabeledContent("Starting weight", value: String(format: "%.1f kg", profile.startingWeightKg))
            Stepper(
                "Target \(String(format: "%.1f", profile.targetWeightKg)) kg",
                value: $profile.targetWeightKg,
                in: 60...150,
                step: 0.5
            )
            Section("Log body weight") {
                TextField("Weight kg", text: $newWeight)
                    .keyboardType(.decimalPad)
                Button("Save weight") {
                    if let value = Double(newWeight.replacingOccurrences(of: ",", with: ".")) {
                        modelContext.insert(BodyWeightEntry(weightKg: value))
                        profile.currentWeightKg = value
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
