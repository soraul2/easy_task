import Foundation
import Testing
@testable import EasyTaskCore

// Only synthetic values and explicitly isolated temporary files are used.
// These tests never resolve the user's App Group or open a SwiftData store.
private func goalCalendarLockScreenDate(_ key: String = "2026-10-02") throws -> Date {
    try #require(DayKey.date(from: key))
}

private func goalCalendarLockScreenID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

private func goalCalendarLockScreenEvent(
    _ value: Int,
    title: String? = nil,
    start: String = "2026-10-02",
    end: String = "2026-10-02"
) -> CalendarWidgetEventSnapshot {
    CalendarWidgetEventSnapshot(
        id: goalCalendarLockScreenID(value),
        title: title ?? "일정 \(value)",
        startDayKey: start,
        endDayKey: end,
        colorID: CalendarEventPalette.defaultColor
    )
}

private func goalCalendarLockScreenSnapshot(
    events: [CalendarWidgetEventSnapshot] = [],
    counts: [String: Int]? = nil,
    start: String = "2026-10-01",
    end: String = "2026-10-31",
    schema: Int = CalendarWidgetSnapshot.currentSchemaVersion
) throws -> CalendarWidgetSnapshot {
    CalendarWidgetSnapshot(
        schemaVersion: schema,
        generatedAt: try goalCalendarLockScreenDate(),
        coveredStartDayKey: start,
        coveredEndDayKey: end,
        eventCountsByDayKey: counts,
        events: events
    )
}

@Test
func goalCalendarLockScreenShowsAtMostTwoTitlesWithFullMetadataCount() throws {
    let snapshot = try goalCalendarLockScreenSnapshot(
        events: (1...4).map { goalCalendarLockScreenEvent($0) },
        counts: ["2026-10-02": 9]
    )
    let presentation = CalendarLockScreenWidgetRules.presentation(
        snapshot: snapshot, at: try goalCalendarLockScreenDate()
    )
    #expect(presentation.availability == .available)
    #expect(presentation.totalCount == 9)
    #expect(presentation.previews.map(\.title) == ["일정 1", "일정 2"])
    #expect(presentation.remainingCount == 7)
    #expect(presentation.inlineText == "일정 1 · 종일 · +8")
    #expect(presentation.accessibilityText == "오늘 일정 9개, 일정 1, 종일, 일정 2, 종일, 그 외 7개")
    #expect(!presentation.accessibilityText.contains("일정 3"))
}

@Test
func goalCalendarLockScreenMissingPreviewsStillShowsPositiveCount() throws {
    let snapshot = try goalCalendarLockScreenSnapshot(counts: ["2026-10-02": 300])
    let presentation = CalendarLockScreenWidgetRules.presentation(
        snapshot: snapshot, at: try goalCalendarLockScreenDate()
    )
    #expect(presentation.availability == .available)
    #expect(presentation.totalCount == 300)
    #expect(presentation.previews.isEmpty)
    #expect(presentation.inlineText == "일정 300개")
    #expect(presentation.accessibilityText == "오늘 일정 300개")
}

@Test
func goalCalendarLockScreenConfirmsEmptyOnlyInsideReadableCoverage() throws {
    let date = try goalCalendarLockScreenDate()
    let empty = CalendarLockScreenWidgetRules.presentation(
        snapshot: try goalCalendarLockScreenSnapshot(), at: date
    )
    #expect(empty.totalCount == 0)
    #expect(empty.inlineText == "일정 없음")
    #expect(empty.accessibilityText == "오늘 일정 없음")
    let outside = CalendarLockScreenWidgetRules.presentation(
        snapshot: try goalCalendarLockScreenSnapshot(end: "2026-10-01"), at: date
    )
    #expect(outside.availability == .needsRefresh)
    #expect(outside.totalCount == nil)
    #expect(outside.inlineText == "앱을 열어 갱신")
}

