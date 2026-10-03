import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// Ordinary safety repro, not a performance harness. Every edit below targets a
// previously SAVED model; insert-only overlays cannot expose this SDK behavior.
// No production or frozen baseline source is changed by adding these tests.
enum GoalPendingScope: String, CaseIterable, Sendable {
    case activity, progress, focus
}

private func goalPendingID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

private struct GoalPendingValues: Equatable {
    let title: String
    let note: String?
    let taskUpdated: Date
    let activityID: UUID
    let activityTaskID: UUID
    let activityDay: String
    let activityDate: Date
    let activityUpdated: Date
    let activitySuperseded: Date?
    let stopID: UUID
    let stopTaskID: UUID
    let stopKind: String
    let stopDate: Date
    let stopUpdated: Date
    let stopSuperseded: Date?
    let focusID: UUID
    let focusSeconds: Int
    let focusOutcome: String
    let focusUpdated: Date
    let focusSuperseded: Date?
}

@MainActor
private struct GoalPendingFixture {
    let container: ModelContainer
    let day: Date
    let base: Date
    let task: EasyTaskCore.Task
    let activity: TaskCompletionActivity
    let start: TaskProgressEvent
    let stop: TaskProgressEvent
    let focus: FocusSession
    var context: ModelContext { container.mainContext }
    var key: String { DayKey.key(for: day) }

    init() throws {
        container = try PlanBaseContainerFactory.makeInMemory()
        container.mainContext.autosaveEnabled = false
        day = try #require(DayKey.date(from: "2026-10-02"))
        base = day.addingTimeInterval(12 * 60 * 60)
        task = EasyTaskCore.Task(id: goalPendingID(1), instanceID: goalPendingID(101),
                                 title: "저장된 작업", plannedAt: day, order: 1,
                                 createdAt: base, updatedAt: base)
        activity = TaskCompletionActivity(
            id: TaskActivityRules.logicalID(taskID: task.id, activityDayKey: DayKey.key(for: day)),
            instanceID: goalPendingID(201), taskId: task.id, activityDayKey: DayKey.key(for: day),
            occurredAt: base.addingTimeInterval(60), origin: .captured,
            createdAt: base, updatedAt: base)
        start = TaskProgressEvent(id: goalPendingID(301), instanceID: goalPendingID(401),
                                  taskId: task.id, kind: .started, occurredAt: base,
                                  createdAt: base, updatedAt: base)
        stop = TaskProgressEvent(id: goalPendingID(302), instanceID: goalPendingID(402),
                                 taskId: task.id, kind: .stopped, occurredAt: base.addingTimeInterval(60),
                                 createdAt: base, updatedAt: base)
        focus = FocusSession(id: goalPendingID(501), instanceID: goalPendingID(601),
                             taskId: task.id, startedAt: base, endedAt: base.addingTimeInterval(1500),
                             plannedDurationSeconds: 1500, focusedDurationSeconds: 300, outcome: .stopped,
                             createdAt: base, updatedAt: base)
        container.mainContext.insert(task)
        container.mainContext.insert(activity)
        container.mainContext.insert(start)
        container.mainContext.insert(stop)
        container.mainContext.insert(focus)
        try container.mainContext.save()
        #expect(!container.mainContext.hasChanges)
    }

    var values: GoalPendingValues {
        GoalPendingValues(
            title: task.title, note: task.note, taskUpdated: task.updatedAt,
            activityID: activity.id, activityTaskID: activity.taskId,
            activityDay: activity.activityDayKey, activityDate: activity.occurredAt,
            activityUpdated: activity.updatedAt, activitySuperseded: activity.supersededAt,
            stopID: stop.id, stopTaskID: stop.taskId, stopKind: stop.kindRawValue,
            stopDate: stop.occurredAt, stopUpdated: stop.updatedAt, stopSuperseded: stop.supersededAt,
            focusID: focus.id, focusSeconds: focus.focusedDurationSeconds,
            focusOutcome: focus.outcomeRawValue, focusUpdated: focus.updatedAt,
            focusSuperseded: focus.supersededAt)
    }

    func edit(_ scope: GoalPendingScope) {
        switch scope {
        case .activity:
            activity.occurredAt = base.addingTimeInterval(240)
            activity.updatedAt = base.addingTimeInterval(2000)
        case .progress:
            stop.occurredAt = base.addingTimeInterval(240)
            stop.updatedAt = base.addingTimeInterval(2000)
        case .focus:
            focus.focusedDurationSeconds = 900
            focus.updatedAt = base.addingTimeInterval(2000)
        }
    }

