import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// The reference mirrors the starting 2026-09-22 view: three list projections,
// then a full child scan and source-task projection for every realized row.
// It intentionally preserves physical duplicates and equal-order input order.
private struct TemplateRowObservation: Equatable {
    let instanceID: UUID
    let drafts: [TemplateTaskDraft]
    let summary: TemplateApplicationSummary
}

private struct TemplateProjectionObservation: Equatable {
    let visibleIDs: [UUID]
    let rows: [TemplateRowObservation]

    var digest: String {
        var parts = visibleIDs.map(\.uuidString)
        for row in rows {
            parts.append(row.instanceID.uuidString)
            parts.append(String(row.summary.totalCount))
            parts.append(String(row.summary.newCount))
            for draft in row.drafts {
                parts.append(draft.id.uuidString)
                parts.append(draft.title)
                parts.append(draft.note)
                parts.append(draft.priority ?? "nil")
                parts.append(String(draft.estimatedMinutes ?? -1))
                parts.append(String(draft.order))
                parts.append(contentsOf: draft.tags)
                parts.append(contentsOf: draft.checklistTitles)
            }
        }
        return SHA256.hash(data: Data(parts.joined(separator: "\u{1f}").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private struct TemplateProjectionFixture {
    let container: ModelContainer
    var templates: [TaskTemplate]
    var items: [TaskTemplateItem]
    var tasks: [Task]
    let date: Date

    init(templateCount: Int, children: Int = 3, taskCount: Int = 240) throws {
        container = try PlanBaseContainerFactory.makeInMemory()
        date = try #require(DayKey.date(from: "2026-09-22"))
        templates = []
        items = []
        tasks = []
        let context = container.mainContext
        for index in 0..<templateCount {
            let template = TaskTemplate(
                id: projectionID(index + 1), instanceID: projectionID(index + 100_001),
                name: String(format: "루틴 %04d", index), isFavorite: index.isMultiple(of: 3),
                createdAt: date, updatedAt: date)
            context.insert(template)
            templates.append(template)
            for child in 0..<children {
                let itemIndex = index * children + child
                let item = TaskTemplateItem(
                    id: projectionID(itemIndex + 200_001), instanceID: projectionID(itemIndex + 300_001),
                    templateId: template.id, title: "항목 \(index)-\(child) 운동 café",
                    note: "메모 \(index)-\(child)", priority: child.isMultiple(of: 2) ? TaskPriority.high.rawValue : nil,
                    tags: ["태그 \(child)", "운동"], estimatedMinutes: child.isMultiple(of: 2) ? 15 : nil,
                    checklistTitles: ["준비 \(child)", "마무리"], order: Double(child % 2),
                    createdAt: date, updatedAt: date)
                context.insert(item)
                items.append(item)
            }
        }
        for index in 0..<taskCount {
            let task = Task(
                title: "항목 \(index % max(templateCount, 1))-0 운동 café",
                plannedAt: index.isMultiple(of: 5) ? DayKey.addingDays(-1, to: date) : date,
                order: Double(taskCount - index))
            if index.isMultiple(of: 7) { task.archivedAt = date }
            if index.isMultiple(of: 11) { task.supersededAt = date }
            context.insert(task)
            tasks.append(task)
        }
        try context.save()
    }
}

private func projectionID(_ index: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(index)))!
}

@MainActor
private func referenceTemplateProjection(
    _ fixture: TemplateProjectionFixture, query: String, scope: TemplateListScope, realizedRows: Int
) -> TemplateProjectionObservation {
    func visible() -> [TaskTemplate] {
        TemplateListRules.filterAndSort(fixture.templates, items: fixture.items, query: query, scope: scope)
    }
    guard !visible().isEmpty else { return .init(visibleIDs: [], rows: []) }
    let count = visible().count
    let templates = visible()
    precondition(count == templates.count)
    let rows = templates.prefix(realizedRows).map { template in
        let drafts = TemplateService.drafts(from: template, items: fixture.items)
        let sourceTasks = fixture.tasks.filter {
            $0.supersededAt == nil && $0.archivedAt == nil
                && $0.plannedDayKey == DayKey.key(for: fixture.date)
        }.sorted { $0.order < $1.order }
        return TemplateRowObservation(
            instanceID: template.instanceID, drafts: drafts,
            summary: TemplateApplicationRules.summary(drafts: drafts, dates: [fixture.date], tasks: sourceTasks))
    }
    return .init(visibleIDs: templates.map(\.instanceID), rows: rows)
}

// Match the production library's render-scoped preparation. The production
// grouping helper keeps drafting lazy for realized rows and must not deduplicate.
@MainActor
private func proposedTemplateProjection(
    _ fixture: TemplateProjectionFixture, query: String, scope: TemplateListScope, realizedRows: Int
) -> TemplateProjectionObservation {
    let templates = TemplateListRules.filterAndSort(
        fixture.templates, items: fixture.items, query: query, scope: scope)
    let grouped = templates.isEmpty ? [:] : TemplateListRules.itemsByTemplate(in: fixture.items)
    let selectedDayKey = DayKey.key(for: fixture.date)
    let sourceTasks = fixture.tasks.filter {
        $0.supersededAt == nil && $0.archivedAt == nil
            && $0.plannedDayKey == selectedDayKey
    }.sorted { $0.order < $1.order }
    let rows = templates.prefix(realizedRows).map { template in
        let drafts = TemplateService.drafts(from: template, items: grouped[template.id] ?? [])
        return TemplateRowObservation(
            instanceID: template.instanceID, drafts: drafts,
            summary: TemplateApplicationRules.summary(drafts: drafts, dates: [fixture.date], tasks: sourceTasks))
    }
    return .init(visibleIDs: templates.map(\.instanceID), rows: rows)
}

@Test @MainActor
func templateRowGroupingPreservesPhysicalDuplicatesMetadataAndLiveEdits() throws {
    var fixture = try TemplateProjectionFixture(templateCount: 30)
    let context = fixture.container.mainContext
    let duplicate = TaskTemplate(
        id: fixture.templates[0].id, instanceID: projectionID(900_001), name: fixture.templates[0].name,
        isFavorite: fixture.templates[0].isFavorite, createdAt: fixture.date, updatedAt: fixture.date)
    context.insert(duplicate)
    fixture.templates.append(duplicate)
    let duplicateChild = TaskTemplateItem(
        id: fixture.items[0].id, instanceID: projectionID(900_002), templateId: fixture.templates[0].id,
        title: "별도 물리 항목", note: "기존 물리 항목과 함께 유지", order: 0)
    let orphan = TaskTemplateItem(templateId: projectionID(999_999), title: "고아 전용", order: 0)
    let hidden = TaskTemplateItem(templateId: fixture.templates[0].id, title: "비활성 전용", order: 0,
                                  supersededAt: fixture.date)
    for item in [duplicateChild, orphan, hidden] { context.insert(item); fixture.items.append(item) }
    fixture.templates[2].supersededAt = fixture.date
    try context.save()

    for round in 0..<3 {
        if round == 1 {
            fixture.templates[0].name = "새 루틴 이름"
            fixture.templates[1].isFavorite.toggle()
            fixture.items[0].title = "변경된 운동 운동"
            fixture.items[0].note = "변경된 긴 메모 " + String(repeating: "내용 ", count: 100)
            fixture.items[0].tags = ["수정", "운동"]
            fixture.items[0].checklistTitles = ["수정된 준비", "추가된 단계"]
            fixture.items[0].estimatedMinutes = 60
            fixture.items[1].order = -10
            fixture.items[2].supersededAt = fixture.date
        } else if round == 2 {
            fixture.items[3].templateId = fixture.templates[0].id
            fixture.items[4].title = " "
            fixture.items[4].note = nil
            fixture.items[4].priority = nil
            let removed = fixture.items.remove(at: 5)
            context.delete(removed)
            let inserted = TaskTemplateItem(templateId: fixture.templates[1].id, title: "새 항목", order: 0)
            context.insert(inserted)
            fixture.items.insert(inserted, at: 0)
            fixture.tasks[1].title = "새 항목"
        }
        for query in ["", " \n", "항목", "새 루틴", "새 항목", "운동", "운동", "CAFÉ", "비활성 전용", "고아 전용", "없는검색"] {
            for scope in TemplateListScope.allCases {
                for limit in [0, 10, fixture.templates.count] {
                    let result = proposedTemplateProjection(fixture, query: query, scope: scope, realizedRows: limit)
                    let expected = referenceTemplateProjection(fixture, query: query, scope: scope, realizedRows: limit)
                    #expect(result == expected)
                }
            }
        }
    }
    let duplicateDrafts = proposedTemplateProjection(fixture, query: "새 루틴", scope: .all, realizedRows: 30)
        .rows.first?.drafts ?? []
    #expect(duplicateDrafts.filter { $0.id == duplicateChild.id }.count == 2)
    let empty = try TemplateProjectionFixture(templateCount: 0, taskCount: 0)
    #expect(proposedTemplateProjection(empty, query: "", scope: .all, realizedRows: 10)
            == referenceTemplateProjection(empty, query: "", scope: .all, realizedRows: 10))
}

@Test @MainActor
func templateQuickEntryImportGateContractPreservesRefreshAndSubmissionSafety() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let template = try SavedTaskLibraryService.create(
        draft: .init(title: "기존 운동", order: 0), isFavorite: false, quickEntryAlias: "운동", in: context)
    let controller = SavedTaskQuickEntryController()
    controller.update("/운동", in: context)
    #expect(controller.suggestions.first?.draft.title == "기존 운동")
    let item = try #require(context.fetch(FetchDescriptor<TaskTemplateItem>()).first)
    item.title = "가져온 운동"
    template.isFavorite = true
    try context.save()

