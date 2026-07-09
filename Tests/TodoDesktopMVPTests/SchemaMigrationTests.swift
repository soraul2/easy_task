import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func schemaV1ContainsEveryPersistedModel() {
    let modelNames = Set(EasyTaskSchemaV1.models.map { String(reflecting: $0) })
    let expectedNames = Set([
        String(reflecting: EasyTaskSchemaV1.Task.self),
        String(reflecting: EasyTaskSchemaV1.CalendarEvent.self),
        String(reflecting: EasyTaskSchemaV1.TaskTemplate.self),
        String(reflecting: EasyTaskSchemaV1.TaskTemplateItem.self),
        String(reflecting: EasyTaskSchemaV1.TemplatePlacement.self),
        String(reflecting: EasyTaskSchemaV1.DailyReview.self),
        String(reflecting: EasyTaskSchemaV1.DiaryBlock.self)
    ])

    #expect(EasyTaskSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    #expect(modelNames == expectedNames)
}

@Test
func schemaV2ContainsEveryCurrentPersistedModel() {
    let modelNames = Set(EasyTaskSchemaV2.models.map { String(reflecting: $0) })
    let expectedNames = Set([
        String(reflecting: Task.self),
        String(reflecting: CalendarEvent.self),
        String(reflecting: TaskTemplate.self),
        String(reflecting: TaskTemplateItem.self),
        String(reflecting: TemplatePlacement.self),
        String(reflecting: DailyReview.self),
        String(reflecting: DiaryBlock.self)
    ])

    #expect(EasyTaskSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
    #expect(modelNames == expectedNames)
}

@Test
@MainActor
func versionedContainerReopensFileBackedStore() throws {
    try withTemporaryStore { storeURL in
        try writeFixture(
            to: EasyTaskContainerFactory.makePersistent(storeURL: storeURL),
            title: "versioned fixture"
        )

        let reopened = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        try expectFixture(in: reopened, title: "versioned fixture")
    }
}

@Test
@MainActor
func versionedV1StoreMigratesToV2WithoutDataLoss() throws {
    try withTemporaryStore { storeURL in
        let v1Schema = Schema(versionedSchema: EasyTaskSchemaV1.self)
        let configuration = ModelConfiguration(
            "EasyTaskV1",
            schema: v1Schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let v1Container = try ModelContainer(
            for: v1Schema,
            configurations: configuration
        )
        try writeV1Fixture(to: v1Container, title: "v1 fixture")

        let migrated = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        try expectFixture(in: migrated, title: "v1 fixture")
        try expectLegacyIdentityBackfill(in: migrated)
    }
}

@Test
@MainActor
func existingUnversionedStoreOpensWithSchemaV1WithoutDataLoss() throws {
    try withTemporaryStore { storeURL in
        try writeUnversionedV1Fixture(to: storeURL, title: "legacy fixture")

        let migrated = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        try expectFixture(in: migrated, title: "legacy fixture")
        try expectLegacyIdentityBackfill(in: migrated)
    }
}

@MainActor
private func writeUnversionedV1Fixture(to storeURL: URL, title: String) throws {
    let configuration = ModelConfiguration(
        url: storeURL,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(
        for: EasyTaskSchemaV1.Task.self,
        EasyTaskSchemaV1.CalendarEvent.self,
        EasyTaskSchemaV1.TaskTemplate.self,
        EasyTaskSchemaV1.TaskTemplateItem.self,
        EasyTaskSchemaV1.TemplatePlacement.self,
        EasyTaskSchemaV1.DailyReview.self,
        EasyTaskSchemaV1.DiaryBlock.self,
        configurations: configuration
    )
    try writeV1Fixture(to: container, title: title)
}

@MainActor
private func writeV1Fixture(to container: ModelContainer, title: String) throws {
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let event = EasyTaskSchemaV1.CalendarEvent(title: "\(title) event", startAt: day, endAt: day)
    let template = EasyTaskSchemaV1.TaskTemplate(name: "\(title) template")
    let templateItem = EasyTaskSchemaV1.TaskTemplateItem(
        templateId: template.id,
        title: "\(title) template item",
        order: 100
    )
    let placement = EasyTaskSchemaV1.TemplatePlacement(
        sourceTemplateId: template.id,
        templateName: template.name,
        dayKey: DayKey.key(for: day)
    )
    let task = EasyTaskSchemaV1.Task(
        title: title,
        plannedAt: day,
        order: 100,
        eventId: event.id,
        templatePlacementId: placement.id
    )
    placement.taskIds = [task.id]
    let review = EasyTaskSchemaV1.DailyReview(
        dayKey: DayKey.key(for: day),
        content: "\(title) review"
    )
    let block = EasyTaskSchemaV1.DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: review.content,
        order: 100
    )

    context.insert(event)
    context.insert(template)
    context.insert(templateItem)
    context.insert(placement)
    context.insert(task)
    context.insert(review)
    context.insert(block)
    try context.save()
}

@MainActor
private func writeFixture(to container: ModelContainer, title: String) throws {
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let event = CalendarEvent(title: "\(title) event", startAt: day, endAt: day)
    let template = TaskTemplate(name: "\(title) template")
    let templateItem = TaskTemplateItem(
        templateId: template.id,
        title: "\(title) template item",
        order: 100
    )
    let placement = TemplatePlacement(
        sourceTemplateId: template.id,
        templateName: template.name,
        dayKey: DayKey.key(for: day)
    )
    let task = Task(
        title: title,
        plannedAt: day,
        order: 100,
        eventId: event.id,
        templatePlacementId: placement.id
    )
    placement.taskIds = [task.id]
    let review = DailyReview(dayKey: DayKey.key(for: day), content: "\(title) review")
    let block = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: review.content,
        order: 100
    )

    context.insert(event)
    context.insert(template)
    context.insert(templateItem)
    context.insert(placement)
    context.insert(task)
    context.insert(review)
    context.insert(block)
    try context.save()
}

@MainActor
private func expectFixture(in container: ModelContainer, title: String) throws {
    let context = container.mainContext
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplateItem>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TemplatePlacement>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<DailyReview>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<DiaryBlock>()) == 1)

    let task = try #require(context.fetch(FetchDescriptor<Task>()).first)
    let placement = try #require(context.fetch(FetchDescriptor<TemplatePlacement>()).first)
    #expect(task.title == title)
    #expect(task.templatePlacementId == placement.id)
    #expect(placement.taskIds.isEmpty)

}

@MainActor
private func expectLegacyIdentityBackfill(in container: ModelContainer) throws {
    let context = container.mainContext
    #expect(try context.fetch(FetchDescriptor<CalendarEvent>()).allSatisfy { $0.instanceID == $0.id })
    #expect(try context.fetch(FetchDescriptor<TaskTemplate>()).allSatisfy { $0.instanceID == $0.id })
    #expect(try context.fetch(FetchDescriptor<TaskTemplateItem>()).allSatisfy { $0.instanceID == $0.id })
    #expect(try context.fetch(FetchDescriptor<TemplatePlacement>()).allSatisfy { $0.instanceID == $0.id })
    #expect(try context.fetch(FetchDescriptor<Task>()).allSatisfy { $0.instanceID == $0.id })
    #expect(try context.fetch(FetchDescriptor<DailyReview>()).allSatisfy { $0.instanceID == $0.id })
    #expect(try context.fetch(FetchDescriptor<DiaryBlock>()).allSatisfy { $0.instanceID == $0.id })
}

@MainActor
private func withTemporaryStore(
    _ operation: (URL) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("EasyTaskSchemaV1-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try operation(directory.appendingPathComponent("default.store"))
}
