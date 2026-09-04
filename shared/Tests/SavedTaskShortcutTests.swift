import CryptoKit
import CoreData
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor func shortcutSchemaAddsOnlyOptionalTemplateAlias() throws {
    let old = try #require(NSManagedObjectModel.makeManagedObjectModel(for: EasyTaskSchemaV10.models))
    let current = try #require(NSManagedObjectModel.makeManagedObjectModel(for: EasyTaskSchemaV11.models))
    #expect(Set(old.entitiesByName.keys) == Set(current.entitiesByName.keys))
    let template = try #require(current.entitiesByName["TaskTemplate"])
    let oldTemplate = try #require(old.entitiesByName["TaskTemplate"])
    #expect(Set(template.attributesByName.keys) == Set(oldTemplate.attributesByName.keys).union(["quickEntryAlias"]))
    let alias = try #require(template.attributesByName["quickEntryAlias"])
    #expect(alias.isOptional && alias.attributeType == .stringAttributeType)
    #expect(template.uniquenessConstraints.isEmpty)
    for (name, entity) in old.entitiesByName where name != "TaskTemplate" {
        #expect(entity.versionHash == current.entitiesByName[name]?.versionHash)
    }
}

@Test func shortcutNormalizationAndOrdinaryInput() throws {
    #expect(try SavedTaskShortcutRules.normalizedAlias(" /Weekly ") == "weekly")
    #expect(try SavedTaskShortcutRules.normalizedAlias("운동-1_회") == "운동-1_회")
    #expect(try SavedTaskShortcutRules.normalizedAlias("운동") == "운동")
    #expect(try SavedTaskShortcutRules.normalizedAlias("") == nil)
    #expect(SavedTaskShortcutRules.query(in: "일반 작업 / 메모") == nil)
    #expect(SavedTaskShortcutRules.query(in: " /WORK ") == "work")
    for invalid in ["/", "두 단어", "a/b", "🙂", String(repeating: "가", count: 25)] {
        #expect(throws: SavedTaskShortcutRules.Failure.self) {
            try SavedTaskShortcutRules.normalizedAlias(invalid)
        }
    }
}

@Test @MainActor func shortcutDuplicateRejectionAndEditingPreservesExistingData() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let first = try SavedTaskLibraryService.create(draft: .init(title: "운동", order: 100),
        isFavorite: false, quickEntryAlias: "WORK", in: context)
    #expect(first.quickEntryAlias == "work")
    #expect(throws: SavedTaskShortcutRules.Failure.self) {
        try SavedTaskLibraryService.create(draft: .init(title: "중복", order: 100),
            isFavorite: false, quickEntryAlias: "/Work", in: context)
    }
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplateItem>()) == 1)
    try SavedTaskLibraryService.update(id: first.id, draft: .init(title: "바꾼 운동", order: 100), isFavorite: true, in: context)
    #expect(first.quickEntryAlias == "work")
    try SavedTaskLibraryService.update(id: first.id, draft: .init(title: "바꾼 운동", order: 100),
        isFavorite: true, quickEntryAlias: "", in: context)
    #expect(first.quickEntryAlias == nil)
}

@Test @MainActor func shortcutCreatesIndependentTasksOnSelectedDateWithFullContents() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let entry = try SavedTaskLibraryService.create(
        draft: .init(title: "헬스장 운동", note: "운동복 챙기기", priority: TaskPriority.high.rawValue,
                     tags: ["건강"], estimatedMinutes: 60, checklistTitles: ["준비", "마무리"], order: 100),
        isFavorite: true, quickEntryAlias: "운동", in: context)
    let date = try #require(DayKey.date(from: "2026-10-20"))
    let state = SavedTaskQuickEntryController()
    state.update("/운", in: context)
    #expect(state.suggestions.first?.id == entry.id)
    #expect(state.add(input: "/운", on: date, in: context) == nil)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    let first = try #require(state.add(input: "/운동", on: date, in: context))
    let second = try #require(state.add(input: "/운동", on: date, in: context))
    #expect(first.id != second.id)
    #expect(first.title == "헬스장 운동")
    #expect(first.plannedDayKey == "2026-10-20")
    #expect(first.status == TaskStatus.todo.rawValue)
    #expect(first.note == "운동복 챙기기" && first.estimatedMinutes == 60)
    #expect(first.tags == ["건강"] && first.priority == TaskPriority.high.rawValue)
    #expect(first.reminderAt == nil && first.templatePlacementId == nil)
    let checks = try TaskChecklistService.items(for: first.id, in: context)
    #expect(checks.count == 2 && checks.allSatisfy { !$0.isCompleted })
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 0)
}