    // Ignored events must leave the existing value snapshots intact even though
    // the model context already contains changed rows.
    for kind in [CloudKitSyncEventKind.setup, .export, .unknown, .import] {
        for completed in [false, true] {
            for succeeded in [false, true] {
                let summary = CloudKitSyncEventSummary(kind: kind, isCompleted: completed, succeeded: succeeded)
                if kind == .import && completed && succeeded { continue }
                controller.refresh(after: summary, in: context)
                #expect(controller.suggestions.first?.draft.title == "기존 운동")
            }
        }
    }
    let imported = CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: true)
    controller.refresh(after: imported, in: context)
    #expect(controller.suggestions.first?.draft.title == "가져온 운동")
    #expect(controller.suggestions.first?.isFavorite == true)
    template.quickEntryAlias = "바뀜"
    try context.save()
    // A matching title remains a valid explicitly selected suggestion. Here the
    // unselected exact alias must fail after the stored alias changes.
    #expect(controller.add(input: "/운동", on: Date(), in: context) == nil)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    controller.update("/바뀜", in: context)
    try SavedTaskLibraryService.delete(id: template.id, in: context)
    #expect(controller.add(input: "/바뀜", selectedID: template.id, on: Date(), in: context) == nil)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    controller.update("일반 입력", in: context)
    controller.refresh(in: context)
    #expect(controller.entries.isEmpty && !controller.isPresented)
}

