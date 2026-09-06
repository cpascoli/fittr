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
                    decrement: {
                        let displayed = max(0, UnitConversion.displayWeight(kg: controller.draftWeightKg, units: controller.units) - displayIncrement)
                        controller.draftWeightKg = UnitConversion.storageWeight(displayed: displayed, units: controller.units)
                    },
                    increment: {
                        let displayed = UnitConversion.displayWeight(kg: controller.draftWeightKg, units: controller.units) + displayIncrement
                        controller.draftWeightKg = UnitConversion.storageWeight(displayed: displayed, units: controller.units)
                    },
                    onTapValue: {
                        weightText = NumberFormatting.compactWeight(controller.draftWeightKg, units: controller.units)
                        editingWeight = true
                    }
                )
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

    private var displayIncrement: Double {
        UnitConversion.displayWeight(kg: controller.weightIncrementKg, units: controller.units)
    }
}
