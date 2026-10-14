#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Shipping APIs in one binary over two independently owned, identical stores.
/// No UI, CloudKit, hardware cold boot, notification or frame latency is measured.
/// Enable explicitly and run alone after other builds/measurements have stopped.
private let submissionBenchmarkEnabled20261013002 =
    ProcessInfo.processInfo.environment["PLANBASE_SUBMISSION_BENCHMARK_20261013_002"] == "1"

@Test(.enabled(if: submissionBenchmarkEnabled20261013002)) @MainActor
func goalLatencySubmissionComparison20261013002() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseSubmissionLatency-20261013-002-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let date = try #require(DayKey.date(from: "2026-10-12"))
    for libraryCount in [100, 1_000] {
        for selected in [false, true] {
            try autoreleasepool {
                let selection = selected ? "selected-partial-alias" : "exact-alias"
                let oldContainer = try PlanBaseContainerFactory.makePersistent(
                    storeURL: directory.appendingPathComponent("\(libraryCount)-\(selection)-old.store"), mode: .local)
                let newContainer = try PlanBaseContainerFactory.makePersistent(
                    storeURL: directory.appendingPathComponent("\(libraryCount)-\(selection)-new.store"), mode: .local)
                let oldFixture = try seedSubmissionBenchmark(count: libraryCount, date: date, in: oldContainer.mainContext)
                let newFixture = try seedSubmissionBenchmark(count: libraryCount, date: date, in: newContainer.mainContext)
                try #require(oldFixture == newFixture, "Identical canonical fixture inputs are required.")
                // Both measured contexts are fresh after the owned stores are
                // seeded. The seed/save can warm process and filesystem caches.
                let oldContext = ModelContext(oldContainer)
                let newContext = ModelContext(newContainer)
                oldContext.autosaveEnabled = false; newContext.autosaveEnabled = false
                let input = selected ? "/perf" : "/perf12"
                let selectedID = selected ? submissionBenchmarkID(namespace: 1, index: 12) : nil
                var oldTimes = SubmissionBenchmarkTimes()
                var newTimes = SubmissionBenchmarkTimes()
                var canonicalOutputs: [String] = []
                // Sample 0 is the first API observation, samples 1...2 are
                // explicit warmups, and samples 3...22 are n20 repeats.
                for sample in 0..<23 {
                    var oldValue: SubmissionBenchmarkTaskValue?
                    var newValue: SubmissionBenchmarkTaskValue?
                    let runOld = {
                        let start = DispatchTime.now().uptimeNanoseconds
                        // This mirrors the previous successful controller's
                        // reload, prepared aliases, suggestions, ID validation,
                        // then add(id:). It includes both command saves.
                        let entries = try SavedTaskLibraryService.load(in: oldContext)
                        let keys = SavedTaskShortcutRules.aliasKeys(in: entries)
                        let suggestions = SavedTaskShortcutRules.suggestions(
                            entries, input: input, preparedAliasKeys: keys)
                        let id: UUID
                        if let selectedID {
                            guard suggestions.contains(where: { $0.id == selectedID }) else {
                                throw SavedTaskLibraryService.Failure.unavailable
                            }
                            id = selectedID
                        } else {
                            id = try SavedTaskShortcutRules.exactMatch(in: entries, input: input)
                        }
                        let task = try SavedTaskLibraryService.add(id: id, on: date, in: oldContext)
                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                        oldTimes.record(elapsed, sample: sample)
                        oldValue = try submissionBenchmarkValue(task: task, sample: sample, in: oldContext)
                    }
                    let runNew = {
                        let start = DispatchTime.now().uptimeNanoseconds
                        let task = try SavedTaskLibraryService.add(
                            input: input, selectedID: selectedID, on: date, in: newContext)
                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                        newTimes.record(elapsed, sample: sample)
                        newValue = try submissionBenchmarkValue(task: task, sample: sample, in: newContext)
                    }
                    // Alternate within each pair to reduce systematic ordering
                    // bias. All measurement and validation are serial.
                    if sample.isMultiple(of: 2) { try runOld(); try runNew() }
                    else { try runNew(); try runOld() }
                    let old = try #require(oldValue)
                    let new = try #require(newValue)
                    try #require(old == new, "Canonical task/checklist/history parity for sample \(sample)")
                    canonicalOutputs.append(try submissionBenchmarkDigest(old))
                }
                let outputDigest = try submissionBenchmarkDigest(canonicalOutputs)
                for (variant, times) in [("full-library-resolution-and-add", oldTimes),
                                         ("dedicated-resolution-and-add", newTimes)] {
                    let report = SubmissionBenchmarkReport(
                        variant: variant, libraryCount: libraryCount, selection: selection,
                        input: input, fixtureInputSHA256: oldFixture,
                        firstMs: times.first, warmupMs: times.warmups, rawMs: times.repeats,
                        p50Ms: times.p50, p95Ms: times.p95, maximumMs: times.maximum,
                        canonicalPairCount: canonicalOutputs.count,
                        canonicalOutputsSHA256: outputDigest, canonicalOutputSHA256BySample: canonicalOutputs)
                    print("GOAL_SUBMISSION_LATENCY_RESULT " + String(decoding: try submissionBenchmarkJSON(report), as: UTF8.self))
                }
                withExtendedLifetime((oldContext, newContext, oldContainer, newContainer)) {}
            }
        }
    }
}

