import Foundation
import UIKit

protocol HapticServicing: AnyObject {
    func setCompleted()
    func restComplete()
    func exerciseComplete()
    func workoutComplete()
}

final class HapticService: HapticServicing {
    var isEnabled: Bool = true

    func setCompleted() {
        fire(.medium)
    }

    func restComplete() {
        fire(.heavy)
        fire(.success)
    }

    func exerciseComplete() {
        fire(.success)
    }

    func workoutComplete() {
        fire(.success)
    }

    private func fire(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    private func fire(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

final class MockHapticService: HapticServicing {
    var events: [String] = []

    func setCompleted() { events.append("set") }
    func restComplete() { events.append("rest") }
    func exerciseComplete() { events.append("exercise") }
    func workoutComplete() { events.append("workout") }
}
