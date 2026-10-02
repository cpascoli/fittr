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
                OptionalDecimalField("Distance (km)", value: Binding(
                    get: { cardio.distanceKm },
                    set: { cardio.distanceKm = $0 }
                ))
                OptionalDecimalField("Resistance", value: Binding(
                    get: { cardio.resistanceLevel },
                    set: { cardio.resistanceLevel = $0 }
                ))
                OptionalDecimalField("Speed (km/h)", value: Binding(
                    get: { cardio.averageSpeedKmh },
                    set: { cardio.averageSpeedKmh = $0 }
                ))
                OptionalDecimalField("Incline %", value: Binding(
                    get: { cardio.inclinePercent },
                    set: { cardio.inclinePercent = $0 }
                ))
                OptionalDecimalField("Machine calories", value: Binding(
                    get: { cardio.machineCalories },
                    set: { cardio.machineCalories = $0 }
                ))
            }
            if let swim = controller.session.swim {
                OptionalDecimalField("Pool length (m)", value: Binding(
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

/// Keeps whatever is typed until the field is left. The number is written then,
/// so "5" is not rewritten to "5.0" while "5.4" is still being entered.
private struct OptionalDecimalField: View {
    let title: String
    @Binding var value: Double?
    @State private var text = ""
    @State private var didLoad = false
    @FocusState private var focused: Bool

    init(_ title: String, value: Binding<Double?>) {
        self.title = title
        self._value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onAppear {
                    guard !didLoad else { return }
                    text = DecimalFieldDraft.display(value)
                    didLoad = true
                }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onDisappear {
                    guard didLoad else { return }
                    commit()
                }
        }
    }

    private func commit() {
        switch DecimalFieldDraft.commit(text) {
        case .empty:
            value = nil
            text = DecimalFieldDraft.display(value)
        case .value(let number):
            value = number
            text = DecimalFieldDraft.display(value ?? number)
        case .invalid:
            text = DecimalFieldDraft.display(value)
        }
    }
}