@Test(arguments: [
    CalendarLockScreenAvailability.needsRefresh,
    CalendarLockScreenAvailability.requiresAppUpdate
])
func goalCalendarLockScreenUnavailableReadNeverBecomesZero(
    availability: CalendarLockScreenAvailability
) throws {
    let date = try goalCalendarLockScreenDate()
    // A fallback empty snapshot cannot override missing/corrupt/unsupported state.
    let snapshot = try goalCalendarLockScreenSnapshot()
    let presentation = CalendarLockScreenWidgetRules.presentation(
        snapshot: snapshot, at: date, availability: availability
    )
    #expect(presentation.availability == availability)
    #expect(presentation.totalCount == nil)
    #expect(presentation.previews.isEmpty)
    #expect(presentation.inlineText == availability.message)
    #expect(CalendarLockScreenWidgetRules.timelineEntryDates(
        snapshot: snapshot, startingAt: date, availability: availability
    ) == [date])
    let missing = CalendarLockScreenWidgetRules.presentation(snapshot: nil, at: date)
    #expect(missing.availability == .needsRefresh)
    #expect(missing.totalCount == nil)
}

@Test
func goalCalendarLockScreenRejectsFutureSchemaAndMalformedSemanticPayloads() throws {
    let date = try goalCalendarLockScreenDate()
    let future = CalendarLockScreenWidgetRules.presentation(
        snapshot: try goalCalendarLockScreenSnapshot(
            schema: CalendarWidgetSnapshot.currentSchemaVersion + 1
        ), at: date
    )
    #expect(future.availability == .requiresAppUpdate)
    #expect(future.totalCount == nil)
    let malformed = try [
        goalCalendarLockScreenSnapshot(start: "2026-02-30"),
        goalCalendarLockScreenSnapshot(start: "2026-10-03", end: "2026-10-01"),
        goalCalendarLockScreenSnapshot(schema: 0),
        goalCalendarLockScreenSnapshot(counts: ["2026-10-02": -1]),
        goalCalendarLockScreenSnapshot(counts: ["2026-02-30": 1]),
        goalCalendarLockScreenSnapshot(events: [goalCalendarLockScreenEvent(1, title: " \n ")]),
        goalCalendarLockScreenSnapshot(events: [goalCalendarLockScreenEvent(1, start: "2026-02-30")]),
        goalCalendarLockScreenSnapshot(events: [goalCalendarLockScreenEvent(1, end: "2026-10-01")]),
        goalCalendarLockScreenSnapshot(events: [goalCalendarLockScreenEvent(1), goalCalendarLockScreenEvent(1)]),
        goalCalendarLockScreenSnapshot(events: [goalCalendarLockScreenEvent(1)], counts: ["2026-10-02": 0])
    ]
    for snapshot in malformed {
        let presentation = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date)
        #expect(presentation.availability == .needsRefresh)
        #expect(presentation.totalCount == nil)
        #expect(presentation.previews.isEmpty)
        #expect(presentation.accessibilityText == "앱을 열어 갱신")
    }
}

@Test
func goalCalendarLockScreenPrivacyRemovesDetailsFromVisibleAndAccessibleValues() throws {
    let snapshot = try goalCalendarLockScreenSnapshot(events: [
        goalCalendarLockScreenEvent(1, title: "비밀 병원 일정", start: "2026-10-01", end: "2026-10-03"),
        goalCalendarLockScreenEvent(2, title: "비밀 상담")
    ])
    let hidden = CalendarLockScreenWidgetRules.presentation(
        snapshot: snapshot, at: try goalCalendarLockScreenDate(), redactingDetails: true
    )
    #expect(hidden.totalCount == 2)
    #expect(hidden.previews.isEmpty)
    #expect(hidden.inlineText == "일정 2개")
    #expect(hidden.accessibilityText == "오늘 일정 2개")
    #expect(!hidden.accessibilityText.contains("비밀"))
    #expect(!hidden.accessibilityText.contains("10/1"))
}