/// Run serially, with no other build/test/benchmark. This models view preparation,
/// not rendered frames or input latency. Normal and stress fixtures have stable IDs.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_TEMPLATE_PROJECTION_PERFORMANCE"] == "1"))
@MainActor
func templateProjectionCompositionPerformance() throws {
    let algorithm = ProcessInfo.processInfo.environment["PLANBASE_TEMPLATE_PROJECTION_ALGORITHM"] ?? "reference"
    #expect(algorithm == "reference" || algorithm == "proposal")
    let operation = algorithm == "proposal" ? proposedTemplateProjection : referenceTemplateProjection
    for templateCount in [30, 1_000] {
        let fixture = try TemplateProjectionFixture(templateCount: templateCount)
        for (queryName, query) in [("empty", ""), ("item", "항목 1"), ("absent", "없는검색")] {
            for realizedRows in [10, templateCount] {
                let expected = referenceTemplateProjection(fixture, query: query, scope: .all, realizedRows: realizedRows)
                // One untimed warm-up. Digest and result comparisons are outside timed intervals.
                #expect(operation(fixture, query, .all, realizedRows) == expected)
                var samples: [Double] = []
                for _ in 0..<20 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let result = operation(fixture, query, .all, realizedRows)
                    samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                    #expect(result == expected)
                }
                let ordered = samples.sorted()
                let median = (ordered[9] + ordered[10]) / 2
                print("TEMPLATE_PROJECTION_BENCHMARK algorithm=\(algorithm) templates=\(templateCount) items=\(fixture.items.count) tasks=\(fixture.tasks.count) query=\(queryName) realizedLimit=\(realizedRows) realized=\(expected.rows.count) visible=\(expected.visibleIDs.count) unit=ms n=20 p50=\(median) p95=\(ordered[18]) digest=\(expected.digest) samples=\(samples)")
            }
        }
    }
}
