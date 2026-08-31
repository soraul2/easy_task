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
            directoryURL: directoryURL
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
            directoryURL: directoryURL
        )
        XCTAssertTrue(changedThemeDidWrite)
        XCTAssertEqual(
            try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL)?.themeID,
            "roseLilac"
        )
    }
}
