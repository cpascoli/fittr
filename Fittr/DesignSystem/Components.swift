import SwiftUI

struct StepperControl: View {
    let title: String
    let valueText: String
    let decrement: () -> Void
    let increment: () -> Void
    var onTapValue: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.title2.weight(.bold))
                        .frame(width: FittrTheme.gymTouchTarget, height: FittrTheme.gymTouchTarget)
                        .background(FittrTheme.cardElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel("Decrease \(title)")

                Button(action: { onTapValue?() }) {
                    Text(valueText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .minimumScaleFactor(0.6)
                }
                .disabled(onTapValue == nil)
                .accessibilityLabel(title)

                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .frame(width: FittrTheme.gymTouchTarget, height: FittrTheme.gymTouchTarget)
                        .background(FittrTheme.cardElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel("Increase \(title)")
            }
        }
    }
}

struct StatusChip: View {
    let text: String
    var color: Color = FittrTheme.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fittrCard()
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String = ""

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: message.isEmpty ? nil : Text(message))
    }
}