@Test
func goalCalendarLockScreenUsesInclusiveDateRangesAndAllDayLabels() throws {
    let snapshot = try goalCalendarLockScreenSnapshot(events: [
        goalCalendarLockScreenEvent(1, title: "기간", start: "2026-10-01", end: "2026-10-03"),
        goalCalendarLockScreenEvent(2, title: "종일"),
        goalCalendarLockScreenEvent(3, title: "어제", start: "2026-10-01", end: "2026-10-01")
    ])
    let today = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: try goalCalendarLockScreenDate())
    #expect(today.totalCount == 2)
    #expect(today.previews.map(\.periodText) == ["10/1–10/3", "종일"])
    let last = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: try goalCalendarLockScreenDate("2026-10-03"))
    #expect(last.totalCount == 1)
    #expect(last.previews.map(\.title) == ["기간"])
    let after = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: try goalCalendarLockScreenDate("2026-10-04"))
    #expect(after.totalCount == 0)
    let yearBoundary = try goalCalendarLockScreenSnapshot(
        events: [goalCalendarLockScreenEvent(4, start: "2026-12-31", end: "2027-01-02")],
        start: "2026-12-01", end: "2027-02-28"
    )
    let nextYear = CalendarLockScreenWidgetRules.presentation(
        snapshot: yearBoundary, at: try goalCalendarLockScreenDate("2027-01-01")
    )
    #expect(nextYear.previews.first?.periodText == "2026/12/31–2027/1/2")
}

@Test
func goalCalendarLockScreenCalendarOnlyTimelineUsesMidnightsAndCoverageEnd() throws {
    let startOfDay = try goalCalendarLockScreenDate()
    let now = startOfDay.addingTimeInterval(12 * 60 * 60)
    let snapshot = try goalCalendarLockScreenSnapshot(end: "2026-10-04")
    #expect(snapshot.lockScreenDaySummaries == nil)
    #expect(!snapshot.hasLockScreenCoverage(dayKey: "2026-10-02"))
    let timeline = CalendarLockScreenWidgetRules.timeline(snapshot: snapshot, startingAt: now)
    let dates = timeline.entries.map(\.date)
    #expect(dates == [now, try goalCalendarLockScreenDate("2026-10-03"),
                     try goalCalendarLockScreenDate("2026-10-04"),
                     try goalCalendarLockScreenDate("2026-10-05")])
    #expect(CalendarLockScreenWidgetRules.timelineEntryDates(snapshot: snapshot, startingAt: now) == dates)
    #expect(timeline.entries.map(\.availability) == [.available, .available, .available, .needsRefresh])
    #expect(timeline.refreshDate == dates.last)
    let terminal = try #require(timeline.entries.last)
    let expired = CalendarLockScreenWidgetRules.presentation(
        snapshot: snapshot, at: terminal.date, availability: terminal.availability
    )
    #expect(expired.availability == .needsRefresh)
    #expect(expired.totalCount == nil)
    #expect(expired.previews.isEmpty)
    #expect(expired.inlineText == "앱을 열어 갱신")
}

@Test
func goalCalendarLockScreenTimelineIsBoundedAndChangesItsSelectedDay() throws {
    let now = try goalCalendarLockScreenDate().addingTimeInterval(23 * 60 * 60)
    let snapshot = try goalCalendarLockScreenSnapshot(events: [
        goalCalendarLockScreenEvent(1, title: "오늘"),
        goalCalendarLockScreenEvent(2, title: "내일", start: "2026-10-03", end: "2026-10-03")
    ])
    let timeline = CalendarLockScreenWidgetRules.timeline(snapshot: snapshot, startingAt: now)
    let dates = timeline.entries.map(\.date)
    #expect(dates.count == 9)
    #expect(timeline.entries.filter { $0.availability == .available }.count == 8)
    #expect(dates.first == now)
    #expect(dates.dropFirst().allSatisfy { $0 == DayKey.startOfDay(for: $0) })
    #expect(dates == dates.sorted())
    #expect(CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: dates[0]).previews.map(\.title) == ["오늘"])
    #expect(CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: dates[1]).previews.map(\.title) == ["내일"])
    let terminal = try #require(timeline.entries.last)
    #expect(terminal.date == (try goalCalendarLockScreenDate("2026-10-10")))
    #expect(timeline.refreshDate == terminal.date)
    #expect(terminal.availability == .needsRefresh)
    // Coverage is still readable: the explicit schedule state prevents an
    // old today entry surviving past the bounded timeline when reload is late.
    #expect(snapshot.covers(dayKey: DayKey.key(for: terminal.date)))
    #expect(CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: terminal.date).availability == .available)
    let expired = CalendarLockScreenWidgetRules.presentation(
        snapshot: snapshot, at: terminal.date, availability: terminal.availability
    )
    #expect(expired.totalCount == nil)
    #expect(expired.previews.isEmpty)
    #expect(expired.accessibilityText == "앱을 열어 갱신")
}

