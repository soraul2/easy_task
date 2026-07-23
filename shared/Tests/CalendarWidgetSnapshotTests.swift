import Foundation
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func calendarWidgetSnapshotFiltersSortsAndFindsSpanningEvents() throws {
    let referenceDate = try #require(DayKey.date(from: "2026-07-16"))
    let projectStart = try #require(DayKey.date(from: "2026-07-15"))
    let projectEnd = try #require(DayKey.date(from: "2026-07-18"))
    let distantStart = try #require(DayKey.date(from: "2027-01-01"))
    let distantEnd = try #require(DayKey.date(from: "2027-01-02"))
    let first = try #require(CalendarEventRules.makeEvent(
        title: "  프로젝트 일정  ",
        startAt: projectStart,
        endAt: projectEnd,
        color: CalendarEventColor.red.rawValue,
        now: referenceDate
    ))
    let second = try #require(CalendarEventRules.makeEvent(
        title: "회의",
        startAt: referenceDate,
        endAt: referenceDate,
        color: "invalid",
        now: referenceDate
    ))
    let removed = try #require(CalendarEventRules.makeEvent(
        title: "삭제된 일정",
        startAt: referenceDate,
        endAt: referenceDate,
        now: referenceDate
    ))
    removed.supersededAt = referenceDate
    let distant = try #require(CalendarEventRules.makeEvent(
        title: "범위 밖",
        startAt: distantStart,
        endAt: distantEnd,
        now: referenceDate
    ))

    let snapshot = CalendarWidgetSnapshot.make(
        events: [second, distant, removed, first],
        referenceDate: referenceDate,
        themeID: "roseLilac"
    )

    #expect(snapshot.schemaVersion == 4)
    #expect(snapshot.themeID == "roseLilac")
    #expect(snapshot.events.map(\.title) == ["프로젝트 일정", "회의"])
    #expect(snapshot.events.first?.colorID == CalendarEventColor.red.rawValue)
    #expect(snapshot.events.last?.colorID == CalendarEventPalette.defaultColor)
    #expect(snapshot.events(onDayKey: "2026-07-16").map(\.title) == ["프로젝트 일정", "회의"])
    #expect(snapshot.events(onDayKey: "2026-07-19").isEmpty)
}

@Test
func calendarWidgetSnapshotStoreRoundTripsAndSkipsEquivalentContent() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let event = CalendarWidgetEventSnapshot(
        id: UUID(),
        title: "출시 준비",
        startDayKey: "2026-07-16",
        endDayKey: "2026-07-18",
        colorID: CalendarEventColor.blue.rawValue
    )
    let first = CalendarWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 100),
        themeID: "appleSystem",
        events: [event]
    )
    let sameContent = CalendarWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 200),
        themeID: "appleSystem",
        events: [event]
    )
    let changedTheme = CalendarWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 300),
        themeID: "roseLilac",
        events: [event]
    )

    #expect(try CalendarWidgetSnapshotStore.writeIfChanged(first, directoryURL: directoryURL))
    #expect(try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL) == first)
    #expect(try !CalendarWidgetSnapshotStore.writeIfChanged(sameContent, directoryURL: directoryURL))
    #expect(try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL)?.generatedAt == first.generatedAt)
    #expect(try CalendarWidgetSnapshotStore.writeIfChanged(changedTheme, directoryURL: directoryURL))
    #expect(try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL)?.themeID == "roseLilac")
}

