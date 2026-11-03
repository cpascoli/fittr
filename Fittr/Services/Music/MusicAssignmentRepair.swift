import Foundation
import SwiftData

enum MusicAssignmentRepair {
    /// Exercise tracks chosen from a template's music screen used to be saved
    /// with that template as their owner, which meant deleting the template would
    /// take the exercise's track with it. The picker no longer does that; this
    /// detaches the ones already saved. Returns how many were changed.
    @discardableResult
    static func detachExerciseTracksFromTemplates(in context: ModelContext) throws -> Int {
        let assignments = try context.fetch(FetchDescriptor<MusicAssignment>())
        var changed = 0
        for assignment in assignments where assignment.scope == .exercise && assignment.template != nil {
            assignment.template = nil
            changed += 1
        }
        if changed > 0 {
            try context.save()
        }
        return changed
    }
}
