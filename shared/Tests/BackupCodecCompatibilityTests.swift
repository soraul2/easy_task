import Foundation
import Testing
import SwiftData
@testable import EasyTaskCore

@Test
func backupUnsupportedVersionErrorIncludesVersion() {
    let error = BackupServiceError.unsupportedVersion(99)

    #expect(error.errorDescription?.contains("99") == true)
}

@Test
@MainActor
func backupCodecRoundTripsTemplatePlacementLinks() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let date = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))
    let placement = TemplatePlacement(
        sourceTemplateId: UUID(),
        templateName: "백업 루틴",
        dayKey: DayKey.key(for: date)
    )
    let task = Task(title: "백업 작업", plannedAt: date, order: 100, templatePlacementId: placement.id)
    placement.taskIds = [task.id]
    context.insert(placement)
    context.insert(task)

    let payload = try BackupCodec.makePayload(context: context)

    #expect(payload.templatePlacements?.first?.id == placement.id)
    #expect(payload.templatePlacements?.first?.taskIds == [task.id])
    #expect(payload.tasks.first?.templatePlacementId == placement.id)

    let restoredContainer = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let restoredContext = restoredContainer.mainContext
    try BackupCodec.replaceAll(with: payload, in: restoredContext)

    let restoredPlacement = try #require(restoredContext.fetch(FetchDescriptor<TemplatePlacement>()).first)
    let restoredTask = try #require(restoredContext.fetch(FetchDescriptor<Task>()).first)

    #expect(restoredPlacement.templateName == "백업 루틴")
    #expect(restoredPlacement.taskIds.isEmpty)
    #expect(restoredTask.templatePlacementId == restoredPlacement.id)
    #expect(TemplateService.tasks(for: restoredPlacement, in: [restoredTask]).map(\.id) == [restoredTask.id])
}
