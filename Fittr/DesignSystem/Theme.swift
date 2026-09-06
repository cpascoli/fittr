import SwiftUI

enum FittrTheme {
    static let accent = Color.accentColor
    static let background = Color(red: 0.07, green: 0.08, blue: 0.09)
    static let card = Color(red: 0.12, green: 0.13, blue: 0.15)
    static let cardElevated = Color(red: 0.16, green: 0.17, blue: 0.20)
    static let secondaryText = Color.secondary
    static let success = Color(red: 0.35, green: 0.82, blue: 0.55)
    static let warning = Color(red: 0.95, green: 0.72, blue: 0.28)
    static let danger = Color(red: 0.95, green: 0.40, blue: 0.38)

    static let gymButtonHeight: CGFloat = 76
    static let gymTouchTarget: CGFloat = 64
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FittrTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func fittrCard() -> some View {
        modifier(CardBackground())
    }
}

struct GymButtonStyle: ButtonStyle {
    var fill: Color = FittrTheme.accent
    var foreground: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: FittrTheme.gymButtonHeight)
            .background(fill.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryGymButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(FittrTheme.cardElevated.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
