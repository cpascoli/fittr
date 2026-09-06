import SwiftUI

struct RestTimerView: View {
    @Bindable var controller: ActiveWorkoutController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(controller.restIsReady ? "READY" : "REST")
                .font(.caption.weight(.bold))
                .foregroundStyle(controller.restIsReady ? FittrTheme.success : .secondary)
            Text(DurationFormatting.countdown(seconds: controller.remainingRest))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(controller.restIsReady ? FittrTheme.success : .primary)
                .accessibilityIdentifier("workout.restTimer")
            ProgressView(value: controller.restProgress)
                .tint(controller.restIsReady ? FittrTheme.success : FittrTheme.accent)
            HStack {
                Button("+15s") { controller.addRest(15) }
                    .buttonStyle(SecondaryGymButtonStyle())
                Button("+30s") { controller.addRest(30) }
                    .buttonStyle(SecondaryGymButtonStyle())
            }
            HStack {
                Button("Skip Rest") { controller.skipRest() }
                    .buttonStyle(SecondaryGymButtonStyle())
                    .accessibilityIdentifier("workout.skipRest")
                Button("Start Next Set") { controller.startNextSet() }
                    .buttonStyle(GymButtonStyle())
                    .accessibilityIdentifier("workout.startNextSet")
            }
            if let rest = controller.openRest {
                Text("Actual rest so far: \(DurationFormatting.compact(seconds: rest.actualDuration(now: controller.tick)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fittrCard()
    }
}
