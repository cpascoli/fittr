import SwiftUI

enum FittrTheme {
    static let accent = Color.accentColor
    static let background = Color(red: 0.05, green: 0.055, blue: 0.065)
    static let card = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let cardElevated = Color(red: 0.155, green: 0.17, blue: 0.195)
    static let secondaryText = Color.secondary
    static let success = Color(red: 0.35, green: 0.82, blue: 0.55)
    static let warning = Color(red: 0.95, green: 0.72, blue: 0.28)
    static let danger = Color(red: 0.95, green: 0.40, blue: 0.38)

    /// A hairline lighter than the card it edges. On a dark UI this is what
    /// separates "crisp" from "muddy" — surfaces read as distinct panels
    /// instead of grey blocks dissolving into the background.
    static let hairline = Color.white.opacity(0.08)
    static let accentSoft = Color.accentColor.opacity(0.16)

    /// Rest palette. Working screens are near-black with a green accent; resting
    /// swaps to a cool blue so a glance from arm's length tells you which phase
    /// you are in, before reading a single word. Green stays reserved for the
    /// action that ends the rest.
    static let restBackground = Color(red: 0.04, green: 0.085, blue: 0.165)
    static let restAccent = Color(red: 0.38, green: 0.68, blue: 1.0)
    static let restCard = Color(red: 0.09, green: 0.13, blue: 0.19)

    static var restBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.07, green: 0.145, blue: 0.26), restBackground],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Very slight lift towards the top so full-screen backgrounds are not a
    /// dead flat field behind the cards.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.075, green: 0.085, blue: 0.10), background],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let cardCornerRadius: CGFloat = 20
    static let gymButtonHeight: CGFloat = 76
    static let gymTouchTarget: CGFloat = 64
}

/// How much a card should stand out from the ones around it.
enum CardEmphasis {
    /// Default panel.
    case standard
    /// The one thing on screen worth acting on.
    case hero
    /// Quiet container for secondary detail.
    case subtle
}

struct CardBackground: ViewModifier {
    var emphasis: CardEmphasis = .standard

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: FittrTheme.cardCornerRadius, style: .continuous)
        return content
            .padding(emphasis == .hero ? 20 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    emphasis == .hero ? FittrTheme.accent.opacity(0.35) : FittrTheme.hairline,
                    lineWidth: 1
                )
            }
    }

    private var fill: AnyShapeStyle {
        switch emphasis {
        case .standard:
            AnyShapeStyle(FittrTheme.card)
        case .subtle:
            AnyShapeStyle(FittrTheme.card.opacity(0.5))
        case .hero:
            AnyShapeStyle(
                LinearGradient(
                    colors: [FittrTheme.accent.opacity(0.20), FittrTheme.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

extension View {
    func fittrCard(_ emphasis: CardEmphasis = .standard) -> some View {
        modifier(CardBackground(emphasis: emphasis))
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
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 48 : 52)
            .padding(.horizontal, compact ? 4 : 0)
            .background(FittrTheme.cardElevated.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
