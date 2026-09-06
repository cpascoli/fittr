import Foundation
import SwiftData

enum TemplateService {
    @discardableResult
    static func duplicate(
        _ template: WorkoutTemplate,
        name: String,
        weekday: ISOWeekday,
        in context: ModelContext
    ) throws -> WorkoutTemplate {
        let copy = WorkoutTemplate(
            name: name,
            type: template.type,
            estimatedDurationMinutes: template.estimatedDurationMinutes,
            notes: template.notes,
            weekday: weekday,
            isOptionalDay: template.isOptionalDay,
            preferredHour: template.preferredHour,
            preferredMinute: template.preferredMinute,
            plan: template.plan
        )
        for item in template.orderedExercises {
            let cloned = WorkoutTemplateExercise(
                order: item.order,
                targetSets: item.targetSets,
                minReps: item.minReps,
                maxReps: item.maxReps,
                targetDurationSeconds: item.targetDurationSeconds,
                targetRestSeconds: item.targetRestSeconds,
                isOptional: item.isOptional,
                trackingModeOverride: item.trackingModeOverride,
                notes: item.notes,
                template: copy,
                exercise: item.exercise
            )
            copy.exercises.append(cloned)
        }
        if let plan = template.plan {
            plan.templates.append(copy)
        }
        context.insert(copy)
        try context.save()
        try ScheduleService.ensureUpcomingSchedule(in: context)
        return copy
    }
}
