import SwiftData
import SwiftUI

struct RootTabView: View {
    @Binding var presentedSession: WorkoutSession?
    @Query private var settings: [AppSettings]
    @Query private var profiles: [UserProfile]

    var body: some View {
        TabView {
            TodayView(presentedSession: $presentedSession)
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(item: $presentedSession) { session in
            if let settings = settings.first {
                ActiveWorkoutView(
                    controller: ActiveWorkoutController(
                        session: session,
                        modelContext: FittrDependencies.shared.modelContext ?? session.modelContext!,
                        haptics: FittrDependencies.shared.haptics,
                        notifications: FittrDependencies.shared.notifications,
                        music: FittrDependencies.shared.music,
                        settings: settings,
                        profile: profiles.first
                    )
                )
            }
        }
    }
}

extension WorkoutSession: Identifiable {}
