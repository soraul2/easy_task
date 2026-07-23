import Foundation
import PlanBaseCore
import XCTest

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
}
