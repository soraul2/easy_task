#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Serial, opt-in controller microbenchmarks on an isolated in-memory library.
/// Library loading, state reset, expected outputs, and digest checks are untimed.
/// This measures 100 controller operations, not SwiftUI body counts or input-to-frame latency.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_QUICK_ENTRY_PERFORMANCE"] == "1"))
@MainActor
func goalQuickEntryPerformance() throws {
    for entryCount in [100, 1_000] {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        context.autosaveEnabled = false
        try seedGoalQuickEntryLibrary(count: entryCount, in: context)

        let controller = SavedTaskQuickEntryController()
        controller.update("/", in: context) // The actual library load is outside every timed interval.
        #expect(controller.failure == nil && controller.entries.count == entryCount)
        let entries = controller.entries

        let inputCycle = [
            "/", "/p", "/pe", "/per", "/perf", "/perf1", "/perf12", "/perf1",
            "/perf", "/per", "/pe", "/p", "/운", "/운동", "/운동", "/없는검색",
        ]
        let inputs = (0..<100).map { inputCycle[$0 % inputCycle.count] }
        let expectedInput = inputs.map {
            GoalQuickEntryObservation(
                input: $0, highlightedID: nil,
                suggestions: SavedTaskShortcutRules.suggestions(entries, input: $0),
                isPresented: true, failure: nil, selectionMoved: nil)
        }
        try reportGoalQuickEntrySamples(
            name: "input-changes-and-suggestions", entryCount: entryCount,
            expected: expectedInput,
            prepare: { controller.update("/__reset_goal_query__", in: context) },
            operation: {
                var observations: [GoalQuickEntryObservation] = []
                observations.reserveCapacity(inputs.count)
                for input in inputs {
                    controller.update(input, in: context)
                    observations.append(GoalQuickEntryObservation(controller, suggestions: controller.suggestions))
                }
                return observations
            })

        // Broad and narrow result sets expose sorting costs and selection clamping separately.
        for (queryName, query) in [("all", "/"), ("prefix", "/perf1")] {
            let ranked = SavedTaskShortcutRules.suggestions(entries, input: query)
            let offsets = (0..<100).map { $0 < 75 ? 1 : -1 }
            var expectedIndex: Int?
            let expectedHighlight = offsets.map { offset in
                if !ranked.isEmpty {
                    expectedIndex = expectedIndex.map { min(max($0 + offset, 0), ranked.count - 1) }
                        ?? (offset > 0 ? 0 : ranked.count - 1)
                }
                return GoalQuickEntryObservation(
                    input: query, highlightedID: expectedIndex.map { ranked[$0].id },
                    suggestions: ranked, isPresented: true, failure: nil, selectionMoved: true)
            }
            try reportGoalQuickEntrySamples(
                name: "highlight-and-suggestions-\(queryName)", entryCount: entryCount,
                expected: expectedHighlight,
                prepare: {
                    controller.update("/__reset_goal_query__", in: context)
                    controller.update(query, in: context)
                },
                operation: {
                    var observations: [GoalQuickEntryObservation] = []
                    observations.reserveCapacity(offsets.count)
                    for offset in offsets {
                        let moved = controller.moveSelection(by: offset)
                        observations.append(GoalQuickEntryObservation(
                            controller, suggestions: controller.suggestions, selectionMoved: moved))
                    }
                    return observations
                })
        }
        #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
        #expect(!context.hasChanges)
    }
}

private struct GoalQuickEntryObservation {
    var input: String
    var highlightedID: UUID?
    var suggestions: [SavedTaskEntry]
    var isPresented: Bool
    var failure: String?
    var selectionMoved: Bool?

    init(input: String, highlightedID: UUID?, suggestions: [SavedTaskEntry],
         isPresented: Bool, failure: String?, selectionMoved: Bool?) {
        self.input = input
        self.highlightedID = highlightedID
        self.suggestions = suggestions
        self.isPresented = isPresented
        self.failure = failure
        self.selectionMoved = selectionMoved
    }

