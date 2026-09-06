import SwiftUI

struct RestTimerView: View {
    @Bindable var controller: ActiveWorkoutController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(controller.restIsReady ? "READY" : "REST")
                .font(.caption.weight(.bold))
                .foregroundStyle(controller.restIsReady ? FittrTheme.success : .secondary)
            if controller.isRestingBeforeNextExercise, let next = controller.nextExerciseName {
                Text("Next: \(next)")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("workout.nextExercise")
            }
            Text(DurationFormatting.countdown(seconds: controller.remainingRest))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(controller.restIsReady ? FittrTheme.success : .primary)
                .accessibilityIdentifier("workout.restTimer")
            ProgressView(value: controller.restProgress)
                .tint(controller.restIsReady ? FittrTheme.success : FittrTheme.accent)
            if let rest = controller.openRest {
                Text("Actual rest so far: \(DurationFormatting.compact(seconds: rest.actualDuration(now: controller.tick)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fittrCard()
    }
}
