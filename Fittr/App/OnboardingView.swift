import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Bindable var profile: UserProfile
    @Bindable var settings: AppSettings
    @State private var hasPreferredTime = false
    @State private var preferredTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    Text("These values are prefilled from your plan. Change anything that is wrong.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("Date of birth", selection: $profile.dateOfBirth, displayedComponents: .date)
                    LabeledContent("Height", value: "\(Int(profile.heightCm)) cm")
                    LabeledContent(
                        "Starting weight",
                        value: NumberFormatting.weight(profile.startingWeightKg, units: .metric)
                    )
                    Stepper(
                        "Target \(NumberFormatting.weight(profile.targetWeightKg, units: .metric))",
                        value: $profile.targetWeightKg,
                        in: 70...100,
                        step: 0.5
                    )
                    Picker("Lifting weights", selection: $profile.liftingUnits) {
                        ForEach(UnitSystem.allCases) { system in
                            Text(system.weightTitle).tag(system)
                        }
                    }
                }
                Section("Usual workout time") {
                    Text("Optional. Used for Calendar events and reminders. You can leave this unset.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Set a usual time", isOn: $hasPreferredTime)
                    if hasPreferredTime {
                        DatePicker("Time", selection: $preferredTime, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Permissions") {
                    Text("Health, Calendar, Music, and notifications are requested later, only when you turn those features on. The workout logger works offline with none of them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Start using Fittr") {
                        if hasPreferredTime {
                            let components = Calendar.current.dateComponents([.hour, .minute], from: preferredTime)
                            settings.preferredWorkoutHour = components.hour
                            settings.preferredWorkoutMinute = components.minute
                        }
                        settings.hasCompletedOnboarding = true
                        settings.updatedAt = .now
                    }
                    .accessibilityIdentifier("onboarding.done")
                }
            }
            .navigationTitle("Welcome to Fittr")
        }
    }
}