@Test
func goalCalendarLockScreenTodayOnlyCoverageStillSchedulesTerminal() throws {
    let now = try goalCalendarLockScreenDate().addingTimeInterval(23 * 60 * 60 + 59 * 60)
    let snapshot = try goalCalendarLockScreenSnapshot(
        events: [goalCalendarLockScreenEvent(1, title: "마지막 날")], end: "2026-10-02"
    )
    let timeline = CalendarLockScreenWidgetRules.timeline(snapshot: snapshot, startingAt: now)
    #expect(timeline.entries.map(\.date) == [now, try goalCalendarLockScreenDate("2026-10-03")])
    #expect(timeline.entries.map(\.availability) == [.available, .needsRefresh])
    #expect(timeline.refreshDate == timeline.entries.last?.date)
    let terminal = try #require(timeline.entries.last)
    #expect(CalendarLockScreenWidgetRules.presentation(
        snapshot: snapshot, at: terminal.date, availability: terminal.availability
    ).totalCount == nil)
}

@Test
func goalCalendarLockScreenFutureInvalidCountSchedulesUnknownAtFirstInvalidDay() throws {
    let now = try goalCalendarLockScreenDate()
    let snapshot = try goalCalendarLockScreenSnapshot(
        events: [goalCalendarLockScreenEvent(1, start: "2026-10-03", end: "2026-10-03")],
        counts: ["2026-10-03": 0]
    )
    let timeline = CalendarLockScreenWidgetRules.timeline(snapshot: snapshot, startingAt: now)
    #expect(timeline.entries.map(\.date) == [now, try goalCalendarLockScreenDate("2026-10-03")])
    #expect(timeline.entries.map(\.availability) == [.available, .needsRefresh])
    #expect(timeline.refreshDate == (try goalCalendarLockScreenDate("2026-10-03")))
}

@Test
func goalCalendarLockScreenInitialUpdateStateDoesNotDowngradeAtNextMidnight() throws {
    let now = try goalCalendarLockScreenDate().addingTimeInterval(12 * 60 * 60)
    let snapshot = try goalCalendarLockScreenSnapshot(schema: 6)
    let timeline = CalendarLockScreenWidgetRules.timeline(snapshot: snapshot, startingAt: now)
    #expect(timeline.entries.count == 1)
    #expect(timeline.entries.first?.date == now)
    #expect(timeline.entries.first?.availability == .requiresAppUpdate)
    #expect(timeline.refreshDate == (try goalCalendarLockScreenDate("2026-10-03")))
}

@Test
func goalCalendarLockScreenPreservesLegacySnapshotAndDeepLinkCompatibility() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(CalendarWidgetSnapshot.self, from: Data("""
    {"schemaVersion": 1, "generatedAt": "2026-10-02T00:00:00Z", "events": [{
      "id": "00000000-0000-0000-0000-000000000001", "title": "레거시 일정",
      "startDayKey": "2026-10-02", "endDayKey": "2026-10-02", "colorID": "blue"
    }]}
    """.utf8))
    let presentation = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: try goalCalendarLockScreenDate())
    #expect(presentation.totalCount == 1)
    #expect(presentation.previews.first?.title == "레거시 일정")
    #expect(CalendarWidgetConstants.calendarLockScreenKind != CalendarWidgetConstants.lockScreenKind)
    #expect(CalendarWidgetConstants.calendarLockScreenKind != CalendarWidgetConstants.kind)
    let url = try #require(PlanBaseDeepLink.calendarTodayURL())
    #expect(PlanBaseDeepLink.calendarRoute(from: url) == .today)
    #expect(PlanBaseDeepLink.calendarRoute(from: url)?.resolvedDayKey(todayDayKey: "2026-10-03") == "2026-10-03")
}

