import SwiftUI

struct RestTimerView: View {
    @Bindable var controller: ActiveWorkoutController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(controller.restIsReady ? "READY" : "REST")
                .font(.caption.weight(.bold))
                .foregroundStyle(controller.restIsReady ? FittrTheme.success : FittrTheme.restAccent)
            if controller.isRestingBeforeNextExercise, let next = controller.nextExerciseName {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next: \(next)")
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("workout.nextExercise")
                    if let plan = controller.nextExercisePlan {
                        loadPlan(plan)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(DurationFormatting.countdown(seconds: controller.remainingRest))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(controller.restIsReady ? FittrTheme.success : FittrTheme.restAccent)
                .accessibilityIdentifier("workout.restTimer")
            ProgressView(value: controller.restProgress)
                .tint(controller.restIsReady ? FittrTheme.success : FittrTheme.restAccent)
            if let rest = controller.openRest {
                Text("Actual rest so far: \(DurationFormatting.compact(seconds: rest.actualDuration(now: controller.tick)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fittrCard()
    }

    /// The load belongs here rather than only on the set logger: by the time the
    /// logger appears the walk to the rack has already happened.
    @ViewBuilder
    private func loadPlan(_ plan: NextExercisePlan) -> some View {
        if let weight = plan.weightKg {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(NumberFormatting.weight(weight, units: controller.units))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("= \(NumberFormatting.alternateWeight(weight, units: controller.units))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if plan.isPerSide {
                    Text("each side")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workout.nextWeight")
        }
        if let detail = detailLine(plan) {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("workout.nextTarget")
        }
    }

    private func detailLine(_ plan: NextExercisePlan) -> String? {
        let parts = [plan.targetLabel, plan.equipmentLabel, plan.basis?.label].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
