import Foundation
import PlanBaseCore
import SwiftData
import XCTest
@testable import PlanBase

final class PlanBaseWidgetSnapshotIntegrationTests: XCTestCase {
    func testSnapshotStoreRoundTripsV5PayloadUsingAtomicProtectedFile() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let summary = LockScreenWidgetDaySummary(
            dayKey: "2026-07-16",
            todoCount: 1,
            doingCount: 1,
            doneCount: 2,
            eventCount: 3,
            focusTitle: "통합 테스트",
            focusKind: .doingTask
        )
        let snapshot = CalendarWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 100),
            events: [],
            lockScreenCoveredStartDayKey: "2026-07-16",
            lockScreenCoveredEndDayKey: "2026-07-23",
            lockScreenDaySummaries: [summary],
            plannerTaskPreviewsByDayKey: [
                "2026-07-16": [PlannerWidgetTaskPreview(
                    id: UUID(),
                    title: "통합 테스트 작업",
                    status: .doing,
                    order: 0
                )]
            ]
        )

        XCTAssertTrue(try CalendarWidgetSnapshotStore.writeIfChanged(
            snapshot,
            directoryURL: directoryURL
        ))
        XCTAssertEqual(
            try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL),
            snapshot
        )

        let fileURL = directoryURL.appendingPathComponent(
            CalendarWidgetConstants.snapshotFileName
        )
#if os(iOS)
#if targetEnvironment(simulator)
        XCTAssertTrue(
            CalendarWidgetSnapshotStore.snapshotWritingOptions.contains(
                .completeFileProtectionUntilFirstUserAuthentication
            )
        )
#else
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(
            attributes[.protectionKey] as? FileProtectionType,
            .completeUntilFirstUserAuthentication
        )