private struct SubmissionBenchmarkTimes {
    var first = 0.0
    var warmups: [Double] = []
    var repeats: [Double] = []
    mutating func record(_ value: Double, sample: Int) {
        if sample == 0 { first = value }
        else if sample < 3 { warmups.append(value) }
        else { repeats.append(value) }
    }
    var p50: Double { let values = repeats.sorted(); return (values[9] + values[10]) / 2 }
    var p95: Double { repeats.sorted()[18] }
    var maximum: Double { repeats.max() ?? 0 }
}

private struct SubmissionBenchmarkReport: Encodable {
    let protocolID = "shipping-submission-api-20261013-002"
    let variant: String
    let sourceLabel = ProcessInfo.processInfo.environment["PLANBASE_GOAL_SOURCE_LABEL"] ?? "unspecified"
    let unit = "ms"
    let scope = "shipping synchronous API wall time; MainActor; own local SwiftData store; fresh contexts then reused"
    let libraryCount: Int
    let initialTaskCount = 0
    let selection: String
    let input: String
    let fixtureInputSHA256: String
    let referenceDayKey = "2026-10-12"
    let n = 20
    let firstMs: Double
    let firstMeaning = "first submission after seed/save and independent fixture validation; measured context fresh; store/process/filesystem caches warm"
    let warmupN = 2
    let warmupMs: [Double]
    let firstAndWarmupsExcludedFromRepeatStatistics = true
    let rawMs: [Double]
    let p50Ms: Double
    let p95Ms: Double
    let maximumMs: Double
    let p95Method = "nearest-rank; n20 second-largest; finite-sample tail only"
    let setupTimed = false
    let validationTimed = false
    let fixtureAndValidationCanWarmCaches = true
    let pairOrder = "old-new even sample; new-old odd sample; entirely serial"
    let commandPreSaveMutationAndFinalSaveTimed = true
    let firstWarmupsAndRepeatsEachAppendOneTask = true
    let totalCreatedTasksPerVariant = 23
    let canonicalParity = true
    let canonicalPairCount: Int
    let canonicalOutputsSHA256: String
    let canonicalOutputSHA256BySample: [String]
    let canonicalOmissions = ["new Task and checklist logical/physical IDs", "new creation/update timestamps"]
    let physicalColdBoot = false
    let uiOrInputToFrameMeasured = false
    let mainThreadContinuousCPUOrStallMeasured = false
    let systemSideEffectsOrCloudKitMeasured = false
}

private struct SubmissionBenchmarkFixtureValue: Encodable {
    let id: UUID
    let instanceID: UUID
    let itemID: UUID
    let itemInstanceID: UUID
    let title: String
    let alias: String
    let isFavorite: Bool
    let note: String
    let priority: String
    let tags: [String]
    let estimatedMinutes: Int
    let checklistTitles: [String]
    let itemOrder: Double
    let fixedTimestamp: Double
}

@MainActor
private func seedSubmissionBenchmark(count: Int, date: Date, in context: ModelContext) throws -> String {
    context.autosaveEnabled = false
    var fixture: [SubmissionBenchmarkFixtureValue] = []
    for index in 0..<count {
        let title = String(format: "Latency library %04d", index)
        let row = SubmissionBenchmarkFixtureValue(
            id: submissionBenchmarkID(namespace: 1, index: index),
            instanceID: submissionBenchmarkID(namespace: 2, index: index),
            itemID: submissionBenchmarkID(namespace: 3, index: index),
            itemInstanceID: submissionBenchmarkID(namespace: 4, index: index),
            title: title, alias: "perf\(index)", isFavorite: index % 7 == 0,
            note: "Synthetic note", priority: TaskPriority.high.rawValue, tags: ["Synthetic", "latency"],
            estimatedMinutes: 25, checklistTitles: ["First", "Second"], itemOrder: Double(index),
            fixedTimestamp: date.timeIntervalSinceReferenceDate)
        fixture.append(row)
        context.insert(TaskTemplate(id: row.id, instanceID: row.instanceID, name: row.title,
            isFavorite: row.isFavorite, quickEntryAlias: row.alias, createdAt: date, updatedAt: date))
        context.insert(TaskTemplateItem(id: row.itemID, instanceID: row.itemInstanceID, templateId: row.id,
            title: row.title, note: row.note, priority: row.priority, tags: row.tags,
            estimatedMinutes: row.estimatedMinutes, checklistTitles: row.checklistTitles,
            order: row.itemOrder, createdAt: date, updatedAt: date))
    }
    try context.save()
    try #require(!context.hasChanges)
    try #require(context.fetchCount(FetchDescriptor<TaskTemplate>()) == count)
    try #require(context.fetchCount(FetchDescriptor<TaskTemplateItem>()) == count)
    // Validate the persisted fixture in a separate context before measuring.
    // This deliberately warms store caches and is declared in the first result.
    let reader = ModelContext(context.container)
    reader.autosaveEnabled = false
    let templates = try reader.fetch(FetchDescriptor<TaskTemplate>()).sorted { $0.id.uuidString < $1.id.uuidString }
    let items = Dictionary(grouping: try reader.fetch(FetchDescriptor<TaskTemplateItem>()), by: \.templateId)
    var stored: [SubmissionBenchmarkFixtureValue] = []
    for template in templates {
        let children = try #require(items[template.id])
        try #require(children.count == 1)
        let item = try #require(children.first)
        try #require(template.name == item.title && template.createdAt == date && template.updatedAt == date)
        try #require(item.createdAt == date && item.updatedAt == date)
        try #require(template.supersededAt == nil && item.supersededAt == nil)
        stored.append(SubmissionBenchmarkFixtureValue(id: template.id, instanceID: template.instanceID,
            itemID: item.id, itemInstanceID: item.instanceID, title: item.title,
            alias: try #require(template.quickEntryAlias), isFavorite: template.isFavorite,
            note: item.note ?? "", priority: try #require(item.priority), tags: item.tags,
            estimatedMinutes: try #require(item.estimatedMinutes), checklistTitles: item.checklistTitles,
            itemOrder: item.order, fixedTimestamp: template.createdAt.timeIntervalSinceReferenceDate))
    }
    let expected = try submissionBenchmarkDigest(fixture.sorted { $0.id.uuidString < $1.id.uuidString })
    let actual = try submissionBenchmarkDigest(stored)
    try #require(expected == actual && !reader.hasChanges, "Persisted synthetic fixture must match every canonical input field.")
    return actual
}

