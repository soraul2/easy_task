import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func relationshipDeletionCommandsRemainConsistentAfterReopen() throws {
    try withConvergenceStore { storeURL in
        let date = try #require(DayKey.date(from: "2026-07-12"))
        let initial = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        let event = CalendarEvent(
            title: "삭제할 이벤트",
            startAt: date,
            endAt: date
        )
        let placement = TemplatePlacement(
            sourceTemplateId: nil,
            templateName: "삭제할 배치",
            dayKey: "2026-07-12"
        )
        let eventTask = Task(
            title: "이벤트 연결 작업",
            plannedAt: date,
            order: 100,
            eventId: event.id
        )
        let placementTask = Task(
            title: "배치 연결 작업",
            plannedAt: date,
            order: 200,
            templatePlacementId: placement.id
        )
        initial.mainContext.insert(event)
        initial.mainContext.insert(placement)
        initial.mainContext.insert(eventTask)
        initial.mainContext.insert(placementTask)
        try initial.mainContext.save()

        let mutating = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        let storedEvent = try #require(mutating.mainContext.fetch(
            FetchDescriptor<CalendarEvent>()
        ).first)
        let storedPlacement = try #require(mutating.mainContext.fetch(
            FetchDescriptor<TemplatePlacement>()
        ).first)
        try PersistenceCommandService.perform(in: mutating.mainContext) {
            let linkedEventTasks = try BoundedQueryService.tasksLinked(
                toEventID: storedEvent.id,
                in: mutating.mainContext
            )
            CalendarEventRules.detachTasks(from: storedEvent, in: linkedEventTasks)
            mutating.mainContext.delete(storedEvent)

            let linkedPlacementTasks = try BoundedQueryService.tasksLinked(
                toTemplatePlacementID: storedPlacement.id,
                in: mutating.mainContext
            )
            _ = try TemplateService.deletePlacement(
                storedPlacement,
                tasks: linkedPlacementTasks,
                in: mutating.mainContext,
                deleteTasks: false
            )
        }

        let reopened = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        let tasks = try reopened.mainContext.fetch(FetchDescriptor<Task>())
        #expect(try reopened.mainContext.fetch(FetchDescriptor<CalendarEvent>()).isEmpty)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<TemplatePlacement>()).isEmpty)
        #expect(tasks.count == 2)
        #expect(tasks.allSatisfy { $0.eventId == nil && $0.templatePlacementId == nil })
    }
}

@MainActor
private func withConvergenceStore(
    _ operation: (URL) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "EasyTaskConvergence-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try operation(directory.appendingPathComponent("default.store"))
}