    func reconcile(_ scope: GoalPendingScope) throws {
        switch scope {
        case .activity: _ = try TaskActivityIntegrityService.reconcile(in: context, pageSize: 1)
        case .progress: _ = try TaskProgressEventIntegrityService.reconcile(in: context, pageSize: 1)
        case .focus: _ = try FocusSessionIntegrityService.reconcile(in: context, pageSize: 1)
        }
    }

    func assertSaved(_ scope: GoalPendingScope) throws {
        // A fresh local context confirms the final command committed the edit,
        // rather than leaving an expected value only in an old registered object.
        let reader = ModelContext(container)
        reader.autosaveEnabled = false
        switch scope {
        case .activity:
            let row = try #require(reader.fetch(FetchDescriptor<TaskCompletionActivity>()).first)
            #expect(row.occurredAt == base.addingTimeInterval(240))
            #expect(row.updatedAt == base.addingTimeInterval(2000))
        case .progress:
            let row = try #require(reader.fetch(FetchDescriptor<TaskProgressEvent>()).first { $0.id == stop.id })
            #expect(row.occurredAt == base.addingTimeInterval(240))
            #expect(row.updatedAt == base.addingTimeInterval(2000))
        case .focus:
            let row = try #require(reader.fetch(FetchDescriptor<FocusSession>()).first)
            #expect(row.focusedDurationSeconds == 900)
            #expect(row.updatedAt == base.addingTimeInterval(2000))
        }
    }
}

@Test @MainActor
func goalPendingActivitySnapshotsKeepEditedExistingRowValues() throws {
    let fixture = try GoalPendingFixture()
    let nextDay = DayKey.addingDays(1, to: fixture.day)
    fixture.activity.activityDayKey = DayKey.key(for: nextDay)
    fixture.activity.occurredAt = DayKey.addingDays(1, to: fixture.base)
    fixture.activity.taskId = goalPendingID(2)
    fixture.activity.updatedAt = fixture.base.addingTimeInterval(2000)
    let before = fixture.values
    #expect(fixture.context.hasChanges)
    let rows = try BoundedQueryService.taskActivitySnapshots(
        from: fixture.key, through: DayKey.key(for: nextDay), in: fixture.context)
    #expect(fixture.values == before)
    #expect(fixture.context.hasChanges)
    #expect(rows == [TaskActivitySnapshot(taskID: goalPendingID(2), activityDayKey: DayKey.key(for: nextDay))])
}

@Test(arguments: ["moved-existing", "deleted-existing"])
@MainActor
func goalPendingHasTaskActivityDoesNotReviveStoredExistingRow(change: String) throws {
    let fixture = try GoalPendingFixture()
    let nextKey = DayKey.key(for: DayKey.addingDays(1, to: fixture.day))
    let identifier = fixture.activity.persistentModelID
    if change == "moved-existing" {
        fixture.activity.activityDayKey = nextKey
        fixture.activity.occurredAt = DayKey.addingDays(1, to: fixture.base)
        let before = fixture.values
        let result = try BoundedQueryService.hasTaskActivity(before: nextKey, in: fixture.context)
        #expect(fixture.values == before)
        #expect(!result)
    } else {
        fixture.context.delete(fixture.activity)
        #expect(fixture.context.deletedModelsArray.contains { $0.persistentModelID == identifier })
        let result = try BoundedQueryService.hasTaskActivity(before: nextKey, in: fixture.context)
        #expect(!result)
        #expect(fixture.context.deletedModelsArray.contains { $0.persistentModelID == identifier })
        let snapshots = try BoundedQueryService.taskActivitySnapshots(
            from: fixture.key, through: nextKey, in: fixture.context)
        #expect(snapshots.isEmpty)
    }
    #expect(fixture.context.hasChanges)
}

@Test(arguments: GoalPendingScope.allCases)
@MainActor
func goalPendingIntegrityKeepsValidEditedExistingFields(scope: GoalPendingScope) throws {
    let fixture = try GoalPendingFixture()
    fixture.edit(scope)
    let before = fixture.values
    #expect(fixture.context.hasChanges)
    try fixture.reconcile(scope)
    #expect(fixture.values == before)
    #expect(fixture.context.hasChanges)
}

@Test(arguments: GoalPendingScope.allCases)
@MainActor
func goalPendingAtomicCommandKeepsFieldsChangedInsideMutationBeforeRepair(scope: GoalPendingScope) throws {
    let fixture = try GoalPendingFixture()
    fixture.task.note = "명령 이전의 별도 초안"
    try PersistenceCommandService.perform(in: fixture.context) {
        // The command's initial save cannot protect changes created inside it.
        fixture.edit(scope)
        let before = fixture.values
        try fixture.reconcile(scope)
        #expect(fixture.values == before)
    }
    #expect(!fixture.context.hasChanges)
    #expect(fixture.task.note == "명령 이전의 별도 초안")
    try fixture.assertSaved(scope)
}