@Test
@MainActor
func goalCalendarLockScreenUsesLatestRepresentativeBeforeDateVisibility() throws {
    let date = try goalCalendarLockScreenDate()
    let tomorrow = try goalCalendarLockScreenDate("2026-10-03")
    let logicalID = goalCalendarLockScreenID(1)
    let older = CalendarEvent(id: logicalID, instanceID: goalCalendarLockScreenID(101),
                              title: "이전 일정", startAt: date, endAt: date,
                              createdAt: date, updatedAt: date)
    let newer = CalendarEvent(id: logicalID, instanceID: goalCalendarLockScreenID(102),
                              title: "수정 일정", startAt: tomorrow, endAt: tomorrow,
                              createdAt: date, updatedAt: date.addingTimeInterval(1))
    for events in [[older, newer], [newer, older]] {
        let snapshot = CalendarWidgetSnapshot.make(events: events, referenceDate: date)
        let today = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date)
        #expect(today.totalCount == 0)
        let next = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: tomorrow)
        #expect(next.totalCount == 1)
        #expect(next.previews.map(\.title) == ["수정 일정"])
    }
    newer.title = " \n "
    let blankLatest = CalendarWidgetSnapshot.make(events: [older, newer], referenceDate: date)
    #expect(CalendarLockScreenWidgetRules.presentation(snapshot: blankLatest, at: date).totalCount == 0)
    #expect(CalendarLockScreenWidgetRules.presentation(snapshot: blankLatest, at: tomorrow).totalCount == 0)
}

@Test
@MainActor
func goalCalendarLockScreenUsesUncappedProducerCountEvenWithSinglePreview() throws {
    let date = try goalCalendarLockScreenDate()
    let events = (1...5).map { index in
        CalendarEvent(id: goalCalendarLockScreenID(index), title: "동일 제목", startAt: date, endAt: date)
    }
    let snapshot = CalendarWidgetSnapshot.make(events: events, referenceDate: date, maximumEventCount: 1)
    let presentation = CalendarLockScreenWidgetRules.presentation(snapshot: snapshot, at: date)
    #expect(presentation.totalCount == 5)
    #expect(presentation.previews.count == 1)
    #expect(presentation.remainingCount == 4)
    #expect(presentation.inlineText == "동일 제목 · 종일 · +4")
}

@Test
func goalCalendarLockScreenStoreRejectsCorruptAndFutureFilesInIsolatedDirectory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent(CalendarWidgetConstants.snapshotFileName)
    #expect(try CalendarWidgetSnapshotStore.read(directoryURL: directory) == nil)
    try Data("{broken".utf8).write(to: url)
    #expect(throws: (any Error).self) {
        try CalendarWidgetSnapshotStore.read(directoryURL: directory)
    }
    let version = CalendarWidgetSnapshot.currentSchemaVersion + 1
    try Data("{\"schemaVersion\":\(version)}".utf8).write(to: url)
    #expect(throws: CalendarWidgetSnapshotStore.StoreError.unsupportedSchemaVersion(version)) {
        try CalendarWidgetSnapshotStore.read(directoryURL: directory)
    }
}

private func goalCalendarLockScreenJSONObject(
    _ snapshot: CalendarWidgetSnapshot
) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try #require(JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any])
}

private func goalCalendarLockScreenDecodeJSONObject(
    _ object: [String: Any]
) throws -> CalendarWidgetSnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
        CalendarWidgetSnapshot.self,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}

