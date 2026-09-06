import Foundation

enum DurationFormatting {
    static func compact(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 && secs == 0 {
            return "\(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    static func clock(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func countdown(seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

enum NumberFormatting {
    static func weight(_ kg: Double, units: UnitSystem) -> String {
        let value = units == .metric ? kg : UnitConversion.kilogramsToPounds(kg)
        let unit = units == .metric ? "kg" : "lb"
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded())) \(unit)"
        }
        return String(format: "%.1f %@", value, unit)
    }

    static func compactWeight(_ kg: Double, units: UnitSystem) -> String {
        let value = units == .metric ? kg : UnitConversion.kilogramsToPounds(kg)
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    static func volume(_ kg: Double, units: UnitSystem) -> String {
        let value = units == .metric ? kg : UnitConversion.kilogramsToPounds(kg)
        let unit = units == .metric ? "kg" : "lb"
        let formatted = value.formatted(.number.precision(.fractionLength(0...0)).grouping(.automatic))
        return "\(formatted) \(unit)"
    }

    static func distanceKm(_ km: Double, units: UnitSystem) -> String {
        if units == .metric {
            return String(format: "%.2f km", km)
        }
        return String(format: "%.2f mi", UnitConversion.kilometersToMiles(km))
    }
}