@Test(arguments: GoalPendingScope.allCases)
@MainActor
func goalPendingTaskRecordKeepsExistingOverlayAndReflectsItsValue(scope: GoalPendingScope) async throws {
    let fixture = try GoalPendingFixture()
    fixture.edit(scope)
    let before = fixture.values
    let record = try await TaskRecordQueryService.load(
        selection: TaskRecordSelection(taskID: fixture.task.id, dayKey: fixture.key), in: fixture.context)
    #expect(fixture.values == before)
    #expect(fixture.context.hasChanges)
    switch scope {
    case .activity: #expect(record.latestCompletedAt == fixture.base.addingTimeInterval(240))
    case .progress: #expect(record.progress.recordedDuration == 240)
    case .focus: #expect(record.focusedSeconds == 900)
    }
}

@Test(arguments: ["task", "activity", "focus", "progress-reader-control"])
@MainActor
func goalPendingDailyActivityPageKeepsExistingFieldsAndSeparateProgressReaderIsControl(scope: String) async throws {
    let fixture = try GoalPendingFixture()
    if scope == "task" {
        fixture.task.title = "미저장 최신 제목"
        fixture.task.updatedAt = fixture.base.addingTimeInterval(2000)
    } else if scope == "activity" {
        fixture.edit(.activity)
    } else if scope == "focus" {
        fixture.edit(.focus)
    } else {
        fixture.edit(.progress)
    }
    let before = fixture.values
    let filter = ArchiveFilter(contentMode: .dailyActivity, period: .custom,
                               customStartDate: fixture.day, customEndDate: fixture.day)
    let service = DailyActivityQueryService(context: fixture.context)
    var page: ArchiveQueryPage?
    var readError: String?
    do {
        // Real default service, including its separate ModelActor progress reader.
        page = try await service.page(filter: filter, referenceDate: fixture.day)
    } catch {
        readError = String(reflecting: error)
    }
    #expect(fixture.values == before)
    #expect(fixture.context.hasChanges)
    #expect(readError == nil)
    guard let page else { return }
    let entry = try #require(page.records.first?.activityEntries?.first)
    if scope == "task" { #expect(entry.title == "미저장 최신 제목") }
    if scope == "focus" { #expect(entry.evidence.focusSeconds == 900) }
    if scope == "progress-reader-control" { #expect(entry.evidence.progressSeconds == 240) }
}

@Test(arguments: GoalPendingScope.allCases)
@MainActor
func goalPendingIntegrityUsesLatestEditedExistingVersionForSameLogicalID(scope: GoalPendingScope) throws {
    let fixture = try GoalPendingFixture()
    let secondID = goalPendingID(900)
    switch scope {
    case .activity:
        fixture.context.insert(TaskCompletionActivity(
            id: fixture.activity.id, instanceID: secondID, taskId: fixture.task.id,
            activityDayKey: fixture.key, occurredAt: fixture.base.addingTimeInterval(60), origin: .captured,
            createdAt: fixture.base, updatedAt: fixture.base.addingTimeInterval(1)))
    case .progress:
        fixture.context.insert(TaskProgressEvent(
            id: fixture.stop.id, instanceID: secondID, taskId: fixture.task.id,
            kind: .stopped, occurredAt: fixture.base.addingTimeInterval(60),
            createdAt: fixture.base, updatedAt: fixture.base.addingTimeInterval(1)))
    case .focus:
        fixture.context.insert(FocusSession(
            id: fixture.focus.id, instanceID: secondID, taskId: fixture.task.id,
            startedAt: fixture.base, endedAt: fixture.base.addingTimeInterval(1500),
            plannedDurationSeconds: 1500, focusedDurationSeconds: 300, outcome: .stopped,
            createdAt: fixture.base, updatedAt: fixture.base.addingTimeInterval(1)))
    }
    try fixture.context.save()
    fixture.edit(scope)
    let before = fixture.values
    try fixture.reconcile(scope)
    #expect(fixture.values == before)
    switch scope {
    case .activity:
        let rows = try fixture.context.fetch(FetchDescriptor<TaskCompletionActivity>())
        #expect(rows.filter { $0.supersededAt == nil }.map(\.instanceID) == [fixture.activity.instanceID])
    case .progress:
        let rows = try fixture.context.fetch(FetchDescriptor<TaskProgressEvent>())
        #expect(rows.filter { $0.supersededAt == nil && $0.id == fixture.stop.id }.map(\.instanceID) == [fixture.stop.instanceID])
    case .focus:
        let rows = try fixture.context.fetch(FetchDescriptor<FocusSession>())
        #expect(rows.filter { $0.supersededAt == nil }.map(\.instanceID) == [fixture.focus.instanceID])
    }
}

@Test @MainActor
func goalPendingCurrentPackageMergeKeepsNewExistingValuesThroughFinalIntegrity() throws {
    let fixture = try GoalPendingFixture()
    var incoming = try BackupPackageCodec.makeContents(context: fixture.context, exportedAt: fixture.base)
    var activities = try #require(incoming.records.payload.taskCompletionActivities)
    var progress = try #require(incoming.records.payload.taskProgressEvents)
    var focuses = try #require(incoming.records.payload.focusSessions)
    let activityIndex = try #require(activities.firstIndex { $0.instanceID == fixture.activity.instanceID })
    let stopIndex = try #require(progress.firstIndex { $0.instanceID == fixture.stop.instanceID })
    let focusIndex = try #require(focuses.firstIndex { $0.instanceID == fixture.focus.instanceID })
    activities[activityIndex].occurredAt = fixture.base.addingTimeInterval(240)
    activities[activityIndex].updatedAt = fixture.base.addingTimeInterval(2000)
    progress[stopIndex].occurredAt = fixture.base.addingTimeInterval(240)
    progress[stopIndex].updatedAt = fixture.base.addingTimeInterval(2000)
    focuses[focusIndex].focusedDurationSeconds = 900
    focuses[focusIndex].updatedAt = fixture.base.addingTimeInterval(2000)
    incoming.records.payload.taskCompletionActivities = activities
    incoming.records.payload.taskProgressEvents = progress
    incoming.records.payload.focusSessions = focuses
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let recordsData = try encoder.encode(incoming.records)
    incoming.manifest.recordsByteCount = recordsData.count
    incoming.manifest.recordsSHA256 = SHA256.hash(data: recordsData)
        .map { String(format: "%02x", $0) }.joined()
    #expect(incoming.records.formatVersion == BackupPackageCodec.currentVersion)
    let report = try BackupPackageCodec.restoreMerging(incoming, into: fixture.context)
    #expect(report.updatedRecords >= 3)
    #expect(!fixture.context.hasChanges)
    for scope in GoalPendingScope.allCases { try fixture.assertSaved(scope) }
}

@Test(arguments: GoalPendingScope.allCases)
@MainActor
func goalPendingSavedIdentifierFetchKeepsRegisteredExistingFieldsControl(scope: GoalPendingScope) throws {
    let fixture = try GoalPendingFixture()
    fixture.edit(scope)
    let before = fixture.values
    let pendingIDs = Set(fixture.context.changedModelsArray.map(\.persistentModelID))
    let identifiers: [PersistentIdentifier]
    switch scope {
    case .activity:
        var descriptor = FetchDescriptor<TaskCompletionActivity>(sortBy: [SortDescriptor(\TaskCompletionActivity.id)])
        descriptor.includePendingChanges = false
        descriptor.fetchLimit = 1
        identifiers = try fixture.context.fetchIdentifiers(descriptor)
        #expect(identifiers == [fixture.activity.persistentModelID])
        let registeredValue: TaskCompletionActivity? = fixture.context.registeredModel(for: fixture.activity.persistentModelID)
        let registered = try #require(registeredValue)
        #expect(registered === fixture.activity)
    case .progress:
        var descriptor = FetchDescriptor<TaskProgressEvent>(sortBy: [SortDescriptor(\TaskProgressEvent.id)])
        descriptor.includePendingChanges = false
        descriptor.fetchLimit = 1
        // The stored start comes first: the dirty existing stop is on page 2.
        descriptor.fetchOffset = 1
        identifiers = try fixture.context.fetchIdentifiers(descriptor)
        #expect(identifiers == [fixture.stop.persistentModelID])
        let registeredValue: TaskProgressEvent? = fixture.context.registeredModel(for: fixture.stop.persistentModelID)
        let registered = try #require(registeredValue)
        #expect(registered === fixture.stop)
    case .focus:
        var descriptor = FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\FocusSession.id)])
        descriptor.includePendingChanges = false
        descriptor.fetchLimit = 1
        identifiers = try fixture.context.fetchIdentifiers(descriptor)
        #expect(identifiers == [fixture.focus.persistentModelID])
        let registeredValue: FocusSession? = fixture.context.registeredModel(for: fixture.focus.persistentModelID)
        let registered = try #require(registeredValue)
        #expect(registered === fixture.focus)
    }
    // This is an unproven SDK control. A pass establishes field/identity safety
    // for these fixtures; it is not authorization to replace production readers.
    #expect(fixture.values == before)
    #expect(fixture.context.hasChanges)
    #expect(identifiers.filter { !pendingIDs.contains($0) }.isEmpty)
}
