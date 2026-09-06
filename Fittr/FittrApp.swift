import SwiftData
import SwiftUI

@main
struct FittrApp: App {
    @State private var presentedSession: WorkoutSession?
    private let container: ModelContainer

    init() {
        if LaunchArguments.isUITesting {
            FittrDependencies.shared.configureForUITesting()
        }
        do {
            container = try FittrSchema.container(inMemory: LaunchArguments.isUITesting)
        } catch {
            fatalError("Failed to create Fittr store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(presentedSession: $presentedSession)
                .modelContainer(container)
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
