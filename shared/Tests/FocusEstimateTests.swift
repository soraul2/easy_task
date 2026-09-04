import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func focusEstimateSuggestionHandlesBoundsWithoutOverflow() {
    #expect(FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: nil) == 25)
    #expect(FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: 0) == 25)
    #expect(FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: -10) == 25)
    #expect(FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: 3) == 5)
    #expect(FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: 45) == 45)
    #expect(FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: 180) == 120)
    #expect(FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: Int.max) == 120)
}

@Test @MainActor
func focusUsesEstimateByDefaultAndKeepsExplicitSessionDuration() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let now = Date()
    let task = Task(title: "예상 시간 반영", plannedAt: now, order: 100, estimatedMinutes: 45)
    context.insert(task)
    let first = try FocusSessionService.beginFocus(taskID: task.id, now: now, in: context, directoryURL: directory)
    #expect(first.plannedFocusSeconds == 45 * 60)
    task.estimatedMinutes = 90
    #expect(try FocusSessionService.activeSnapshot(directoryURL: directory)?.plannedFocusSeconds == 45 * 60)
    _ = try FocusSessionService.endFocus(outcome: .stopped, expectedSessionID: first.sessionID,
        expectedRevision: first.revision, now: now.addingTimeInterval(60), in: context, directoryURL: directory)
    let custom = try FocusSessionService.beginFocus(taskID: task.id, focusSeconds: 15 * 60, now: now.addingTimeInterval(61), in: context, directoryURL: directory)
    #expect(custom.plannedFocusSeconds == 15 * 60)
    #expect(task.estimatedMinutes == 90)
}

@Test @MainActor
func focusPickerKeepsExplicitOlderTaskOutsideRecentWindow() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let old = Task(title: "먼저 만든 작업", plannedAt: Date(), order: 1, estimatedMinutes: 70)
    old.updatedAt = .distantPast
    context.insert(old)
    for i in 0..<105 {
        context.insert(Task(title: "최근 작업 \(i)", plannedAt: Date(), order: Double(i + 2)))
    }
    try context.save()
    let candidates = try FocusTaskQueryService.candidates(selectedTaskID: old.id, in: context)
    #expect(candidates.count == 101)
    #expect(candidates.first(where: { $0.id == old.id })?.estimatedMinutes == 70)
    old.status = TaskStatus.done.rawValue
    try context.save()
    #expect(try !FocusTaskQueryService.candidates(selectedTaskID: old.id, in: context).contains(where: { $0.id == old.id }))
}