@Test
func calendarWidgetSnapshotDecodesLegacyThemeLessPayload() throws {
    let data = Data(
        #"{"schemaVersion":1,"generatedAt":"2026-07-16T00:00:00Z","events":[]}"#.utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let snapshot = try decoder.decode(CalendarWidgetSnapshot.self, from: data)

    #expect(snapshot.schemaVersion == 1)
    #expect(snapshot.themeID == nil)
    #expect(snapshot.events.isEmpty)
    #expect(snapshot.covers(dayKey: "2026-07-16"))
}

@Test
func calendarWidgetLegacyEventUsesLogicalIDAsRenderID() throws {
    let eventID = UUID()
    let payload = """
    {
      "schemaVersion": 2,
      "generatedAt": "2026-07-16T00:00:00Z",
      "themeID": "appleSystem",
      "events": [{
        "id": "\(eventID.uuidString)",
        "title": "레거시 일정",
        "startDayKey": "2026-07-16",
        "endDayKey": "2026-07-16",
        "colorID": "blue"
      }]
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let snapshot = try decoder.decode(
        CalendarWidgetSnapshot.self,
        from: Data(payload.utf8)
    )

    #expect(snapshot.events.first?.renderID == eventID)
    #expect(snapshot.totalEventCount(onDayKey: "2026-07-16") == 1)
}

@Test
@MainActor
func calendarWidgetSnapshotPreservesEachDaysDisplayCandidatesBeforeCap() throws {
    let referenceDate = try #require(DayKey.date(from: "2026-07-16"))
    let crowdedDate = try #require(DayKey.date(from: "2026-07-01"))
    let laterDate = try #require(DayKey.date(from: "2026-07-20"))
    let nextMonthDate = try #require(DayKey.date(from: "2026-08-20"))
    let crowdedEvents = (0..<300).compactMap { index in
        CalendarEventRules.makeEvent(
            title: "밀집 일정 \(index)",
            startAt: crowdedDate,
            endAt: crowdedDate,
            now: referenceDate
        )
    }
    let laterEvent = try #require(CalendarEventRules.makeEvent(
        title: "월 후반 일정",
        startAt: laterDate,
        endAt: laterDate,
        now: referenceDate
    ))
    let nextMonthEvent = try #require(CalendarEventRules.makeEvent(
        title: "다음 달 일정",
        startAt: nextMonthDate,
        endAt: nextMonthDate,
        now: referenceDate
    ))

    let snapshot = CalendarWidgetSnapshot.make(
        events: crowdedEvents + [laterEvent, nextMonthEvent],
        referenceDate: referenceDate,
        maximumEventCount: 256
    )

    #expect(snapshot.events.count == 256)
    #expect(snapshot.events.contains { $0.id == laterEvent.id })
    #expect(snapshot.events.contains { $0.id == nextMonthEvent.id })
    #expect(snapshot.totalEventCount(onDayKey: "2026-07-01") == 300)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    #expect(try encoder.encode(snapshot).count < 150 * 1_024)
}

@Test
@MainActor
func calendarWidgetSnapshotUsesNewestLogicalEventRepresentative() throws {
    let referenceDate = try #require(DayKey.date(from: "2026-07-16"))
    let eventID = UUID()
    let older = CalendarEvent(
        id: eventID,
        instanceID: UUID(),
        title: "이전 제목",
        startAt: referenceDate,
        endAt: referenceDate,
        createdAt: referenceDate.addingTimeInterval(-20),
        updatedAt: referenceDate.addingTimeInterval(-10)
    )
    let newer = CalendarEvent(
        id: eventID,
        instanceID: UUID(),
        title: "최신 제목",
        startAt: referenceDate,
        endAt: referenceDate,
        createdAt: referenceDate.addingTimeInterval(-20),
        updatedAt: referenceDate
    )

    let snapshot = CalendarWidgetSnapshot.make(
        events: [older, newer],
        referenceDate: referenceDate
    )

    #expect(snapshot.events.count == 1)
    #expect(snapshot.events.first?.renderID == newer.instanceID)
    #expect(snapshot.events.first?.title == "최신 제목")
    #expect(snapshot.totalEventCount(onDayKey: "2026-07-16") == 1)
}

@Test
func calendarWidgetSnapshotStoreReplacesMalformedPayload() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let fileURL = directoryURL.appendingPathComponent(CalendarWidgetConstants.snapshotFileName)
    try Data("not-json".utf8).write(to: fileURL)
    let snapshot = CalendarWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 100),
        events: []
    )

    #expect(try CalendarWidgetSnapshotStore.writeIfChanged(
        snapshot,
        directoryURL: directoryURL
    ))
    #expect(try CalendarWidgetSnapshotStore.read(directoryURL: directoryURL) == snapshot)
}

@Test
func calendarWidgetSnapshotStoreDoesNotOverwriteFutureSchema() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let fileURL = directoryURL.appendingPathComponent(CalendarWidgetConstants.snapshotFileName)
    let futurePayload = Data(#"{"schemaVersion":999}"#.utf8)
    try futurePayload.write(to: fileURL)
    let snapshot = CalendarWidgetSnapshot(generatedAt: Date(), events: [])

    #expect(throws: CalendarWidgetSnapshotStore.StoreError.unsupportedSchemaVersion(999)) {
        try CalendarWidgetSnapshotStore.writeIfChanged(
            snapshot,
            directoryURL: directoryURL
        )
    }
    #expect(try Data(contentsOf: fileURL) == futurePayload)
}

@Test
func calendarWidgetDeepLinkValidatesAndRoundTripsDayKeys() throws {
    let url = try #require(PlanBaseDeepLink.calendarURL(dayKey: "2026-07-16"))
    #expect(url.absoluteString == "planbase://calendar?date=2026-07-16")
    #expect(PlanBaseDeepLink.calendarDayKey(from: url) == "2026-07-16")
    #expect(
        PlanBaseDeepLink.calendarDayKey(
            from: URL(string: "easytask://calendar?date=2026-07-16")!
        ) == "2026-07-16"
    )
    #expect(PlanBaseDeepLink.calendarURL(dayKey: "2026-02-31") == nil)
    #expect(PlanBaseDeepLink.calendarDayKey(from: URL(string: "https://example.com")!) == nil)
}