private struct SubmissionBenchmarkTaskValue: Encodable, Equatable {
    let title: String
    let note: String?
    let priority: String?
    let tags: [String]
    let estimatedMinutes: Int?
    let status: String
    let plannedDayKey: String
    let order: Double
    let reminderAt: Date?
    let completedAt: Date?
    let archivedAt: Date?
    let templatePlacementID: UUID?
    let eventID: UUID?
    let checklistTitles: [String]
    let checklistOrders: [Double]
    let checklistIsCompleted: [Bool]
    let checklistCompletedAt: [Date?]
    let totalTaskCount: Int
    let totalChecklistCount: Int
    let progressCount: Int
    let completionCount: Int
    let focusCount: Int
    let placementCount: Int
}

@MainActor
private func submissionBenchmarkValue(task: Task, sample: Int, in context: ModelContext) throws -> SubmissionBenchmarkTaskValue {
    let checklist = try TaskChecklistService.items(for: task.id, in: context)
    let value = try SubmissionBenchmarkTaskValue(
        title: task.title, note: task.note, priority: task.priority, tags: task.tags,
        estimatedMinutes: task.estimatedMinutes, status: task.status, plannedDayKey: task.plannedDayKey,
        order: task.order, reminderAt: task.reminderAt, completedAt: task.completedAt, archivedAt: task.archivedAt,
        templatePlacementID: task.templatePlacementId, eventID: task.eventId,
        checklistTitles: checklist.map(\.title), checklistOrders: checklist.map(\.order),
        checklistIsCompleted: checklist.map(\.isCompleted), checklistCompletedAt: checklist.map(\.completedAt),
        totalTaskCount: context.fetchCount(FetchDescriptor<Task>()),
        totalChecklistCount: context.fetchCount(FetchDescriptor<TaskChecklistItem>()),
        progressCount: context.fetchCount(FetchDescriptor<TaskProgressEvent>()),
        completionCount: context.fetchCount(FetchDescriptor<TaskCompletionActivity>()),
        focusCount: context.fetchCount(FetchDescriptor<FocusSession>()),
        placementCount: context.fetchCount(FetchDescriptor<TemplatePlacement>()))
    try #require(value.title == "Latency library 0012" && value.note == "Synthetic note")
    try #require(value.priority == TaskPriority.high.rawValue && value.tags == ["Synthetic", "latency"])
    try #require(value.estimatedMinutes == 25 && value.status == TaskStatus.todo.rawValue)
    try #require(value.plannedDayKey == "2026-10-12" && value.checklistTitles == ["First", "Second"])
    try #require(value.totalTaskCount == sample + 1 && value.totalChecklistCount == (sample + 1) * 2)
    try #require(value.progressCount == 0 && value.completionCount == 0 && value.focusCount == 0 && value.placementCount == 0)
    try #require(value.reminderAt == nil && value.completedAt == nil && value.archivedAt == nil)
    try #require(value.templatePlacementID == nil && value.eventID == nil && !context.hasChanges)
    return value
}

private func submissionBenchmarkID(namespace: Int, index: Int) -> UUID {
    UUID(uuidString: String(format: "A6000000-%04X-4000-8000-%012X", namespace, index + 1))!
}

private func submissionBenchmarkJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func submissionBenchmarkDigest<T: Encodable>(_ value: T) throws -> String {
    SHA256.hash(data: try submissionBenchmarkJSON(value)).map { String(format: "%02x", $0) }.joined()
}
#endif
