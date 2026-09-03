import Foundation
import PlanBaseCore
import Testing

@Suite("Watch widget snapshot")
struct WatchWidgetSnapshotTests {
    @MainActor
    @Test("today summary prefers an active task")
    func makesTodaySummary() throws {
        let referenceDate = try #require(DayKey.date(from: "2026-09-01"))
        let todo = Task(
            title: "준비 작업",
            plannedAt: referenceDate,
            order: 200
        )
        let doing = Task(
            title: "집중 작업",
            status: .doing,
            plannedAt: referenceDate,
            order: 100
        )
        let event = CalendarEvent(
            title: "오늘 일정",
            startAt: referenceDate,
            endAt: referenceDate
        )

        let snapshot = WatchWidgetSnapshot.make(
            tasks: [todo, doing],
            events: [event],
            referenceDate: referenceDate
        )

        #expect(snapshot.dayKey == "2026-09-01")
        #expect(snapshot.todoCount == 1)
        #expect(snapshot.doingCount == 1)
        #expect(snapshot.eventCount == 1)
        #expect(snapshot.focusTitle == "집중 작업")
        #expect(snapshot.focusKind == .doingTask)
    }

    @Test("snapshot store round trips and skips unchanged payloads")
    func roundTripsSnapshot() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let snapshot = WatchWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            dayKey: "2026-09-01",
            todoCount: 2,
            doingCount: 1,
            doneCount: 3,
            eventCount: 1,
            focusTitle: "집중 작업",
            focusKind: .doingTask
        )

        #expect(try WatchWidgetSnapshotStore.writeIfChanged(
            snapshot,
            directoryURL: directoryURL
        ))
        #expect(try !WatchWidgetSnapshotStore.writeIfChanged(
            WatchWidgetSnapshot(
                generatedAt: snapshot.generatedAt.addingTimeInterval(60),
                dayKey: snapshot.dayKey,
                todoCount: snapshot.todoCount,
                doingCount: snapshot.doingCount,
                doneCount: snapshot.doneCount,
                eventCount: snapshot.eventCount,
                focusTitle: snapshot.focusTitle,
                focusKind: snapshot.focusKind
            ),
            directoryURL: directoryURL
        ))
        #expect(try WatchWidgetSnapshotStore.read(
            directoryURL: directoryURL
        ) == snapshot)
    }

    @MainActor
    @Test("active Watch focus overrides the generic day focus without ticking writes")
    func embedsActiveFocusState() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day = try #require(DayKey.date(from: "2026-09-01"))
        let active = FocusTimerRules.startFocus(
            taskID: UUID(),
            taskTitle: "Watch 집중 작업",
            focusSeconds: 25 * 60,
            now: now
        )

        let snapshot = WatchWidgetSnapshot.make(
            tasks: [Task(
                title: "다른 진행 작업",
                status: .doing,
                plannedAt: day,
                order: 100
            )],
            events: [],
            referenceDate: day,
            activeFocus: active
        )

        #expect(snapshot.hasActiveFocusTimer)
        #expect(snapshot.focusTitle == "Watch 집중 작업")
        #expect(snapshot.focusSessionID == active.sessionID)
        #expect(snapshot.focusPhase == FocusTimerPhase.focus)
        #expect(snapshot.focusRunState == FocusTimerRunState.running)
        let remaining = try #require(
            snapshot.focusRemainingSeconds(at: now.addingTimeInterval(60))
        )
        #expect(abs(remaining - 24 * 60) < 0.001)
        #expect(snapshot.focusRemainingSeconds(at: now.addingTimeInterval(30 * 60)) == 0)
    }

    @Test("pre-Focus Watch snapshot remains readable")
    func readsLegacySnapshotWithoutFocusTimerFields() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "generatedAt": "2026-09-01T00:00:00Z",
          "dayKey": "2026-09-01",
          "todoCount": 2,
          "doingCount": 1,
          "doneCount": 3,
          "eventCount": 1,
          "focusTitle": "기존 진행 작업",
          "focusKind": "doingTask"
        }
        """
        try Data(legacyJSON.utf8).write(
            to: directoryURL.appendingPathComponent(WatchWidgetConstants.snapshotFileName)
        )

        let decoded = try WatchWidgetSnapshotStore.read(directoryURL: directoryURL)
        let snapshot = try #require(decoded)
        #expect(snapshot.focusTitle == "기존 진행 작업")
        #expect(!snapshot.hasActiveFocusTimer)
        #expect(snapshot.focusSessionID == nil)
    }
}
