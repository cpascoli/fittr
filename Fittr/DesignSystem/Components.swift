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

/// Small uppercase label that opens a section. Consistent tracking and colour so
/// every screen reads with the same rhythm.
struct SectionLabel: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

/// A ring for a 0...1 value. Used for adherence, where a proportion reads faster
/// as a shape than as "67%".
struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7
    var tint: Color = FittrTheme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(FittrTheme.cardElevated, lineWidth: lineWidth)
            // No arc at all at zero: a rounded cap on a zero-length trim renders
            // as a stray dot that reads as a rendering fault.
            if progress > 0.005 {
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text("\(Int((progress * 100).rounded()))%")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Adherence")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

/// One day in the week strip.
struct WeekDayMark: Identifiable, Hashable {
    enum State: Hashable {
        case completed
        case upcoming
        case skipped
        case rest
        case empty
    }

    var id: Int
    var letter: String
    var dayNumber: Int
    var state: State
    var isToday: Bool
}

/// Seven dots showing the training week at a glance. Replaces counting sessions
/// in prose — the shape of the week is the thing you actually want to see.
struct WeekStrip: View {
    let days: [WeekDayMark]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(day.letter)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(day.isToday ? FittrTheme.accent : .secondary)
                    ZStack {
                        Circle()
                            .fill(fill(for: day.state))
                            .frame(width: 32, height: 32)
                        Circle()
                            .strokeBorder(stroke(for: day), lineWidth: day.isToday ? 2 : 1)
                            .frame(width: 32, height: 32)
                        if day.state == .completed {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.black)
                        } else {
                            Text("\(day.dayNumber)")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(day.state == .empty || day.state == .rest ? .secondary : .primary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.letter) \(day.dayNumber)")
                .accessibilityValue(label(for: day.state))
            }
        }
    }

    private func fill(for state: WeekDayMark.State) -> Color {
        switch state {
        case .completed: FittrTheme.accent
        case .skipped: FittrTheme.warning.opacity(0.22)
        case .upcoming: FittrTheme.cardElevated
        case .rest, .empty: Color.clear
        }
    }

    private func stroke(for day: WeekDayMark) -> Color {
        if day.isToday { return FittrTheme.accent }
        switch day.state {
        case .completed: return .clear
        case .skipped: return FittrTheme.warning.opacity(0.5)
        case .upcoming: return FittrTheme.hairline
        case .rest, .empty: return FittrTheme.hairline
        }
    }

    private func label(for state: WeekDayMark.State) -> String {
        switch state {
        case .completed: "Completed"
        case .upcoming: "Planned"
        case .skipped: "Skipped"
        case .rest: "Rest day"
        case .empty: "Nothing planned"
        }
    }
}

/// Compact key/value pair for stat rows, without the full card chrome.
struct StatBlock: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// Compact "nothing here yet" row. Used where a full ContentUnavailableView
/// would be heavier than the thing it is standing in for.
struct EmptyHint: View {
    let text: String
    var systemImage: String = "chart.line.uptrend.xyaxis"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
