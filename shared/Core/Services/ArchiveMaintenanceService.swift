import Foundation
import SwiftData

/// Lazy archival still runs at navigation/day boundaries, but a read-only check
/// must not announce a data mutation to every query session and widget publisher.
public enum ArchiveMaintenanceService {
    @MainActor
    @discardableResult
    public static func archiveCompletedTasks(
        in context: ModelContext,
        todayKey: String = DayKey.today,
        now: Date = Date()
    ) throws -> Int {
        let candidates = try context.fetch(
            BoundedQueryService.tasksNeedingArchiveDescriptor(before: todayKey)
        )
        // Preserve the old command's pre-save of unrelated pending edits. Only a
        // truly clean, empty check can skip both the command and its notification.
        guard !candidates.isEmpty || context.hasChanges else { return 0 }
        return try PersistenceCommandService.perform(in: context) {
            TaskRules.archiveIfNeeded(candidates, todayKey: todayKey, now: now)
            return candidates.count
        }
    }
}
