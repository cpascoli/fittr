import SwiftUI

/// Countdown for duration-based work such as the plank.
///
/// Start it when you are set, hold to zero, and a haptic tells you the set is
/// done without having to look at the phone on the floor. Stopping early keeps
/// whatever you actually held rather than the target, because an honest 22
/// seconds is more useful than a flattering 30.
struct HoldTimerView: View {
    @Bindable var controller: ActiveWorkoutController

    var body: some View {
        VStack(spacing: 14) {
            ring
            controls
            if !controller.isHolding && controller.measuredHoldSeconds == nil {
                StepperControl(
                    title: "Target (sec)",
                    valueText: "\(controller.draftDurationSeconds)",
                    decrement: { controller.draftDurationSeconds = max(5, controller.draftDurationSeconds - 5) },
                    increment: { controller.draftDurationSeconds += 5 }
                )
            }
        }
        .fittrCard()
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(FittrTheme.cardElevated, lineWidth: 12)
            if controller.holdProgress > 0.001 {
                Circle()
                    .trim(from: 0, to: controller.holdProgress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 2) {
                Text(centerText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(tint)
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 165, height: 165)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: controller.holdIsFinished)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("workout.holdTimer")
        .accessibilityLabel("Hold timer")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var controls: some View {
        if controller.isHolding {
            Button("STOP") {
                controller.stopHold()
            }
            .buttonStyle(GymButtonStyle(fill: FittrTheme.warning, foreground: .black))
            .accessibilityIdentifier("workout.stopHold")
        } else if controller.measuredHoldSeconds != nil {
            Button("Reset timer") {
                controller.resetHold()
            }
            .buttonStyle(SecondaryGymButtonStyle())
            .accessibilityIdentifier("workout.resetHold")
        } else {
            Button("START HOLD") {
                controller.startHold()
            }
            .buttonStyle(GymButtonStyle())
            .accessibilityIdentifier("workout.startHold")
        }
    }

    private var tint: Color {
        if controller.holdIsFinished { return FittrTheme.success }
        if controller.isHolding { return FittrTheme.accent }
        return .primary
    }

    private var centerText: String {
        if controller.isHolding {
            return DurationFormatting.countdown(seconds: controller.holdRemaining)
        }
        if let measured = controller.measuredHoldSeconds {
            return DurationFormatting.countdown(seconds: TimeInterval(measured))
        }
        return DurationFormatting.countdown(seconds: TimeInterval(controller.holdTargetSeconds))
    }

    private var caption: String {
        if controller.isHolding { return "remaining" }
        if controller.holdIsFinished { return "hold complete" }
        if controller.measuredHoldSeconds != nil { return "held" }
        return "target"
    }

    private var accessibilityValue: String {
        if controller.isHolding {
            return "\(Int(controller.holdRemaining.rounded())) seconds remaining"
        }
        if let measured = controller.measuredHoldSeconds {
            return controller.holdIsFinished
                ? "Hold complete, \(measured) seconds"
                : "Held \(measured) seconds"
        }
        return "Target \(controller.holdTargetSeconds) seconds"
    }
}
