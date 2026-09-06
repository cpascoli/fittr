import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutTemplate.weekdayRaw) private var templates: [WorkoutTemplate]
    @State private var healthStatus = "Not connected"
    @State private var calendarStatus = "Not connected"
    @State private var musicStatus = "Not connected"

    var body: some View {
        NavigationStack {
            Form {
                if let profile = profiles.first {
                    Section("Profile") {
                        NavigationLink("Edit profile") {
                            ProfileSettingsView(profile: profile)
                        }
                        LabeledContent("Age", value: "\(profile.ageYears)")
                        LabeledContent("Height", value: "\(Int(profile.heightCm)) cm")
                        Picker("Units", selection: Bindable(profile).preferredUnits) {
                            ForEach(UnitSystem.allCases) { system in
                                Text(system.title).tag(system)
                            }
                        }
                    }
                }
                if let current = settings.first {
                    Section("Training") {
                        Stepper(
                            "Weight increment \(NumberFormatting.weight(current.weightIncrementKg, units: profiles.first?.preferredUnits ?? .metric))",
                            value: Bindable(current).weightIncrementKg,
                            in: 0.5...10,
                            step: 0.5
                        )
                        Toggle("Haptics", isOn: Bindable(current).hapticsEnabled)
                        Toggle("Rest timer sound / notification", isOn: Bindable(current).restRemindersEnabled)
                        Stepper("Default pool length \(Int(current.defaultPoolLengthMeters)) m", value: Bindable(current).defaultPoolLengthMeters, in: 15...50, step: 5)
                    }
                    Section("Notifications") {
                        Toggle("Workout reminders", isOn: Bindable(current).workoutRemindersEnabled)
                            .onChange(of: current.workoutRemindersEnabled) { _, enabled in
                                if enabled {
                                    Task {
                                        _ = await FittrDependencies.shared.notifications.requestAuthorizationIfNeeded()
                                    }
                                }
                            }
                        Stepper("Remind \(current.reminderLeadMinutes) min before", value: Bindable(current).reminderLeadMinutes, in: 10...120, step: 10)
                    }
                    Section("Apple Health") {
                        Text("Fittr can read weight, heart rate, and steps, and can write completed workouts. Nothing leaves the phone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Write completed workouts to Health", isOn: Bindable(current).healthWriteEnabled)
                        Button("Connect Apple Health") {
                            Task { await connectHealth() }
                        }
                        Text(healthStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Calendar") {
                        Text("Fittr only creates its own workout events unless you later enable two-way sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Add workouts to Calendar", isOn: Bindable(current).calendarSyncEnabled)
                        Button("Connect Calendar") {
                            Task { await connectCalendar(current) }
                        }
                        Text(calendarStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Workout music") {
                        Text("Tracks come from the Music library on this iPhone (playlists and local MP3s), not the Apple Music catalog.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Auto-play exercise track", isOn: Bindable(current).autoPlayExerciseTrack)
                        Toggle("Restart track from beginning", isOn: Bindable(current).restartExerciseTrack)
                        Picker("After track / exercise", selection: Bindable(current).afterTrackBehavior) {
                            ForEach(AfterTrackBehavior.allCases) { behavior in
                                Text(behavior.title).tag(behavior)
                            }
                        }
                        Button("Allow Music library access") {
                            Task { await connectMusic() }
                        }
                        ForEach(templates.filter { $0.type == .strength }, id: \.id) { template in
                            NavigationLink("Tracks for \(template.weekday.shortTitle) \(template.name)") {
                                WorkoutMusicSetupView(template: template)
                            }
                        }
                        Text(musicStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Library") {
                    NavigationLink("Exercise library") {
                        ExerciseLibraryView()
                    }
                }
                Section("Data") {
                    NavigationLink("Export / import") {
                        ExportImportView()
                    }
                }
                Section("About") {
                    LabeledContent("App", value: "Fittr")
                    Text("Local-first. No account. No analytics SDK. No health data is uploaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onDisappear { try? modelContext.save() }
        }
    }

    private func connectHealth() async {
        do {
            try await FittrDependencies.shared.health.requestAuthorization()
            healthStatus = FittrDependencies.shared.health.isAuthorized ? "Connected" : "Permission not granted"
        } catch {
            healthStatus = "Health is unavailable on this device or signing profile."
        }
    }

    private func connectCalendar(_ current: AppSettings) async {
        let granted = await FittrDependencies.shared.calendar.requestWriteAccess()
        calendarStatus = granted ? "Write access granted" : "Permission not granted"
        if granted {
            current.calendarSyncEnabled = true
            await syncUpcoming(current)
        }
    }

    private func connectMusic() async {
        let granted = await FittrDependencies.shared.music.requestAuthorization()
        musicStatus = granted ? "Local Music library available" : "Permission not granted"
    }

    private func syncUpcoming(_ current: AppSettings) async {
        guard current.calendarSyncEnabled else { return }
        let upcoming = (try? modelContext.fetch(FetchDescriptor<ScheduledWorkout>())) ?? []
        for item in upcoming where item.status == .upcoming {
            guard let template = item.template else { continue }
            if let identifier = try? await FittrDependencies.shared.calendar.upsertWorkoutEvent(
                identifier: item.calendarEventIdentifier.isEmpty ? nil : item.calendarEventIdentifier,
                title: template.name,
                start: item.scheduledStart,
                durationMinutes: template.estimatedDurationMinutes,
                notes: "Expected duration: \(template.estimatedDurationMinutes) min\n\(template.orderedExercises.map { $0.exercise?.name ?? "" }.joined(separator: ", "))",
                deepLink: URL(string: "fittr://workout/\(item.id.uuidString)")
            ) {
                item.calendarEventIdentifier = identifier
            }
        }
        try? modelContext.save()
    }
}
