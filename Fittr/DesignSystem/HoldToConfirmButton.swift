import SwiftUI
import UIKit

/// A button that fires only after being held for a few seconds. It looks exactly
/// like the plain gym button it replaces; the only difference is that a tap does
/// nothing, and holding sweeps a lighter band across it until it fires. For
/// actions that are easy to hit while picking the phone up and hard to undo once
/// hit: moving on to the next exercise, skipping one, finishing the workout.
///
/// The sweep is drawn with a scale transform, not a `GeometryReader`: a reader
/// inside the button made it greedy, and it grew to fill the whole bottom bar.
struct HoldToConfirmButton: View {
    let title: String
    var fill: Color = FittrTheme.accent
    var foreground: Color = .black
    var compact = false
    var duration: TimeInterval = FittrTheme.holdToConfirmSeconds
    let action: () -> Void

    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var holdTask: Task<Void, Never>?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous)
    }

    var body: some View {
        Text(title)
            .font(compact ? .headline.weight(.semibold) : .title3.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(compact ? Color.primary : foreground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 52 : FittrTheme.gymButtonHeight)
            .background(baseFill.opacity(isHolding ? 0.85 : 1), in: shape)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(sweepFill)
                    .scaleEffect(x: progress, y: 1, anchor: .leading)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .scaleEffect(isHolding ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: isHolding)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHolding { beginHold() }
                    }
                    .onEnded { _ in cancelHold() }
            )
            .onDisappear { holdTask?.cancel() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityHint("Hold for \(Int(duration.rounded())) seconds")
            .accessibilityAddTraits(.isButton)
            // VoiceOver users confirm through the rotor action rather than a timed
            // hold, which the gesture cannot deliver to them.
            .accessibilityAction { fire() }
    }

    private var baseFill: Color {
        compact ? FittrTheme.cardElevated : fill
    }

    /// Lightens the hero button as the hold progresses; tints the secondary one
    /// with its accent. Either way the label stays readable over both halves.
    private var sweepFill: Color {
        compact ? fill.opacity(0.45) : Color.white.opacity(0.35)
    }

    private func beginHold() {
        isHolding = true
        withAnimation(.linear(duration: duration)) {
            progress = 1
        }
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, isHolding else { return }
            fire()
        }
    }

    private func cancelHold() {
        guard isHolding else { return }
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(.easeOut(duration: 0.25)) {
            progress = 0
        }
    }

    private func fire() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        progress = 0
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        action()
    }
}

/// The hold control for actions that live in a menu, where a hold cannot
/// happen: the menu item opens this sheet, and the hold happens here.
struct HoldToConfirmSheet: View {
    let title: String
    let message: String
    let buttonTitle: String
    var fill: Color = FittrTheme.accent
    var foreground: Color = .black
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HoldToConfirmButton(title: buttonTitle, fill: fill, foreground: foreground) {
                dismiss()
                onConfirm()
            }
            .accessibilityIdentifier("workout.confirm.hold")
            Button("Keep going") { dismiss() }
                .buttonStyle(SecondaryGymButtonStyle())
                .accessibilityIdentifier("workout.confirm.cancel")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FittrTheme.background.ignoresSafeArea())
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}