@Test(arguments: ["coveredStartDayKey", "coveredEndDayKey", "eventCountsByDayKey"], [false, true])
func goalCalendarLockScreenDecodedV5RejectsEachMissingOrNullMetadataField(
    field: String, replacingWithNull: Bool
) throws {
    let date = try goalCalendarLockScreenDate()
    let complete = try goalCalendarLockScreenSnapshot(
        events: [goalCalendarLockScreenEvent(1)], counts: ["2026-10-02": 9]
    )
    var object = try goalCalendarLockScreenJSONObject(complete)
    if replacingWithNull {
        object[field] = NSNull()
    } else {
        object.removeValue(forKey: field)
    }
    let decoded = try goalCalendarLockScreenDecodeJSONObject(object)
    #expect(decoded.schemaVersion == 5)
    #expect(!decoded.hasCompleteCalendarMetadata)
    let presentation = CalendarLockScreenWidgetRules.presentation(snapshot: decoded, at: date)
    #expect(presentation.availability == .needsRefresh)
    #expect(presentation.totalCount == nil)
    #expect(presentation.previews.isEmpty)
    #expect(presentation.accessibilityText == "앱을 열어 갱신")
    let timeline = CalendarLockScreenWidgetRules.timeline(snapshot: decoded, startingAt: date)
    #expect(timeline.entries.count == 1)
    #expect(timeline.entries.first?.availability == .needsRefresh)
}

@Test
func goalCalendarLockScreenDecodedV5EmptyMetadataIsKnownZeroAndFormatStaysUnchanged() throws {
    let date = try goalCalendarLockScreenDate()
    // Direct initialization materializes complete metadata even when defaults
    // were requested. An explicitly empty sparse dictionary is also complete.
    let snapshot = CalendarWidgetSnapshot(generatedAt: date, events: [])
    let object = try goalCalendarLockScreenJSONObject(snapshot)
    #expect(Set(object.keys) == Set([
        "schemaVersion", "generatedAt", "coveredStartDayKey", "coveredEndDayKey",
        "eventCountsByDayKey", "events"
    ]))
    #expect((object["eventCountsByDayKey"] as? [String: Int])?.isEmpty == true)
    let decoded = try goalCalendarLockScreenDecodeJSONObject(object)
    #expect(decoded.hasCompleteCalendarMetadata)
    #expect(decoded == snapshot)
    #expect(decoded.hasSameContent(as: snapshot))
    #expect(decoded.eventCountsByDayKey["2026-10-02"] == nil)
    let presentation = CalendarLockScreenWidgetRules.presentation(snapshot: decoded, at: date)
    #expect(presentation.availability == .available)
    #expect(presentation.totalCount == 0)
    #expect(presentation.accessibilityText == "오늘 일정 없음")

    var sparseObject = object
    sparseObject["eventCountsByDayKey"] = ["2026-10-03": 513]
    let sparse = try goalCalendarLockScreenDecodeJSONObject(sparseObject)
    #expect(CalendarLockScreenWidgetRules.presentation(snapshot: sparse, at: date).totalCount == 0)
    #expect(CalendarLockScreenWidgetRules.presentation(
        snapshot: sparse, at: try goalCalendarLockScreenDate("2026-10-03")
    ).totalCount == 513)
}

@Test
func goalCalendarLockScreenDecodedV5MissingCountCannotUndercountPresentPreview() throws {
    let date = try goalCalendarLockScreenDate()
    let snapshot = try goalCalendarLockScreenSnapshot(
        events: [goalCalendarLockScreenEvent(1)], counts: [:]
    )
    let decoded = try goalCalendarLockScreenDecodeJSONObject(goalCalendarLockScreenJSONObject(snapshot))
    #expect(decoded.hasCompleteCalendarMetadata)
    let presentation = CalendarLockScreenWidgetRules.presentation(snapshot: decoded, at: date)
    #expect(presentation.availability == .needsRefresh)
    #expect(presentation.totalCount == nil)
    #expect(presentation.previews.isEmpty)
}