#endif
#else
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
#endif
    }

    func testWriteCoordinatorRejectsAnOlderSnapshotForTheSameDestination() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let newerSnapshot = CalendarWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 200),
            themeID: "roseLilac",
            events: []
        )
        let olderSnapshot = CalendarWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 100),
            themeID: AppThemePreset.defaultID,
            events: []
        )
        let coordinator = CalendarWidgetSnapshotWriteCoordinator()

        let didWriteNewerSnapshot = try await coordinator.write(
            newerSnapshot,
            sequence: 2,
            directoryURL: directoryURL,
            forceWrite: true
        )
        let didWriteOlderSnapshot = try await coordinator.write(
            olderSnapshot,
            sequence: 1,
            directoryURL: directoryURL,
            forceWrite: true
        )

        XCTAssertTrue(didWriteNewerSnapshot)
        XCTAssertFalse(didWriteOlderSnapshot)
        XCTAssertEqual(
            try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL),
            newerSnapshot
        )
    }

    @MainActor
    func testPublisherWritesCalendarEventsFetchedFromAppContext() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let referenceDate = try XCTUnwrap(DayKey.date(from: "2026-07-24"))
        let event = try XCTUnwrap(CalendarEventRules.makeEvent(
            title: "위젯 통합 일정",
            startAt: referenceDate,
            endAt: referenceDate,
            color: CalendarEventColor.blue.rawValue,
            now: referenceDate
        ))
        let task = PlanBaseCore.Task(
            title: "오늘 플래너 작업",
            status: .doing,
            plannedAt: referenceDate,
            order: 0,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        context.insert(event)
        context.insert(task)
        try context.save()

        let didWrite = try await CalendarWidgetSnapshotPublicationService.publish(
            context: context,
            themeID: AppThemePreset.defaultID,
            forceWrite: true,
            referenceDate: referenceDate,
            directoryURL: directoryURL,
            reloadTimelines: {}
        )
        XCTAssertTrue(didWrite)

        let snapshot = try XCTUnwrap(
            CalendarWidgetSnapshotStore.read(directoryURL: directoryURL)
        )
        XCTAssertEqual(snapshot.events.map(\.title), ["위젯 통합 일정"])
        XCTAssertEqual(
            snapshot.events(onDayKey: "2026-07-24").map(\.title),
            ["위젯 통합 일정"]
        )
        XCTAssertEqual(
            snapshot.plannerTaskPreviews(onDayKey: "2026-07-24")?.map(\.title),
            ["오늘 플래너 작업"]
        )
        XCTAssertEqual(snapshot.plannerTaskPreviewsByDayKey?.count, 8)

        let changedThemeDidWrite = try await CalendarWidgetSnapshotPublicationService.publish(
            context: context,
            themeID: "roseLilac",
            referenceDate: referenceDate,
            directoryURL: directoryURL,
            reloadTimelines: {}
        )
        XCTAssertTrue(changedThemeDidWrite)
        XCTAssertEqual(
            try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL)?.themeID,
            "roseLilac"
        )
    }

    @MainActor
    func testRepeatedPublicationSkipsUnchangedWritesAndHonorsForcedReload() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent(
            CalendarWidgetConstants.snapshotFileName
        )
        let referenceDate = try XCTUnwrap(DayKey.date(from: "2026-07-24"))
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        var reloadCount = 0
        var writeResults: [Bool] = []

        writeResults.append(try await CalendarWidgetSnapshotPublicationService.publish(
            context: context,
            themeID: AppThemePreset.defaultID,
            forceWrite: true,
            referenceDate: referenceDate,
            directoryURL: directoryURL,
            reloadTimelines: { reloadCount += 1 }
        ))
        let initialBytes = try Data(contentsOf: fileURL)
        // A fixed old timestamp makes an accidental same-bytes rewrite observable.
        try FileManager.default.setAttributes(
            [.modificationDate: referenceDate],
            ofItemAtPath: fileURL.path
        )
        let initialModificationDate = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )[.modificationDate] as? Date
        for _ in 0..<3 {
            writeResults.append(try await CalendarWidgetSnapshotPublicationService.publish(
                context: context,
                themeID: AppThemePreset.defaultID,
                referenceDate: referenceDate,
                directoryURL: directoryURL,
                reloadTimelines: { reloadCount += 1 }
            ))
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), initialBytes)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date,
            initialModificationDate
        )
        XCTAssertEqual(reloadCount, 1)

        writeResults.append(try await CalendarWidgetSnapshotPublicationService.publish(
            context: context,
            themeID: "roseLilac",
            referenceDate: referenceDate,
            directoryURL: directoryURL,
            reloadTimelines: { reloadCount += 1 }
        ))
        let themedBytes = try Data(contentsOf: fileURL)
        XCTAssertNotEqual(themedBytes, initialBytes)
        XCTAssertEqual(reloadCount, 2)

        let event = try XCTUnwrap(CalendarEventRules.makeEvent(
            title: "변경된 위젯 일정",
            startAt: referenceDate,
            endAt: referenceDate,
            now: referenceDate
        ))
        context.insert(event)
        try context.save()
        writeResults.append(try await CalendarWidgetSnapshotPublicationService.publish(
            context: context,
            themeID: "roseLilac",
            referenceDate: referenceDate,
            directoryURL: directoryURL,
            reloadTimelines: { reloadCount += 1 }
        ))
        let changedBytes = try Data(contentsOf: fileURL)
        XCTAssertNotEqual(changedBytes, themedBytes)
        let changedSnapshot = try XCTUnwrap(
            CalendarWidgetSnapshotStore.read(directoryURL: directoryURL)
        )
        XCTAssertEqual(changedSnapshot.generatedAt, referenceDate)
        XCTAssertEqual(changedSnapshot.themeID, "roseLilac")
        XCTAssertEqual(changedSnapshot.events.map(\.title), ["변경된 위젯 일정"])
        XCTAssertEqual(reloadCount, 3)

        let changedModificationDate = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )[.modificationDate] as? Date
        writeResults.append(try await CalendarWidgetSnapshotPublicationService.publish(
            context: context,
            themeID: "roseLilac",
            forceTimelineReload: true,
            referenceDate: referenceDate,
            directoryURL: directoryURL,
            reloadTimelines: { reloadCount += 1 }
        ))
        XCTAssertEqual(try Data(contentsOf: fileURL), changedBytes)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date,
            changedModificationDate
        )
        XCTAssertEqual(reloadCount, 4)

        writeResults.append(try await CalendarWidgetSnapshotPublicationService.publish(
            context: context,
            themeID: "roseLilac",
            forceWrite: true,
            referenceDate: referenceDate,
            directoryURL: directoryURL,
            reloadTimelines: { reloadCount += 1 }
        ))
        XCTAssertEqual(try Data(contentsOf: fileURL), changedBytes)
        XCTAssertEqual(
            try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL)?.generatedAt,
            referenceDate
        )
        XCTAssertEqual(writeResults, [true, false, false, false, true, true, false, true])
        XCTAssertEqual(reloadCount, 5)
    }

    @MainActor
    func testDelayedImportRefreshUsesThemeSelectedWhileWaiting() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let container = try PlanBaseContainerFactory.makeInMemory()
        let gate = WidgetPublicationDelayGate()
        var themeID = AppThemePreset.defaultID
        let delayedPublication = Swift.Task { @MainActor in
            try await CalendarWidgetSnapshotPublicationService.refresh(
                context: container.mainContext,
                themeID: { themeID },
                forceWrite: true,
                delay: .milliseconds(250),
                directoryURL: directoryURL,
                waitForDelay: { _ in await gate.suspend() },
                reloadTimelines: {}
            )
        }

        await gate.waitUntilSuspended()
        themeID = "roseLilac"
        _ = try await CalendarWidgetSnapshotPublicationService.publish(
            context: container.mainContext,
            themeID: themeID,
            forceWrite: true,
            directoryURL: directoryURL,
            reloadTimelines: {}
        )
        XCTAssertEqual(
            try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL)?.themeID,
            "roseLilac"
        )

        await gate.resume()
        _ = try await delayedPublication.value
        XCTAssertEqual(
            try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL)?.themeID,
            "roseLilac",
            "A delayed import must not overwrite a newer theme selection."
        )
    }

    @MainActor
    func testCalendarPublicationDoesNotReviveTodayWhenLatestVersionMovedOutsideCoverage() async throws {
        let date = try XCTUnwrap(DayKey.date(from: "2026-10-02"))
        let older = try goalWidgetCalendarEvent(physicalID: 101, updatedSeconds: 0)
        let latest = try goalWidgetCalendarEvent(
            physicalID: 102, dayKey: "2027-03-02", title: "범위 밖 최신 일정", updatedSeconds: 1
        )
        let snapshot = try await publishGoalCalendarSnapshot(events: [older, latest], at: date)

        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertEqual(snapshot.totalEventCount(onDayKey: "2026-10-02"), 0)
        XCTAssertEqual(snapshot.lockScreenSummary(onDayKey: "2026-10-02")?.eventCount, 0)
        let today = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date)
        XCTAssertEqual(today.availability, .available)
        XCTAssertEqual(today.totalCount, 0)
        XCTAssertTrue(today.previews.isEmpty)
        XCTAssertEqual(today.accessibilityText, "오늘 일정 없음")
    }

    @MainActor
    func testCalendarPublicationKeepsLatestNextMonthInsteadOfOlderToday() async throws {
        let date = try XCTUnwrap(DayKey.date(from: "2026-10-02"))
        let nextMonth = try XCTUnwrap(DayKey.date(from: "2026-11-04"))
        let older = try goalWidgetCalendarEvent(physicalID: 101, updatedSeconds: 0)
        let latest = try goalWidgetCalendarEvent(
            physicalID: 102, dayKey: "2026-11-04", title: "다음 달 최신 일정", updatedSeconds: 1
        )
        let snapshot = try await publishGoalCalendarSnapshot(events: [latest, older], at: date)

        XCTAssertEqual(snapshot.events.map(\.renderID), [goalWidgetCalendarID(102)])
        XCTAssertEqual(CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date).totalCount, 0)
        let future = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: nextMonth)
        XCTAssertEqual(future.availability, .available)
        XCTAssertEqual(future.totalCount, 1)
        XCTAssertEqual(future.previews.map(\.title), ["다음 달 최신 일정"])
        XCTAssertEqual(future.previews.first?.periodText, "종일")
        // The new calendar configuration works beyond the task summary horizon.
        XCTAssertNil(snapshot.lockScreenSummary(onDayKey: "2026-11-04"))
    }

    @MainActor
    func testCalendarPublicationBlankLatestTitleDoesNotRestoreOlderToday() async throws {
        let date = try XCTUnwrap(DayKey.date(from: "2026-10-02"))
        let older = try goalWidgetCalendarEvent(physicalID: 101, updatedSeconds: 0)
        let latest = try goalWidgetCalendarEvent(physicalID: 102, title: " \n\t ", updatedSeconds: 1)
        let snapshot = try await publishGoalCalendarSnapshot(events: [older, latest], at: date)

        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertEqual(snapshot.eventCountsByDayKey["2026-10-02"] ?? 0, 0)
        let today = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date)
        XCTAssertEqual(today.availability, .available)
        XCTAssertEqual(today.totalCount, 0)
        XCTAssertTrue(today.previews.isEmpty)
    }

    @MainActor
    func testCalendarPublicationSupersededLatestLeavesActiveOlderRepresentative() async throws {
        let date = try XCTUnwrap(DayKey.date(from: "2026-10-02"))
        let older = try goalWidgetCalendarEvent(physicalID: 101, title: "남아 있는 활성 일정", updatedSeconds: 0)
        let latest = try goalWidgetCalendarEvent(
            physicalID: 102, dayKey: "2027-03-02", title: "대체된 최신 행", updatedSeconds: 1,
            superseded: true
        )
        let snapshot = try await publishGoalCalendarSnapshot(events: [latest, older], at: date)

        XCTAssertEqual(snapshot.events.map(\.renderID), [goalWidgetCalendarID(101)])
        let today = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date)
        XCTAssertEqual(today.availability, .available)
        XCTAssertEqual(today.totalCount, 1)
        XCTAssertEqual(today.previews.map(\.title), ["남아 있는 활성 일정"])
    }

    @MainActor
    func testCalendarPublicationTimestampTieUsesPhysicalIDBeforeDateOrTitleVisibility() async throws {
        let date = try XCTUnwrap(DayKey.date(from: "2026-10-02"))
        let tomorrow = try XCTUnwrap(DayKey.date(from: "2026-10-03"))
        // Reverse insertion order with independent in-memory containers each time.
        // A newer physical ID must win even when it no longer matches today's date.
        for reversed in [false, true] {
            let older = try goalWidgetCalendarEvent(physicalID: 101, title: "동률 이전 일정", updatedSeconds: 1)
            let latest = try goalWidgetCalendarEvent(
                physicalID: 102, dayKey: "2026-10-03", title: "동률 최신 일정", updatedSeconds: 1
            )
            let events = reversed ? [latest, older] : [older, latest]
            let snapshot = try await publishGoalCalendarSnapshot(events: events, at: date)
            XCTAssertEqual(snapshot.events.map(\.renderID), [goalWidgetCalendarID(102)])
            XCTAssertEqual(CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date).totalCount, 0)
            XCTAssertEqual(CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: tomorrow).previews.map(\.title), ["동률 최신 일정"])
        }
        let older = try goalWidgetCalendarEvent(physicalID: 101, title: "동률 유효 이전 제목", updatedSeconds: 1)
        let latest = try goalWidgetCalendarEvent(physicalID: 102, title: " ", updatedSeconds: 1)
        let blankSnapshot = try await publishGoalCalendarSnapshot(events: [latest, older], at: date)
        XCTAssertTrue(blankSnapshot.events.isEmpty)
        XCTAssertEqual(CalendarLockScreenWidgetRules.presentation(snapshot: blankSnapshot, at: date).totalCount, 0)
    }

    @MainActor
    func testCalendarPublicationFeedsTwoTitlesFullCountAndRedactedAccessibility() async throws {
        let date = try XCTUnwrap(DayKey.date(from: "2026-10-02"))
        let older = try goalWidgetCalendarEvent(physicalID: 101, title: "삭제되지 않은 이전 제목", updatedSeconds: 0)
        let latest = try goalWidgetCalendarEvent(physicalID: 102, title: "A 최신 비밀 일정", updatedSeconds: 1)
        let second = try goalWidgetCalendarEvent(logicalID: 2, physicalID: 201, title: "B 상담", updatedSeconds: 0)
        let third = try goalWidgetCalendarEvent(logicalID: 3, physicalID: 301, title: "C 개인 일정", updatedSeconds: 0)
        let snapshot = try await publishGoalCalendarSnapshot(events: [older, third, latest, second], at: date)

        XCTAssertEqual(snapshot.events.map(\.renderID), [goalWidgetCalendarID(102), goalWidgetCalendarID(201), goalWidgetCalendarID(301)])
        XCTAssertEqual(snapshot.eventCountsByDayKey["2026-10-02"], 3)
        let visible = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date)
        XCTAssertEqual(visible.totalCount, 3)
        XCTAssertEqual(visible.previews.map(\.title), ["A 최신 비밀 일정", "B 상담"])
        XCTAssertEqual(visible.remainingCount, 1)
        let hidden = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date, redactingDetails: true)
        XCTAssertEqual(hidden.totalCount, 3)
        XCTAssertTrue(hidden.previews.isEmpty)
        XCTAssertEqual(hidden.inlineText, "일정 3개")
        XCTAssertEqual(hidden.accessibilityText, "오늘 일정 3개")
    }

    @MainActor
    func testCalendarPublicationKnownEmptyIsDistinctFromExpiredOrUnreadableSnapshot() async throws {
        let date = try XCTUnwrap(DayKey.date(from: "2026-10-02"))
        let snapshot = try await publishGoalCalendarSnapshot(events: [], at: date)
        let confirmed = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date)
        XCTAssertEqual(confirmed.availability, .available)
        XCTAssertEqual(confirmed.totalCount, 0)

        let expiredDate = try XCTUnwrap(DayKey.date(from: snapshot.coveredEndDayKey))
        let expired = CalendarLockScreenWidgetRules.presentation(
            snapshot: snapshot, at: DayKey.addingDays(1, to: expiredDate)
        )
        XCTAssertEqual(expired.availability, .needsRefresh)
        XCTAssertNil(expired.totalCount)
        XCTAssertEqual(expired.inlineText, "앱을 열어 갱신")
        for state in [CalendarLockScreenAvailability.needsRefresh, .requiresAppUpdate] {
            let unreadable = CalendarLockScreenWidgetRules.presentation(
                snapshot: snapshot, at: date, availability: state
            )
            XCTAssertEqual(unreadable.availability, state)
            XCTAssertNil(unreadable.totalCount)
            XCTAssertTrue(unreadable.previews.isEmpty)
        }
        let missing = CalendarLockScreenWidgetRules.presentation(snapshot: nil, at: date)
        XCTAssertNil(missing.totalCount)
        XCTAssertEqual(missing.availability, .needsRefresh)
    }
}

