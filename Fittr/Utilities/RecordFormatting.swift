import Foundation

enum RecordFormatting {
    static func detail(_ record: PersonalRecord, units: UnitSystem) -> String {
        switch record.kind {
        case .heaviestWeight:
            return NumberFormatting.weight(record.value, units: units)
        case .mostRepsAtWeight:
            let weight = record.secondaryValue.map { NumberFormatting.weight($0, units: units) } ?? record.notes
            return weight.isEmpty ? "\(Int(record.value)) reps" : "\(Int(record.value)) reps at \(weight)"
        case .highestSessionVolume:
            return NumberFormatting.volume(record.value, units: units)
        case .longestPlank, .longestCardio, .longestSwim:
            return DurationFormatting.compact(seconds: record.value)
        case .fastestPace:
            return record.unitLabel.isEmpty
                ? String(format: "%.1f", record.value)
                : "\(String(format: "%.1f", record.value)) \(record.unitLabel)"
        }
    }
}
