#if DEBUG
import Foundation
import SwiftData

/// Opt-in performance data. The caller supplies an isolated local store, never the app store.
public enum ResponsivenessPreviewFixtures {
    @MainActor
    public static func seed(in context: ModelContext, referenceDate: Date = Date()) throws {
        guard try context.fetchCount(FetchDescriptor<Task>()) == 0 else { return }
        let today = DayKey.startOfDay(for: referenceDate)
        for index in 0..<3_000 {
            let day = index < 240 ? today : DayKey.addingDays(-(1 + index % 120), to: today)
            let status: TaskStatus = index < 240 ? (index % 3 == 1 ? .doing : .todo) : .done
            let task = Task(title: String(format: "성능 작업 %04d", index), status: status,
                            plannedAt: day, order: Double(index), estimatedMinutes: 30)
            context.insert(task)
            let startedAt = day.addingTimeInterval(9 * 3600)
            context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: startedAt))
            context.insert(TaskProgressEvent(taskId: task.id, kind: .stopped,
                                             occurredAt: startedAt.addingTimeInterval(1_800)))
            if status == .done {
                task.completedAt = startedAt.addingTimeInterval(1_800)
                task.completedDayKey = DayKey.key(for: day)
                task.archivedAt = day.addingTimeInterval(24 * 3600)
                task.archivedDayKey = DayKey.key(for: DayKey.addingDays(1, to: day))
                try TaskActivityService.recordCapturedCompletion(
                    taskID: task.id, occurredAt: task.completedAt!, in: context)
            }
            if index % 250 == 249 { try context.save() }
        }
        for index in 0..<1_000 {
            let title = String(format: "성능 보관 %04d", index)
            let template = TaskTemplate(name: title, quickEntryAlias: "perf\(index)")
            context.insert(template)
            context.insert(TaskTemplateItem(templateId: template.id, title: title,
                                             estimatedMinutes: 30, order: Double(index)))
        }
        for index in 0..<180 {
            let day = DayKey.addingDays(index % 90 - 45, to: today)
            context.insert(CalendarEvent(title: "성능 일정 \(index)", startAt: day,
                                          endAt: day.addingTimeInterval(3_600)))
        }
        for index in 0..<200 {
            context.insert(Memo(content: "성능 메모 \(index)\n" + String(repeating: "테스트 내용입니다. ", count: 40)))
        }
        try context.save()
    }
}
#endif
