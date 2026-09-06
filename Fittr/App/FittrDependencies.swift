import Foundation
import SwiftData

@MainActor
final class FittrDependencies {
    static let shared = FittrDependencies()

    var health: any HealthServicing = HealthService()
    var calendar: any CalendarServicing = CalendarService()
    var music: any MusicServicing = MusicService()
    var notifications: any NotificationServicing = NotificationService()
    var haptics: any HapticServicing = HapticService()
    var modelContext: ModelContext?
    var settings: AppSettings?

    func attach(context: ModelContext) {
        modelContext = context
        settings = try? context.fetch(FetchDescriptor<AppSettings>()).first
        if let haptic = haptics as? HapticService {
            haptic.isEnabled = settings?.hapticsEnabled ?? true
        }
    }

    func configureForUITesting() {
        health = MockHealthService()
        calendar = MockCalendarService()
        music = MockMusicService()
        notifications = MockNotificationService()
        haptics = MockHapticService()
    }
}
