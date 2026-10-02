import Foundation

/// Turns a decimal the user is still typing into a stored number, and back.
///
/// The field keeps the raw text until editing ends. Formatting on every
/// keystroke is what turned "5" into "5.0" and then refused "5.4".
enum DecimalFieldDraft {
    enum Commit: Equatable {
        case empty
        case value(Double)
        case invalid
    }

    static func display(_ value: Double?) -> String {
        guard let value else { return "" }
        return display(value)
    }

    /// Whole numbers stay whole. A stored 5 is "5", not "5.0".
    static func display(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    /// Accepts a trailing separator, so leaving the field on "5." stores 5.
    /// A comma is treated as a decimal point.
    static func commit(_ text: String) -> Commit {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        var normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        guard !normalized.isEmpty, let number = Double(normalized), number.isFinite else {
            return .invalid
        }
        return .value(number)
    }
}
