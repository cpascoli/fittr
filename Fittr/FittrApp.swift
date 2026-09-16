import SwiftData
import SwiftUI

@main
struct FittrApp: App {
    @State private var presentedSession: WorkoutSession?
    @State private var storeState: StoreState

    init() {
        if LaunchArguments.isUITesting {
            FittrDependencies.shared.configureForUITesting()
        }
        // A store that will not open is a state to render, not a reason to trap:
        // this device holds the only copy of the training history.
        _storeState = State(initialValue: FittrSchema.openStore(inMemory: LaunchArguments.isUITesting))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch storeState {
                case .ready(let container):
                    ContentView(presentedSession: $presentedSession)
                        .modelContainer(container)
                case .failed(let failure):
                    StoreRecoveryView(failure: failure) {
                        storeState = FittrSchema.openStore(inMemory: LaunchArguments.isUITesting)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @Query private var profiles: [UserProfile]
    @Binding var presentedSession: WorkoutSession?
    @State private var didSeed = false

    var body: some View {
        Group {
            if let settings = settings.first, let profile = profiles.first, !settings.hasCompletedOnboarding, !LaunchArguments.isUITesting {
                OnboardingView(profile: profile, settings: settings)
            } else {
                RootTabView(presentedSession: $presentedSession)
            }
        }
        .task {
            guard !didSeed else { return }
            didSeed = true
            FittrDependencies.shared.attach(context: modelContext)
            try? SeedService.seedIfNeeded(in: modelContext)
            if LaunchArguments.isUITesting, let settings = try? modelContext.fetch(FetchDescriptor<AppSettings>()).first {
                settings.hasCompletedOnboarding = true
                try? modelContext.save()
            }
        }
    }
}
