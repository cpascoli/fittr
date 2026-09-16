import SwiftData
import SwiftUI

struct ActiveWorkoutHost: View {
    let session: WorkoutSession
    var settings: AppSettings?
    var profile: UserProfile?
    var modelContext: ModelContext?

    @State private var controller: ActiveWorkoutController?

    var body: some View {
        Group {
            if let controller {
                ActiveWorkoutView(controller: controller)
            } else {
                FittrTheme.background.ignoresSafeArea()
            }
        }
        .onAppear(perform: makeControllerIfNeeded)
    }

    private func makeControllerIfNeeded() {
        guard controller == nil else { return }
        let context = modelContext
            ?? FittrDependencies.shared.modelContext
            ?? session.modelContext
        guard let context else { return }
        controller = ActiveWorkoutController(
            session: session,
            modelContext: context,
            haptics: FittrDependencies.shared.haptics,
            notifications: FittrDependencies.shared.notifications,
            music: FittrDependencies.shared.music,
            settings: settings ?? FittrDependencies.shared.settings,
            profile: profile
        )
    }
}
