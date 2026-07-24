import Foundation
import PlanBaseCore
import SwiftData
import XCTest
@testable import PlanBase

final class PlanBaseWidgetSnapshotIntegrationTests: XCTestCase {
    func testSnapshotStoreRoundTripsV4PayloadUsingAtomicProtectedFile() throws {
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
            lockScreenDaySummaries: [summary]
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
        context.insert(event)
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
    }
}
