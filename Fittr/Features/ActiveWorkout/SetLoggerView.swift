import SwiftUI

struct SetLoggerView: View {
    @Bindable var controller: ActiveWorkoutController
    @State private var editingWeight = false
    @State private var weightText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SET \(controller.currentSetNumber)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if controller.usesWeight {
                StepperControl(
                    title: "Weight (\(UnitConversion.weightUnitLabel(controller.units)))",
                    valueText: NumberFormatting.compactWeight(controller.draftWeightKg, units: controller.units),
                    decrement: { step(-1) },
                    increment: { step(1) },
                    onTapValue: {
                        weightText = NumberFormatting.compactWeight(controller.draftWeightKg, units: controller.units)
                        editingWeight = true
                    }
                )
                // The plates say one thing, the app stores another. Show both so
                // the number on the dumbbell can be matched without arithmetic.
                Text("= \(NumberFormatting.alternateWeight(controller.draftWeightKg, units: controller.units))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("workout.weightAlternate")
            }

            if controller.isUnilateral {
                StepperControl(
                    title: "Left reps",
                    valueText: "\(controller.draftLeftReps)",
                    decrement: { controller.draftLeftReps = max(0, controller.draftLeftReps - 1) },
                    increment: { controller.draftLeftReps += 1 }
                )
                StepperControl(
                    title: "Right reps",
                    valueText: "\(controller.draftRightReps)",
                    decrement: { controller.draftRightReps = max(0, controller.draftRightReps - 1) },
                    increment: { controller.draftRightReps += 1 }
                )
            } else if controller.usesReps {
                StepperControl(
                    title: "Reps",
                    valueText: "\(controller.draftReps)",
                    decrement: { controller.draftReps = max(0, controller.draftReps - 1) },
                    increment: { controller.draftReps += 1 }
                )
                .accessibilityIdentifier("workout.reps")
            }

            if let rir = controller.draftRIR {
                Text("RIR \(rir.formatted(.number.precision(.fractionLength(0...1))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fittrCard()
        .alert("Weight", isPresented: $editingWeight) {
            TextField("Weight", text: $weightText)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) {
                    controller.draftWeightKg = UnitConversion.storageWeight(displayed: value, units: controller.units)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// In pounds, a converted 2 kg step is 4.41 lb, which never lands on a rack
    /// number. Round to the nearest real plate jump instead.
    private var displayIncrement: Double {
        switch controller.units {
        case .metric:
            return controller.weightIncrementKg
        case .imperial:
            let raw = UnitConversion.kilogramsToPounds(controller.weightIncrementKg)
            return max(2.5, (raw / 2.5).rounded() * 2.5)
        }
    }

    /// Snap onto the increment grid before moving, so a seeded 12 kg (26.5 lb)
    /// becomes 25 / 30 lb rather than 26.5 / 31.5.
    private func step(_ direction: Int) {
        let increment = displayIncrement
        guard increment > 0 else { return }
        let current = UnitConversion.displayWeight(kg: controller.draftWeightKg, units: controller.units)
        let gridPoint = (current / increment).rounded() * increment
        var next = gridPoint + Double(direction) * increment
        if abs(current - gridPoint) > 0.01 {
            // Off-grid: the first press should land on the grid, not jump past it.
            if direction > 0 && gridPoint > current { next = gridPoint }
            if direction < 0 && gridPoint < current { next = gridPoint }
        }
        controller.draftWeightKg = UnitConversion.storageWeight(
            displayed: max(0, next),
            units: controller.units
        )
    }
}
