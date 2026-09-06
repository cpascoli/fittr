import SwiftUI

struct CardioLoggerView: View {
    @Bindable var controller: ActiveWorkoutController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session is timing from the start stamp. Add details now or after you finish.")
                .foregroundStyle(.secondary)
            if let cardio = controller.session.cardio {
                metricField("Activity", text: Binding(
                    get: { cardio.activityKind },
                    set: { cardio.activityKind = $0 }
                ))
                optionalNumber("Distance (km)", value: Binding(
                    get: { cardio.distanceKm },
                    set: { cardio.distanceKm = $0 }
                ))
                optionalNumber("Resistance", value: Binding(
                    get: { cardio.resistanceLevel },
                    set: { cardio.resistanceLevel = $0 }
                ))
                optionalNumber("Speed (km/h)", value: Binding(
                    get: { cardio.averageSpeedKmh },
                    set: { cardio.averageSpeedKmh = $0 }
                ))
                optionalNumber("Incline %", value: Binding(
                    get: { cardio.inclinePercent },
                    set: { cardio.inclinePercent = $0 }
                ))
                optionalNumber("Machine calories", value: Binding(
                    get: { cardio.machineCalories },
                    set: { cardio.machineCalories = $0 }
                ))
            }
            if let swim = controller.session.swim {
                optionalNumber("Pool length (m)", value: Binding(
                    get: { Optional(swim.poolLengthMeters) },
                    set: { if let value = $0 { swim.poolLengthMeters = value } }
                ))
                optionalInt("Laps / lengths", value: Binding(
                    get: { swim.laps },
                    set: {
                        swim.laps = $0
                        if let laps = $0 {
                            swim.distanceMeters = Double(laps) * swim.poolLengthMeters
                        }
                    }
                ))
                metricField("Stroke", text: Binding(
                    get: { swim.stroke },
                    set: { swim.stroke = $0 }
                ))
            }
            Text("Heart rate: \(heartRateLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fittrCard()
    }

    private var heartRateLabel: String {
        if let hr = controller.session.cardio?.averageHeartRate ?? controller.session.swim?.averageHeartRate {
            return "\(Int(hr)) bpm"
        }
        return "No data available"
    }

    private func metricField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func optionalNumber(_ title: String, value: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: Binding(
                get: { value.wrappedValue.map { String($0) } ?? "" },
                set: { value.wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".")) }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
        }
    }

    private func optionalInt(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: { value.wrappedValue = Int($0) }
            ))
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
        }
    }
}
