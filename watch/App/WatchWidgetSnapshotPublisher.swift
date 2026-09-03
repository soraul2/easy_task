#if os(watchOS)
import PlanBaseCore
import SwiftData
import WidgetKit

@MainActor
enum WatchWidgetSnapshotPublicationService {
    @discardableResult
    static func publish(
        context: ModelContext,
        referenceDate: Date = Date(),
        forceWrite: Bool = false
    ) throws -> Bool {
        let dayKey = DayKey.key(for: referenceDate)
        let tasks = try context.fetch(
            BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey)
        )
        let events = try context.fetch(
            BoundedQueryService.eventsDescriptor(
                overlappingStartDayKey: dayKey,
                endDayKey: dayKey
            )
        )
        let snapshot = WatchWidgetSnapshot.make(
            tasks: tasks,
            events: events,
            referenceDate: referenceDate,
            activeFocus: try? FocusSessionService.activeSnapshot()
        )
        let didWrite = try WatchWidgetSnapshotStore.writeIfChanged(
            snapshot,
            forceWrite: forceWrite
        )
        if didWrite || forceWrite {
            WidgetCenter.shared.reloadTimelines(ofKind: WatchWidgetConstants.kind)
        }
        return didWrite
    }
}
#endif