@Test @MainActor func shortcutResolvesCloudConflictsAndStaleSuggestionsSafely() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let a = try SavedTaskLibraryService.create(draft: .init(title: "첫 작업", order: 100), isFavorite: false, quickEntryAlias: "같음", in: context)
    let b = try SavedTaskLibraryService.create(draft: .init(title: "둘째 작업", order: 100), isFavorite: false, in: context)
    b.quickEntryAlias = "같음" // Simulate two devices independently choosing the same alias.
    try context.save()
    _ = try DataIntegrityService.reconcile(context: context)
    let state = SavedTaskQuickEntryController()
    state.update("/같음", in: context)
    #expect(state.add(input: "/같음", on: Date(), in: context) == nil)
    #expect(state.failure?.contains("여러 개") == true)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    #expect(state.moveSelection(by: 1))
    #expect(state.add(input: "/같음", on: Date(), in: context) != nil)
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 2)
    state.update("/같음", in: context)
    a.quickEntryAlias = "새입력어"
    b.quickEntryAlias = "다른입력어"
    try context.save()
    #expect(state.add(input: "/같음", on: Date(), in: context) == nil)
    state.update("/새입력어", in: context)
    try SavedTaskLibraryService.delete(id: a.id, in: context)
    #expect(state.add(input: "/새입력어", selectedID: a.id, on: Date(), in: context) == nil)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
}

@Test @MainActor func shortcutBackupRoundTripClearAndLegacyMerge() throws {
    let source = try PlanBaseContainerFactory.makeInMemory()
    let entry = try SavedTaskLibraryService.create(draft: .init(title: "운동", order: 100), isFavorite: true,
        quickEntryAlias: "운동", in: source.mainContext)
    let package = try BackupPackageCodec.makeContents(context: source.mainContext)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try BackupPackageCodec.write(package, to: url)
    let decoded = try BackupPackageCodec.read(from: url)
    #expect(decoded.manifest.formatVersion == 10)
    let destination = try PlanBaseContainerFactory.makeInMemory()
    _ = try BackupPackageCodec.restoreMerging(decoded, into: destination.mainContext)
    let restored = try #require(destination.mainContext.fetch(FetchDescriptor<TaskTemplate>()).first)
    #expect(restored.quickEntryAlias == "운동")

    var legacy = package
    legacy.manifest.formatVersion = 9
    legacy.records.formatVersion = 9
    legacy.records.payload.taskTemplates[0].quickEntryAlias = nil
    legacy.records.payload.taskTemplates[0].name = "구버전 편집"
    legacy.records.payload.taskTemplates[0].updatedAt = entry.updatedAt.addingTimeInterval(10)
    refreshShortcutMetadata(&legacy)
    _ = try BackupPackageCodec.restoreMerging(legacy, into: destination.mainContext)
    #expect(restored.quickEntryAlias == "운동")
    #expect(restored.name == "구버전 편집")

    entry.quickEntryAlias = nil
    entry.updatedAt = entry.updatedAt.addingTimeInterval(20)
    let cleared = try BackupPackageCodec.makeContents(context: source.mainContext)
    #expect(cleared.records.payload.taskTemplates[0].quickEntryAlias == "")
    _ = try BackupPackageCodec.restoreMerging(cleared, into: destination.mainContext)
    #expect(restored.quickEntryAlias == nil)
}

@Test @MainActor func shortcutV10MigrationPreservesTemplatesAndReopensAlias() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("store.sqlite")
    let id = UUID(), instanceID = UUID()
    try autoreleasepool {
        let schema = Schema(versionedSchema: EasyTaskSchemaV10.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let old = try ModelContainer(for: schema, configurations: configuration)
        old.mainContext.insert(EasyTaskSchemaV5.TaskTemplate(id: id, instanceID: instanceID, name: "기존 작업", isFavorite: true))
        old.mainContext.insert(TaskTemplateItem(templateId: id, title: "기존 작업", estimatedMinutes: 30,
                                                checklistTitles: ["기존 체크"], order: 100))
        try old.mainContext.save()
    }
    try autoreleasepool {
        let current = try PlanBaseContainerFactory.makePersistent(storeURL: url)
        let entry = try #require(current.mainContext.fetch(FetchDescriptor<TaskTemplate>()).first)
        #expect(entry.id == id && entry.instanceID == instanceID && entry.isFavorite)
        #expect(entry.quickEntryAlias == nil)
        let item = try #require(current.mainContext.fetch(FetchDescriptor<TaskTemplateItem>()).first)
        #expect(item.templateId == id && item.estimatedMinutes == 30 && item.checklistTitles == ["기존 체크"])
        entry.quickEntryAlias = "기존"
        try current.mainContext.save()
    }
    let reopened = try PlanBaseContainerFactory.makePersistent(storeURL: url)
    #expect(try reopened.mainContext.fetch(FetchDescriptor<TaskTemplate>()).first?.quickEntryAlias == "기존")
}

private func refreshShortcutMetadata(_ contents: inout BackupPackageContents) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(contents.records)
    contents.manifest.recordsByteCount = data.count
    contents.manifest.recordsSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