    @MainActor
    init(_ controller: SavedTaskQuickEntryController, suggestions: [SavedTaskEntry], selectionMoved: Bool? = nil) {
        self.init(input: controller.input, highlightedID: controller.highlightedID, suggestions: suggestions,
                  isPresented: controller.isPresented, failure: controller.failure, selectionMoved: selectionMoved)
    }
}

@MainActor
private func reportGoalQuickEntrySamples(
    name: String,
    entryCount: Int,
    expected: [GoalQuickEntryObservation],
    prepare: () -> Void,
    operation: () -> [GoalQuickEntryObservation]
) throws {
    let expectedDigest = goalQuickEntryDigest(expected)
    func validate(_ observations: [GoalQuickEntryObservation]) throws {
        try #require(observations.count == expected.count)
        for (actual, reference) in zip(observations, expected) {
            #expect(actual.input == reference.input)
            #expect(actual.highlightedID == reference.highlightedID)
            #expect(actual.suggestions.map(\.id) == reference.suggestions.map(\.id))
            #expect(actual.isPresented == reference.isPresented)
            #expect(actual.failure == reference.failure)
            #expect(actual.selectionMoved == reference.selectionMoved)
        }
        #expect(goalQuickEntryDigest(observations) == expectedDigest)
    }

    prepare()
    try validate(operation()) // One untimed warm-up, with the same observable contract.
    var samples: [Double] = []
    for _ in 0..<30 {
        prepare()
        let start = DispatchTime.now().uptimeNanoseconds
        let observations = operation()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        try validate(observations) // Rank/selection comparison and SHA are outside the interval.
    }
    let ordered = samples.sorted()
    let median = (ordered[14] + ordered[15]) / 2
    let operationCount = expected.count
    let perOperation = samples.map { $0 / Double(operationCount) }
    print("GOAL_QUICK_ENTRY_BENCHMARK name=\(name) entries=\(entryCount) operationsPerSample=\(operationCount) libraryLoadTimed=false unit=batch-ms n=30 p50=\(median) p95=\(ordered[28]) max=\(ordered[29]) perOperationUnit=ms perOperationP50=\(median / Double(operationCount)) perOperationP95=\(ordered[28] / Double(operationCount)) perOperationMax=\(ordered[29] / Double(operationCount)) rankSelectionDigest=\(expectedDigest) samples=\(samples) perOperationSamples=\(perOperation)")
}

private func goalQuickEntryDigest(_ observations: [GoalQuickEntryObservation]) -> String {
    let payload = observations.enumerated().map { index, value in
        let rankedIDs = value.suggestions.map { $0.id.uuidString }.joined(separator: ",")
        return "\(index)|\(value.input)|\(value.highlightedID?.uuidString ?? "-")|\(value.isPresented)|\(value.failure ?? "-")|\(value.selectionMoved.map { String($0) } ?? "-")|\(rankedIDs)"
    }.joined(separator: "\n")
    return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
}

@MainActor
private func seedGoalQuickEntryLibrary(count: Int, in context: ModelContext) throws {
    let now = Date(timeIntervalSince1970: 1_788_400_000)
    for index in 0..<count {
        let id = goalQuickEntryFixtureID(namespace: 1, index: index)
        let title = index % 10 == 0 ? "성능 작업 공통" : String(format: "성능 작업 %04d", index)
        let alias = index == 0 ? "운동" : index == 1 ? "건강" : "perf\(index)"
        context.insert(TaskTemplate(
            id: id, instanceID: goalQuickEntryFixtureID(namespace: 2, index: index),
            name: title, isFavorite: index % 7 == 0, quickEntryAlias: alias,
            createdAt: now, updatedAt: now))
        context.insert(TaskTemplateItem(
            id: goalQuickEntryFixtureID(namespace: 3, index: index),
            instanceID: goalQuickEntryFixtureID(namespace: 4, index: index),
            templateId: id, title: title, note: "측정용 메모 \(index)", tags: ["측정"],
            estimatedMinutes: 30, checklistTitles: ["준비", "마무리"],
            order: Double(index + 1) * 100, createdAt: now, updatedAt: now))
    }
    try context.save()
}

private func goalQuickEntryFixtureID(namespace: Int, index: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-%04X-%012X", namespace, index + 1))!
}
#endif
