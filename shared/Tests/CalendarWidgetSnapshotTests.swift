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

    #expect(snapshot.schemaVersion == 2)
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
}

@Test
func calendarWidgetDeepLinkValidatesAndRoundTripsDayKeys() throws {
    let url = try #require(EasyTaskDeepLink.calendarURL(dayKey: "2026-07-16"))
    #expect(url.absoluteString == "easytask://calendar?date=2026-07-16")
    #expect(EasyTaskDeepLink.calendarDayKey(from: url) == "2026-07-16")
    #expect(EasyTaskDeepLink.calendarURL(dayKey: "2026-02-31") == nil)
    #expect(EasyTaskDeepLink.calendarDayKey(from: URL(string: "https://example.com")!) == nil)
}
