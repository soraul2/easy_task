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
