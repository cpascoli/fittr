import SwiftUI
import UIKit

/// A button that fires only after being held for a few seconds, with a fill that
/// sweeps across it to show how far along the hold is. For actions that are easy
/// to hit while picking the phone up and hard to undo once hit: moving on to the
/// next exercise, skipping one, finishing the workout. A plain tap does nothing
/// except start the sweep and reset, which is how the control teaches itself.
struct HoldToConfirmButton: View {
    let title: String
    var subtitle: String?
    var fill: Color = FittrTheme.accent
    var foreground: Color = .black
    var compact = false
    var duration: TimeInterval = FittrTheme.holdToConfirmSeconds
    let action: () -> Void

    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var holdTask: Task<Void, Never>?

    private var cornerRadius: CGFloat { compact ? 16 : 18 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    var body: some View {
        ZStack {
            shape.fill(FittrTheme.cardElevated)
            label(color: .primary)
            // The filled part of the bar carries its own copy of the label in the
            // button's foreground colour, so the text stays legible both over the
            // dark base and over the bright sweep as it passes underneath.
            GeometryReader { proxy in
                ZStack {
                    shape.fill(fill)
                    label(color: foreground)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: proxy.size.width * progress)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: compact ? 52 : FittrTheme.gymButtonHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(fill.opacity(0.5), lineWidth: 1))
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

    private func label(color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(compact ? .headline.weight(.semibold) : .title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(hint)
                .font(.caption2.weight(.semibold))
                .opacity(0.8)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    private var hint: String {
        if isHolding { return "Keep holding…" }
        if let subtitle { return subtitle }
        return "Hold for \(Int(duration.rounded())) seconds"
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
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}