@MainActor
private func goalWidgetCalendarEvent(
    logicalID: Int = 1,
    physicalID: Int,
    dayKey: String = "2026-10-02",
    title: String = "이전 오늘 일정",
    updatedSeconds: TimeInterval,
    superseded: Bool = false
) throws -> CalendarEvent {
    let referenceDate = try XCTUnwrap(DayKey.date(from: "2026-10-02"))
    let eventDate = try XCTUnwrap(DayKey.date(from: dayKey))
    return CalendarEvent(
        id: goalWidgetCalendarID(logicalID),
        instanceID: goalWidgetCalendarID(physicalID),
        title: title,
        startAt: eventDate,
        endAt: eventDate,
        createdAt: referenceDate,
        updatedAt: referenceDate.addingTimeInterval(updatedSeconds),
        supersededAt: superseded ? referenceDate.addingTimeInterval(2) : nil
    )
}

private func goalWidgetCalendarID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

@MainActor
private func publishGoalCalendarSnapshot(
    events: [CalendarEvent],
    at referenceDate: Date,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> CalendarWidgetSnapshot {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("goal-widget-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    for event in events { container.mainContext.insert(event) }
    try container.mainContext.save()
    var publicationReloadCallbackCount = 0
    let didWrite = try await CalendarWidgetSnapshotPublicationService.publish(
        context: container.mainContext,
        themeID: AppThemePreset.defaultID,
        forceWrite: true,
        referenceDate: referenceDate,
        directoryURL: directoryURL,
        reloadTimelines: { publicationReloadCallbackCount += 1 }
    )
    XCTAssertTrue(didWrite, file: file, line: line)
    // This proves only publication callback invocation, not a WidgetKit refresh.
    XCTAssertEqual(publicationReloadCallbackCount, 1, file: file, line: line)
    return try XCTUnwrap(
        CalendarWidgetSnapshotStore.read(directoryURL: directoryURL),
        file: file,
        line: line
    )
}

private actor WidgetPublicationDelayGate {
    private var isSuspended = false
    private var delayContinuation: CheckedContinuation<Void, Never>?
    private var suspensionContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            delayContinuation = continuation
            isSuspended = true
            suspensionContinuation?.resume()
            suspensionContinuation = nil
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { suspensionContinuation = $0 }
    }

    func resume() {
        delayContinuation?.resume()
        delayContinuation = nil
    }
}
