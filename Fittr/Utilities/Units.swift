import Foundation

enum UnitConversion {
    private static let kilogramsPerPound = 0.45359237
    private static let kilometersPerMile = 1.609344

    static func kilogramsToPounds(_ kg: Double) -> Double {
        kg / kilogramsPerPound
    }

    static func poundsToKilograms(_ pounds: Double) -> Double {
        pounds * kilogramsPerPound
    }

    static func kilometersToMiles(_ km: Double) -> Double {
        km / kilometersPerMile
    }

    static func milesToKilometers(_ miles: Double) -> Double {
        miles * kilometersPerMile
    }

    static func displayWeight(kg: Double, units: UnitSystem) -> Double {
        units == .metric ? kg : kilogramsToPounds(kg)
    }

    static func storageWeight(displayed: Double, units: UnitSystem) -> Double {
        units == .metric ? displayed : poundsToKilograms(displayed)
    }

    static func weightUnitLabel(_ units: UnitSystem) -> String {
        units == .metric ? "kg" : "lb"
    }
}

enum DateHelpers {
    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func isoWeekStart(for date: Date, calendar: Calendar = .current) -> Date {
        var calendar = calendar
        calendar.firstWeekday = 2
        let weekday = ISOWeekday.from(date: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: -(weekday.rawValue - 1), to: startOfDay(date, calendar: calendar))
            ?? startOfDay(date, calendar: calendar)
    }

    static func dateOnISOWeekday(_ weekday: ISOWeekday, weekStart: Date, hour: Int?, minute: Int?, calendar: Calendar = .current) -> Date {
        let day = calendar.date(byAdding: .day, value: weekday.rawValue - 1, to: startOfDay(weekStart, calendar: calendar))
            ?? weekStart
        return applying(hour: hour, minute: minute, to: day, calendar: calendar)
    }

    static func applying(hour: Int?, minute: Int?, to date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour ?? 12
        components.minute = minute ?? 0
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
