import Foundation

enum WorkoutPlanSeed {
    static func makePlan(exercises: [UUID: ExerciseDefinition]) -> WorkoutPlan {
        let plan = WorkoutPlan(
            id: SeedID.plan,
            name: "Sustainable Fitness",
            isActive: true
        )

        let monday = makeStrengthTemplate(
            id: SeedID.mondayStrength,
            name: "Full Body Strength",
            weekday: .monday,
            exercises: exercises,
            notes: "Primary strength day. Stop most sets with 3–4 reps in reserve."
        )
        monday.plan = plan

        let tuesday = WorkoutTemplate(
            id: SeedID.tuesdayCardio,
            name: "Easy Cardio",
            type: .cardio,
            estimatedDurationMinutes: 35,
            notes: "Cycling or treadmill walking at conversational intensity.",
            weekday: .tuesday,
            plan: plan,
            exercises: [
                item(order: 0, exercise: exercises[SeedID.indoorCycling], sets: 1, rest: 0, duration: 2100),
            ]
        )

        let wednesday = WorkoutTemplate(
            id: SeedID.wednesdayRecovery,
            name: "Recovery",
            type: .recovery,
            estimatedDurationMinutes: 30,
            notes: "Walking, mobility, or rest. No structured gym session required.",
            weekday: .wednesday,
            isOptionalDay: true,
            plan: plan,
            exercises: [
                item(order: 0, exercise: exercises[SeedID.walking], sets: 1, rest: 0, duration: 1800),
                item(order: 1, exercise: exercises[SeedID.mobility], sets: 1, rest: 0, duration: 1200, optional: true),
            ]
        )

        let thursday = makeStrengthTemplate(
            id: SeedID.thursdayStrength,
            name: "Full Body Strength",
            weekday: .thursday,
            exercises: exercises,
            notes: "Same starting prescription as Monday. Edit exercises independently if you want."
        )
        thursday.plan = plan

        let friday = WorkoutTemplate(
            id: SeedID.fridaySwim,
            name: "Swim / Cardio",
            type: .swimming,
            estimatedDurationMinutes: 30,
            notes: "Default swimming. Cycling, treadmill, or walking are fine alternatives.",
            weekday: .friday,
            plan: plan,
            exercises: [
                item(order: 0, exercise: exercises[SeedID.swimming], sets: 1, rest: 0, duration: 1800),
            ]
        )

        let saturday = WorkoutTemplate(
            id: SeedID.saturdayOptional,
            name: "Optional Activity",
            type: .recovery,
            estimatedDurationMinutes: 40,
            notes: "Long walk, swim, or casual activity. Skip without guilt.",
            weekday: .saturday,
            isOptionalDay: true,
            plan: plan,
            exercises: [
                item(order: 0, exercise: exercises[SeedID.walking], sets: 1, rest: 0, duration: 2400),
            ]
        )

        let sunday = WorkoutTemplate(
            id: SeedID.sundayRest,
            name: "Rest",
            type: .rest,
            estimatedDurationMinutes: 0,
            notes: "No scheduled training.",
            weekday: .sunday,
            isOptionalDay: true,
            plan: plan
        )

        plan.templates = [monday, tuesday, wednesday, thursday, friday, saturday, sunday]
        return plan
    }

    private static func makeStrengthTemplate(
        id: UUID,
        name: String,
        weekday: ISOWeekday,
        exercises: [UUID: ExerciseDefinition],
        notes: String
    ) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id,
            name: name,
            type: .strength,
            estimatedDurationMinutes: 40,
            notes: notes,
            weekday: weekday,
            exercises: [
                item(order: 0, exercise: exercises[SeedID.gobletSquat], sets: 2, min: 8, max: 12, rest: 90),
                item(order: 1, exercise: exercises[SeedID.romanianDeadlift], sets: 2, min: 8, max: 12, rest: 90),
                item(order: 2, exercise: exercises[SeedID.chestPress], sets: 2, min: 8, max: 12, rest: 90),
                item(order: 3, exercise: exercises[SeedID.oneArmRow], sets: 2, min: 8, max: 12, rest: 75),
                item(order: 4, exercise: exercises[SeedID.shoulderPress], sets: 2, min: 8, max: 12, rest: 90),
                item(order: 5, exercise: exercises[SeedID.latPulldown], sets: 2, min: 8, max: 12, rest: 90, optional: true),
                item(order: 6, exercise: exercises[SeedID.plank], sets: 2, rest: 60, duration: 25),
            ]
        )
    }

    private static func item(
        order: Int,
        exercise: ExerciseDefinition?,
        sets: Int,
        min: Int? = nil,
        max: Int? = nil,
        rest: Int,
        duration: Int? = nil,
        optional: Bool = false
    ) -> WorkoutTemplateExercise {
        WorkoutTemplateExercise(
            order: order,
            targetSets: sets,
            minReps: min,
            maxReps: max,
            targetDurationSeconds: duration ?? exercise?.defaultDurationSeconds,
            targetRestSeconds: rest,
            isOptional: optional,
            exercise: exercise
        )
    }
}
