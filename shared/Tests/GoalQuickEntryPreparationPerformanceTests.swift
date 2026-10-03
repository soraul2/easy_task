#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// First command entry on a fresh controller, with actual library fetch and
/// command preparation in the interval. Seed, expectations, controller creation,
/// complete value/rank digests are outside the interval. Candidate output capture
/// is timed because the baseline computes suggestions in its getter, whereas
/// the candidate computes them in update. Both must finish the same work.
/// Each sample reuses a saved memory store: this is controller-first entry, not
/// a cold process/database launch, SwiftUI render count, or input-to-frame time.
/// Only public controller/rules APIs are used so the identical harness can run
/// against the frozen baseline that has no prepared-alias implementation.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_QUICK_ENTRY_PREPARATION_PERFORMANCE"] == "1"))
@MainActor
func goalQuickEntryPreparationPerformance() throws {
    for entryCount in [100, 1_000] {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        context.autosaveEnabled = false
        try seedGoalQuickEntryPreparationLibrary(count: entryCount, in: context)
        let entries = try SavedTaskLibraryService.load(in: context) // Untimed expected value snapshots.
        try #require(entries.count == entryCount)
        for (name, input, preparesLibrary) in [
            ("first-all", "/", true),
            ("first-specific", "/perf12", true),
            ("ordinary-input-control", "일반 작업", false),
        ] {
            let expected = GoalQuickEntryPreparationState(
                input: input, entries: preparesLibrary ? entries : [],
                suggestions: preparesLibrary ? SavedTaskShortcutRules.suggestions(entries, input: input) : [],
                isPresented: preparesLibrary, highlightedID: nil, failure: nil)
            try reportGoalQuickEntryPreparation(
                name: name, input: input, entryCount: entryCount, preparesLibrary: preparesLibrary,
                expected: expected, in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
        #expect(!context.hasChanges)
    }
}

private struct GoalQuickEntryPreparationState {
    let input: String
    let entries: [SavedTaskEntry]
    let suggestions: [SavedTaskEntry]
    let isPresented: Bool
    let highlightedID: UUID?
    let failure: String?

    init(input: String, entries: [SavedTaskEntry], suggestions: [SavedTaskEntry],
         isPresented: Bool, highlightedID: UUID?, failure: String?) {
        self.input = input
        self.entries = entries
        self.suggestions = suggestions
        self.isPresented = isPresented
        self.highlightedID = highlightedID
        self.failure = failure
    }

    @MainActor
    init(_ controller: SavedTaskQuickEntryController) {
        self.init(input: controller.input, entries: controller.entries, suggestions: controller.suggestions,
                  isPresented: controller.isPresented, highlightedID: controller.highlightedID, failure: controller.failure)
    }
}

@MainActor
private func reportGoalQuickEntryPreparation(
    name: String, input: String, entryCount: Int, preparesLibrary: Bool,
    expected: GoalQuickEntryPreparationState, in context: ModelContext
) throws {
    let expectedDigest = try goalQuickEntryPreparationDigest(expected)
    func validate(_ actual: GoalQuickEntryPreparationState) throws {
        #expect(actual.input == expected.input)
        #expect(actual.entries.map(\.id) == expected.entries.map(\.id))
        #expect(actual.entries.map(\.draft) == expected.entries.map(\.draft))
        #expect(actual.entries.map(\.isFavorite) == expected.entries.map(\.isFavorite))
        #expect(actual.entries.map(\.quickEntryAlias) == expected.entries.map(\.quickEntryAlias))
        #expect(actual.suggestions.map(\.id) == expected.suggestions.map(\.id))
        #expect(actual.suggestions.map(\.draft) == expected.suggestions.map(\.draft))
        #expect(actual.suggestions.map(\.isFavorite) == expected.suggestions.map(\.isFavorite))
        #expect(actual.suggestions.map(\.quickEntryAlias) == expected.suggestions.map(\.quickEntryAlias))
        #expect(actual.isPresented == expected.isPresented)
        #expect(actual.highlightedID == expected.highlightedID && actual.failure == expected.failure)
        #expect(try goalQuickEntryPreparationDigest(actual) == expectedDigest)
        #expect(!context.hasChanges)
    }

    let warmup = SavedTaskQuickEntryController()
    warmup.update(input, in: context)
    try validate(GoalQuickEntryPreparationState(warmup))
    var samples: [Double] = []
    for _ in 0..<30 {
        let controller = SavedTaskQuickEntryController() // Construction remains untimed.
        let start = DispatchTime.now().uptimeNanoseconds
        controller.update(input, in: context)
        let actual = GoalQuickEntryPreparationState(controller)
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        try validate(actual)
    }
    let ordered = samples.sorted()
    let median = (ordered[14] + ordered[15]) / 2
    // The control's zero preparation is an expected source contract, also checked
    // with an injected loader in correctness tests; no alias-call counter is timed.
    print("GOAL_QUICK_ENTRY_PREPARATION_BENCHMARK name=\(name) input=\(input) entries=\(entryCount) operationsPerSample=1 libraryLoadTimed=\(preparesLibrary) libraryPreparationsExpected=\(preparesLibrary ? 1 : 0) controllerConstructionTimed=false outputReadTimed=true store=memory-warm unit=ms n=30 p50=\(median) p95=\(ordered[28]) max=\(ordered[29]) valueRankDigest=\(expectedDigest) samples=\(samples)")
}

private struct GoalQuickEntryPreparationDigestState: Encodable {
    let input: String
    let entries: [GoalQuickEntryPreparationDigestEntry]
    let suggestions: [GoalQuickEntryPreparationDigestEntry]
    let isPresented: Bool
    let highlightedID: UUID?
    let failure: String?

    init(_ value: GoalQuickEntryPreparationState) {
        input = value.input
        entries = value.entries.map(GoalQuickEntryPreparationDigestEntry.init)
        suggestions = value.suggestions.map(GoalQuickEntryPreparationDigestEntry.init)
        isPresented = value.isPresented
        highlightedID = value.highlightedID
        failure = value.failure
    }
}

private struct GoalQuickEntryPreparationDigestEntry: Encodable {
    let id: UUID
    let draftID: UUID
    let title: String
    let note: String
    let priority: String?
    let tags: [String]
    let estimatedMinutes: Int?
    let checklistTitles: [String]
    let order: Double
    let isFavorite: Bool
    let quickEntryAlias: String?

    init(_ entry: SavedTaskEntry) {
        id = entry.id
        draftID = entry.draft.id
        title = entry.draft.title
        note = entry.draft.note
        priority = entry.draft.priority
        tags = entry.draft.tags
        estimatedMinutes = entry.draft.estimatedMinutes
        checklistTitles = entry.draft.checklistTitles
        order = entry.draft.order
        isFavorite = entry.isFavorite
        quickEntryAlias = entry.quickEntryAlias
    }
}

private func goalQuickEntryPreparationDigest(_ state: GoalQuickEntryPreparationState) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(GoalQuickEntryPreparationDigestState(state))
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Identical values/IDs to GoalQuickEntryPerformanceTests; that frozen harness
/// stays untouched for the input-change/highlight before/after comparison.
@MainActor
private func seedGoalQuickEntryPreparationLibrary(count: Int, in context: ModelContext) throws {
    let now = Date(timeIntervalSince1970: 1_788_400_000)
    for index in 0..<count {
        let id = goalQuickEntryPreparationFixtureID(namespace: 1, index: index)
        let title = index % 10 == 0 ? "성능 작업 공통" : String(format: "성능 작업 %04d", index)
        let alias = index == 0 ? "운동" : index == 1 ? "건강" : "perf\(index)"
        context.insert(TaskTemplate(
            id: id, instanceID: goalQuickEntryPreparationFixtureID(namespace: 2, index: index),
            name: title, isFavorite: index % 7 == 0, quickEntryAlias: alias,
            createdAt: now, updatedAt: now))
        context.insert(TaskTemplateItem(
            id: goalQuickEntryPreparationFixtureID(namespace: 3, index: index),
            instanceID: goalQuickEntryPreparationFixtureID(namespace: 4, index: index),
            templateId: id, title: title, note: "측정용 메모 \(index)", tags: ["측정"],
            estimatedMinutes: 30, checklistTitles: ["준비", "마무리"],
            order: Double(index + 1) * 100, createdAt: now, updatedAt: now))
    }
    try context.save()
}

private func goalQuickEntryPreparationFixtureID(namespace: Int, index: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-%04X-%012X", namespace, index + 1))!
}
#endif