@Test(arguments: [1, 2, 3, 4])
func goalCalendarLockScreenLegacyMetadataFallbackStillDecodesAndDisplays(schema: Int) throws {
    let date = try goalCalendarLockScreenDate()
    let snapshot = CalendarWidgetSnapshot(
        schemaVersion: schema, generatedAt: date, events: [goalCalendarLockScreenEvent(1)]
    )
    var object = try goalCalendarLockScreenJSONObject(snapshot)
    for field in ["coveredStartDayKey", "coveredEndDayKey", "eventCountsByDayKey"] {
        object.removeValue(forKey: field)
    }
    let decoded = try goalCalendarLockScreenDecodeJSONObject(object)
    #expect(decoded == snapshot)
    #expect(decoded.hasSameContent(as: snapshot))
    let presentation = CalendarLockScreenWidgetRules.presentation(snapshot: decoded, at: date)
    #expect(presentation.availability == .available)
    #expect(presentation.totalCount == 1)
    #expect(presentation.previews.map(\.title) == ["일정 1"])
    object["events"] = [] as [Any]
    let empty = try goalCalendarLockScreenDecodeJSONObject(object)
    #expect(CalendarLockScreenWidgetRules.presentation(snapshot: empty, at: date).totalCount == 0)
}

@Test
@MainActor
func goalCalendarLockScreenDefaultCapRoundTripKeepsAll513EventsInCount() throws {
    let date = try goalCalendarLockScreenDate()
    let events = (1...513).map { index in
        CalendarEvent(id: goalCalendarLockScreenID(index), title: "동일 제목", startAt: date, endAt: date)
    }
    let snapshot = CalendarWidgetSnapshot.make(events: events, referenceDate: date)
    #expect(snapshot.events.count == 256)
    let decoded = try goalCalendarLockScreenDecodeJSONObject(goalCalendarLockScreenJSONObject(snapshot))
    #expect(decoded == snapshot)
    #expect(decoded.hasCompleteCalendarMetadata)
    #expect(decoded.lockScreenDaySummaries == nil)
    let presentation = CalendarLockScreenWidgetRules.presentation(snapshot: decoded, at: date)
    #expect(presentation.availability == .available)
    #expect(presentation.totalCount == 513)
    #expect(presentation.previews.count == 2)
    #expect(Set(presentation.previews.map(\.id)).count == 2)
    #expect(presentation.remainingCount == 511)
}

@Test
func goalCalendarLockScreenNormalWriteRepairsMissingV5MetadataEvenWithEqualFallbackValues() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let date = try goalCalendarLockScreenDate()
    let complete = CalendarWidgetSnapshot(generatedAt: date, events: [])
    var object = try goalCalendarLockScreenJSONObject(complete)
    object.removeValue(forKey: "eventCountsByDayKey")
    let url = directory.appendingPathComponent(CalendarWidgetConstants.snapshotFileName)
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    let incomplete = try #require(try CalendarWidgetSnapshotStore.read(directoryURL: directory))
    #expect(incomplete.coveredStartDayKey == complete.coveredStartDayKey)
    #expect(incomplete.coveredEndDayKey == complete.coveredEndDayKey)
    #expect(incomplete.eventCountsByDayKey == complete.eventCountsByDayKey)
    #expect(!incomplete.hasCompleteCalendarMetadata)
    #expect(!incomplete.hasSameContent(as: complete))
    #expect(!complete.hasSameContent(as: incomplete))
    #expect(CalendarLockScreenWidgetRules.presentation(snapshot: incomplete, at: date).totalCount == nil)

    #expect(try CalendarWidgetSnapshotStore.writeIfChanged(complete, directoryURL: directory))
    let repaired = try #require(try CalendarWidgetSnapshotStore.read(directoryURL: directory))
    #expect(repaired == complete)
    #expect(repaired.hasCompleteCalendarMetadata)
    #expect(CalendarLockScreenWidgetRules.presentation(snapshot: repaired, at: date).totalCount == 0)
    #expect(try CalendarWidgetSnapshotStore.writeIfChanged(complete, directoryURL: directory) == false)
}
